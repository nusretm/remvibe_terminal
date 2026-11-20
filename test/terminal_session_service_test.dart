import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:remvibe_terminal/remvibe_terminal.dart';
import 'package:test/test.dart';

final class _FakeProcess implements HostedTerminalProcess {
  _FakeProcess(this.processId);

  @override
  final int processId;
  final _out = StreamController<Uint8List>.broadcast();
  final _done = Completer<int?>();
  final writes = <List<int>>[];
  bool closed = false;

  @override
  Stream<Uint8List> get output => _out.stream;
  @override
  Future<int?> get exitCode => _done.future;
  @override
  bool get isClosed => closed;

  void emit(String text) => _out.add(Uint8List.fromList(utf8.encode(text)));

  @override
  void write(List<int> bytes) => writes.add(List.of(bytes));
  @override
  void resize({required int columns, required int rows}) {}
  @override
  void interrupt() {}

  Future<void> finish(int code) async {
    if (!_done.isCompleted) _done.complete(code);
    await _out.close();
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (!_done.isCompleted) _done.complete(null);
    await _out.close();
  }
}

void main() {
  late List<_FakeProcess> processes;
  late TerminalSessionService service;
  var clock = DateTime.utc(2026, 11, 20);

  setUp(() {
    processes = [];
    clock = DateTime.utc(2026, 11, 20);
    service = TerminalSessionService.withFactory(
      maximumSessions: 4,
      maximumReplayBytes: 8,
      detachedIdleTimeout: const Duration(minutes: 10),
      sweepInterval: const Duration(days: 1),
      clock: () => clock,
      processFactory: ({
        required commandLine,
        required columns,
        required rows,
        required maximumBufferBytes,
      }) {
        final process = _FakeProcess(processes.length + 100);
        processes.add(process);
        return process;
      },
    );
  });

  tearDown(() async {
    await service.close();
  });

  test('four independent terminals, list, detach and reattach', () async {
    final first = service.newTerminal(sessionId: 's1', commandLine: 'powershell');
    final second = service.newTerminal(sessionId: 's2', commandLine: 'cmd');
    final third = service.newTerminal(sessionId: 's3', commandLine: 'cmd');
    final fourth = service.newTerminal(sessionId: 's4', commandLine: 'cmd');

    expect(service.listSessions().map((s) => s.sessionId),
        ['s1', 's2', 's3', 's4']);
    expect(service.activeSessionCount, 4);
    expect(() => service.newTerminal(sessionId: 's5', commandLine: 'cmd'),
        throwsStateError);

    await first.detach();
    expect(service.contains('s1'), isTrue);
    expect(processes[0].closed, isFalse);
    expect(service.listSessions().first.attached, isFalse);

    final resumed = service.attach('s1');
    expect(resumed.isAttached, isTrue);
    resumed.write([0x41]);
    expect(processes[0].writes, [[0x41]]);
    await resumed.detach();
    await second.detach();
    await third.detach();
    await fourth.detach();
  });

  test('retained output and sequence resume across detach', () async {
    final first = service.newTerminal(sessionId: 's1', commandLine: 'powershell');
    final initial = first.output.listen((_) {});
    processes[0].emit('ab');
    await Future<void>.delayed(Duration.zero);
    await initial.cancel();
    await first.detach();

    processes[0].emit('cd');
    await Future<void>.delayed(Duration.zero);
    final resume = service.attach('s1', afterSequence: 1);
    final frames = <TerminalOutputFrame>[];
    final subscriber = resume.output.listen(frames.add);
    await Future<void>.delayed(Duration.zero);
    expect(frames.map((f) => utf8.decode(f.bytes)), ['cd']);
    expect(frames.single.sequence, 2);

    await subscriber.cancel();
    await resume.detach();
    expect(service.listSessions().single.lastOutputSequence, 2);
  });

  test('bounded output replay flags truncation', () async {
    final first = service.newTerminal(sessionId: 's1', commandLine: 'powershell');
    await first.detach();
    processes[0].emit('abcdef');
    await Future<void>.delayed(Duration.zero);
    processes[0].emit('ghij');
    await Future<void>.delayed(Duration.zero);
    final state = service.listSessions().single;
    expect(state.outputTruncated, isTrue);
    expect(state.firstRetainedSequence, 2);

    final resumed = service.attach('s1');
    final frames = <String>[];
    final subscription =
        resumed.output.listen((frame) => frames.add(utf8.decode(frame.bytes)));
    await Future<void>.delayed(Duration.zero);
    expect(frames, ['ghij']);
    await subscription.cancel();
    await resumed.detach();
  });

  test('idle reaping is detached-only and output does not extend TTL', () async {
    final first = service.newTerminal(sessionId: 's1', commandLine: 'powershell');
    clock = clock.add(const Duration(hours: 1));
    await service.expireIdleSessions();
    expect(service.contains('s1'), isTrue);
    await first.detach();

    clock = clock.add(const Duration(minutes: 9));
    processes[0].emit('noisy background output');
    await Future<void>.delayed(Duration.zero);
    await service.expireIdleSessions();
    expect(service.contains('s1'), isTrue);

    clock = clock.add(const Duration(minutes: 2));
    await service.expireIdleSessions();
    expect(service.contains('s1'), isFalse);
    expect(processes[0].closed, isTrue);
    expect(() => service.attach('s1'), throwsStateError);
  });

  test('reattach resets idle timer, termination leaves other alive', () async {
    final first = service.newTerminal(sessionId: 's1', commandLine: 'powershell');
    final second = service.newTerminal(sessionId: 's2', commandLine: 'cmd');
    await first.detach();
    clock = clock.add(const Duration(minutes: 9));
    final resumed = service.attach('s1');
    await resumed.detach();
    clock = clock.add(const Duration(minutes: 2));
    await service.expireIdleSessions();
    expect(service.contains('s1'), isTrue);

    await service.terminateSession('s1');
    expect(processes[0].closed, isTrue);
    expect(processes[1].closed, isFalse);
    expect(service.listSessions().single.sessionId, 's2');
    await second.detach();
  });

  test('running detached command survives, unknown uses fail-safe', () async {
    final first = service.newTerminal(sessionId: 'running', commandLine: 'powershell');
    final second = service.newTerminal(sessionId: 'unknown', commandLine: 'cmd');
    service.setCommandActivity(
      'running',
      HostedTerminalCommandActivity.running,
    );
    service.setCommandActivity(
      'unknown',
      HostedTerminalCommandActivity.unknown,
    );
    await first.detach();
    await second.detach();

    clock = clock.add(const Duration(minutes: 11));
    await service.expireIdleSessions();
    expect(service.contains('running'), isTrue);
    expect(service.contains('unknown'), isTrue);

    clock = clock.add(const Duration(minutes: 20));
    await service.expireIdleSessions();
    expect(service.contains('running'), isTrue);
    expect(service.contains('unknown'), isFalse);

    service.setCommandActivity(
      'running',
      HostedTerminalCommandActivity.idle,
    );
    clock = clock.add(const Duration(minutes: 11));
    await service.expireIdleSessions();
    expect(service.contains('running'), isFalse);
  });

  test('registered singleton supports items/newTerminal without creating a second host', () async {
    expect(() => TerminalSessionService(), throwsStateError);
    expect(identical(TerminalSessionService.register(service), service), isTrue);
    expect(identical(TerminalSessionService(), service), isTrue);

    final first = TerminalSessionService().newTerminal(
      sessionId: 'a',
      commandLine: 'powershell',
    );
    final before = TerminalSessionService().items;
    expect(before.single.sessionId, 'a');
    expect(() => before.clear(), throwsUnsupportedError);

    final second = TerminalSessionService().newTerminal(
      sessionId: 'b',
      commandLine: 'cmd',
    );
    expect(before, hasLength(1)); // snapshots do not mutate under UI readers
    expect(TerminalSessionService().items.map((s) => s.sessionId), ['a', 'b']);

    final independent = TerminalSessionService.withFactory(
      processFactory: ({
        required commandLine,
        required columns,
        required rows,
        required maximumBufferBytes,
      }) => _FakeProcess(999),
    );
    expect(
      () => TerminalSessionService.register(independent),
      throwsStateError,
    );
    await independent.close();
    await first.detach();
    await second.detach();
    await service.close();
    expect(() => TerminalSessionService(), throwsStateError);
  });

  test('itemsChanged emits create, detach, activity and termination snapshots',
      () async {
    final changes = <List<HostedTerminalInfo>>[];
    final sub = service.itemsChanged.listen(changes.add);
    final first = service.newTerminal(sessionId: 'a', commandLine: 'cmd');
    await Future<void>.delayed(Duration.zero);
    expect(changes.single.single.attached, isTrue);

    await first.detach();
    service.setCommandActivity('a', HostedTerminalCommandActivity.running);
    await Future<void>.delayed(Duration.zero);
    expect(changes[1].single.attached, isFalse);
    expect(changes[2].single.commandActivity,
        HostedTerminalCommandActivity.running);

    await service.terminateSession('a');
    await Future<void>.delayed(Duration.zero);
    expect(changes.last, isEmpty);
    await sub.cancel();
  });

  test('natural process exit removes session from discovery', () async {
    final session = service.newTerminal(sessionId: 's1', commandLine: 'cmd');
    await processes[0].finish(0);
    await Future<void>.delayed(Duration.zero);
    expect(service.contains('s1'), isFalse);
    expect(session.isAttached, isFalse);
  });
}
