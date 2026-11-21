import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:remvibe_terminal/remvibe_terminal.dart';
import 'package:test/test.dart';

final class _FakeTerminalProcess implements HostedTerminalProcess {
  _FakeTerminalProcess(this.processId);
  @override
  final int processId;

  late final _output = StreamController<Uint8List>(
    onListen: () => outputSubscriptions++,
  );
  final _exit = Completer<int?>();
  final writes = <List<int>>[];
  bool closed = false;
  int outputSubscriptions = 0;

  @override
  Stream<Uint8List> get output => _output.stream;
  @override
  Future<int?> get exitCode => _exit.future;
  @override
  bool get isClosed => closed;

  void emit(String text) => _output.add(Uint8List.fromList(utf8.encode(text)));

  @override
  void write(List<int> bytes) => writes.add(List.of(bytes));
  @override
  void resize({required int columns, required int rows}) {}
  @override
  void interrupt() {}

  Future<void> finish(int code) async {
    if (!_exit.isCompleted) _exit.complete(code);
    if (!_output.isClosed) await _output.close();
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (!_exit.isCompleted) _exit.complete(null);
    if (!_output.isClosed) await _output.close();
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late List<_FakeTerminalProcess> processes;
  late TerminalSessionService service;
  var clock = DateTime.utc(2026, 11, 21);

  setUp(() {
    processes = [];
    clock = DateTime.utc(2026, 11, 21);
    service = TerminalSessionService.withFactory(
      maximumSessions: 4,
      maximumReplayBytes: 4,
      sweepInterval: const Duration(days: 1),
      clock: () => clock,
      processFactory: ({
        required commandLine,
        required columns,
        required rows,
        required maximumBufferBytes,
      }) {
        final fake = _FakeTerminalProcess(processes.length + 100);
        processes.add(fake);
        return fake;
      },
    );
  });

  tearDown(() async => service.close());

  test('two independent PTYs output concurrently; two viewers share one PTY',
      () async {
    final first = service.newTerminal(sessionId: 'one', commandLine: 'cmd');
    final second = service.newTerminal(sessionId: 'two', commandLine: 'cmd');
    final a = service.findTerminal('one')!;
    final b = service.findTerminal('two')!;
    final x = <TerminalStreamEvent>[];
    final y = <TerminalStreamEvent>[];
    final z = <TerminalStreamEvent>[];
    final a1 = a.registerHandler(onTerminalStream: (_, e) => x.add(e));
    final a2 = a.registerHandler(onTerminalStream: (_, e) => y.add(e));
    final b1 = b.registerHandler(onTerminalStream: (_, e) => z.add(e));

    processes[0].emit('a');
    processes[1].emit('b');
    await _flush();
    expect(x.single.terminalId, 'one');
    expect(y.single.sequence, 1);
    expect(z.single.terminalId, 'two');
    expect(z.single.sequence, 1);
    expect(utf8.decode(x.single.bytes), 'a');
    expect(utf8.decode(y.single.bytes), 'a');
    expect(utf8.decode(z.single.bytes), 'b');

    await a.unregisterHandler(a1);
    processes[0].emit('c');
    processes[1].emit('d');
    await _flush();
    expect(x, hasLength(1));
    expect(y.map((e) => e.sequence), [1, 2]);
    expect(z.map((e) => e.sequence), [1, 2]);
    expect(processes.every((p) => !p.closed), isTrue);
    expect(processes.map((p) => p.outputSubscriptions), [1, 1]);
    await a.unregisterHandler(a2);
    await b.unregisterHandler(b1);
    await first.detach();
    await second.detach();
  });

  test('bounded replay reports an inclusive missing-sequence gap', () async {
    final attachment =
        service.newTerminal(sessionId: 's', commandLine: 'cmd');
    await attachment.detach();
    processes[0].emit('aa');
    processes[0].emit('bb');
    processes[0].emit('cc');
    await _flush();
    final seen = <TerminalStreamEvent>[];
    final session = service.findTerminal('s')!;
    final token = session.registerHandler(
      onTerminalStream: (_, event) => seen.add(event),
    );
    await _flush();
    expect(seen.map((e) => e.sequence), [1, 2, 3]);
    expect(seen.first.isGap, isTrue);
    expect(seen.first.gapFromSequence, 1);
    expect(seen.first.gapToSequence, 1);
    expect(seen.skip(1).map((e) => e.replayed), [true, true]);
    expect(seen.skip(1).map((e) => utf8.decode(e.bytes)), ['bb', 'cc']);
    await session.unregisterHandler(token);
  });

  test('register replay is before live output with no subscription race',
      () async {
    service.newTerminal(sessionId: 's', commandLine: 'cmd');
    processes[0].emit('a');
    await _flush();
    final session = service.findTerminal('s')!;
    final events = <TerminalStreamEvent>[];
    final token = session.registerHandler(
      onTerminalStream: (_, event) => events.add(event),
    );
    processes[0].emit('b');
    await _flush();
    expect(events.map((e) => e.sequence), [1, 2]);
    expect(events.map((e) => e.replayed), [true, false]);
    expect(events.every((e) => !e.isGap), isTrue);
    await session.unregisterHandler(token);
  });

  test('slow watcher queue is bounded and does not stall another watcher',
      () async {
    service.newTerminal(sessionId: 's', commandLine: 'cmd');
    final session = service.findTerminal('s')!;
    final releaseSlow = Completer<void>();
    final slowEvents = <TerminalStreamEvent>[];
    final fastEvents = <TerminalStreamEvent>[];
    final slow = session.registerHandler(
      onTerminalStream: (_, event) async {
        if (!event.isGap && event.sequence == 1) {
          await releaseSlow.future;
        }
        slowEvents.add(event);
      },
    );
    final fast = session.registerHandler(
      onTerminalStream: (_, event) => fastEvents.add(event),
    );
    processes[0].emit('a');
    await _flush();
    for (var i = 2; i <= 145; i++) {
      processes[0].emit('x');
      await _flush(); // Fast viewer drains while slow viewer is still awaiting.
    }
    expect(fastEvents.where((e) => !e.isGap), hasLength(145));
    expect(slowEvents, isEmpty);

    releaseSlow.complete();
    await _flush();
    expect(slowEvents.first.sequence, 1);
    expect(slowEvents.any((e) => e.isGap), isTrue);
    expect(slowEvents.last.sequence, 145);
    await session.unregisterHandler(slow);
    await session.unregisterHandler(fast);
  });

  test('throwing callback does not stop another watcher or later output',
      () async {
    service.newTerminal(sessionId: 's', commandLine: 'cmd');
    final session = service.findTerminal('s')!;
    final events = <TerminalStreamEvent>[];
    final failing = session.registerHandler(
      onTerminalStream: (_, event) => throw StateError('bad subscriber'),
    );
    final healthy = session.registerHandler(
      onTerminalStream: (_, event) => events.add(event),
    );
    processes[0].emit('a');
    processes[0].emit('b');
    await _flush();
    expect(events.map((e) => e.sequence), [1, 2]);
    await session.unregisterHandler(failing);
    await session.unregisterHandler(healthy);
  });

  test('local read-only observation never claims control or kills process',
      () async {
    final attachment = service.newTerminal(sessionId: 's', commandLine: 'cmd');
    final session = service.findTerminal('s')!;
    final readonly = TerminalHandlerLocal(terminal: session);
    final controller = TerminalHandlerLocal(
      terminal: session,
      controller: attachment,
    );
    final received = <TerminalStreamEvent>[];
    final token =
        readonly.registerHandler(onTerminalStream: (_, e) => received.add(e));
    await expectLater(readonly.input([65]), throwsStateError);
    await controller.input([65]);
    expect(processes.single.writes, [[65]]);
    await readonly.unregisterHandler(token);
    await controller.detach();
    expect(processes.single.closed, isFalse);
    processes.single.emit('x');
    await _flush();
    expect(received, isEmpty);
    expect(service.contains('s'), isTrue);
  });

  test('typed lifecycle, explicit activity and process exit code', () async {
    final attachment = service.newTerminal(sessionId: 's', commandLine: 'cmd');
    final session = service.findTerminal('s')!;
    final states = <TerminalStateEvent>[];
    final token =
        session.registerHandler(onTerminalState: (_, event) => states.add(event));
    await _flush();
    expect(states.map((e) => e.kind), [
      TerminalStateEventKind.created,
      TerminalStateEventKind.snapshot,
    ]);
    expect(states.first.replayed, isTrue);
    expect(states.last.controllerAttached, isTrue);
    service.setCommandActivity('s', HostedTerminalCommandActivity.running);
    processes.single.emit('x');
    await _flush();
    expect(states.last.commandState, TerminalCommandState.busy);
    expect(states.last.kind, TerminalStateEventKind.commandActivityChanged);

    await attachment.detach();
    await _flush();
    expect(states.last.kind, TerminalStateEventKind.detached);
    expect(states.last.controllerAttached, isFalse);
    await processes.single.finish(7);
    await _flush();
    expect(states.last.kind, TerminalStateEventKind.exited);
    expect(states.last.exitCode, 7);
    expect(service.findTerminal('s'), isNull);
    await session.unregisterHandler(token);
  });

  test('explicit termination and idle expiry report distinct reasons',
      () async {
    final first = service.newTerminal(sessionId: 'a', commandLine: 'cmd');
    final second = service.newTerminal(sessionId: 'b', commandLine: 'cmd');
    final a = service.findTerminal('a')!;
    final b = service.findTerminal('b')!;
    final reasonsA = <TerminalStateEventKind>[];
    final reasonsB = <TerminalStateEventKind>[];
    a.registerHandler(onTerminalState: (_, e) => reasonsA.add(e.kind));
    b.registerHandler(onTerminalState: (_, e) => reasonsB.add(e.kind));
    await first.detach();
    await second.detach();
    await service.terminateSession('a');
    clock = clock.add(const Duration(minutes: 11));
    await service.expireIdleSessions();
    await _flush();
    expect(reasonsA.last, TerminalStateEventKind.terminated);
    expect(reasonsB.last, TerminalStateEventKind.expired);
    expect(service.items, isEmpty);
  });

  test('unregister during terminal teardown cancels queued callbacks',
      () async {
    service.newTerminal(sessionId: 's', commandLine: 'cmd');
    final session = service.findTerminal('s')!;
    final blocker = Completer<void>();
    final seen = <TerminalStateEventKind>[];
    final token = session.registerHandler(
      onTerminalState: (_, event) async {
        seen.add(event.kind);
        if (event.kind == TerminalStateEventKind.created) {
          await blocker.future;
        }
      },
    );
    await _flush();
    expect(seen, [TerminalStateEventKind.created]);
    await service.terminateSession('s');
    await session.unregisterHandler(token);
    blocker.complete();
    await _flush();
    expect(seen, [TerminalStateEventKind.created]);
    expect(processes.single.closed, isTrue);
  });

  test('registered lookup shares service; independent test host lookup works',
      () async {
    service.newTerminal(sessionId: 's', commandLine: 'cmd');
    expect(service.findTerminal('s'), isNotNull);
    expect(TerminalSessionService.register(service), same(service));
    expect(TerminalSessionService.getTerminal('s'),
        same(service.findTerminal('s')));
    expect(TerminalSessionService.getTerminal('missing'), isNull);
  });
}
