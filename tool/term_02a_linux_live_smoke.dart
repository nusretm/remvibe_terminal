import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:remvibe_terminal/remvibe_terminal.dart';

/// Real Linux PTY acceptance smoke. Runs Bash, not a simulated event source.
/// Execute on Ubuntu: dart run tool/term_02a_linux_live_smoke.dart
Future<void> main() async {
  if (!Platform.isLinux) {
    throw UnsupportedError('TERM-02A native smoke requires Linux.');
  }
  final engine = RemVibeTerminal.currentPlatform();
  final service = TerminalSessionService.withEngine(
    engine: engine,
    maximumSessions: 4,
    maximumReplayBytes: 64 * 1024,
  );
  final subscriptions = <(TerminalSession, TerminalHandlerRegistration)>[];
  try {
    final first = service.newTerminal(
      commandLine: 'exec /bin/bash --noprofile --norc -i',
      columns: 80,
      rows: 24,
    );
    final second = service.newTerminal(
      commandLine: 'exec /bin/bash --noprofile --norc -i',
      columns: 80,
      rows: 24,
    );
    final firstTerminal = service.findTerminal(first.sessionId)!;
    final secondTerminal = service.findTerminal(second.sessionId)!;
    final observerA = _Capture();
    final observerMirror = _Capture();
    final observerB = _Capture();

    final a = firstTerminal.registerHandler(
      onTerminalStream: (_, e) => observerA.receive(e),
    );
    final mirror = firstTerminal.registerHandler(
      onTerminalStream: (_, e) => observerMirror.receive(e),
    );
    final b = secondTerminal.registerHandler(
      onTerminalStream: (_, e) => observerB.receive(e),
    );
    subscriptions.addAll([
      (firstTerminal, a),
      (firstTerminal, mirror),
      (secondTerminal, b),
    ]);

    first.write(utf8.encode('printf "RVTERM_REAL_LINUX_A\\n"\r'));
    second.write(utf8.encode('printf "RVTERM_REAL_LINUX_B\\n"\r'));
    await observerA.waitFor('RVTERM_REAL_LINUX_A');
    await observerMirror.waitFor('RVTERM_REAL_LINUX_A');
    await observerB.waitFor('RVTERM_REAL_LINUX_B');
    if (first.processId == second.processId) {
      throw StateError('Distinct PTYs unexpectedly share one PID.');
    }
    print('LINUX TWO PTYS / TWO VIEWERS ONE PTY PASS');

    // Each controlling attachment is separate from any observer registration.
    first.write(utf8.encode('echo RVTERM_PID=\$\$\r'));
    await observerA.waitFor('RVTERM_PID=${first.processId}');
    await observerMirror.waitFor('RVTERM_PID=${first.processId}');
    print('LINUX NATIVE CHILD PID PASS');

    first.resize(columns: 101, rows: 39);
    first.write(utf8.encode('stty size\r'));
    await observerA.waitFor('39 101');
    print('LINUX PTY RESIZE PASS');

    // Unregistering the mirror does not stop output or the OS process.
    await firstTerminal.unregisterHandler(mirror);
    subscriptions.removeWhere((pair) => identical(pair.$2, mirror));
    final mirrorSnapshot = observerMirror.text;
    first.write(utf8.encode('echo RVTERM_AFTER_UNREGISTER\r'));
    await observerA.waitFor('RVTERM_AFTER_UNREGISTER');
    if (observerMirror.text != mirrorSnapshot) {
      throw StateError('Unregistered mirror received further output.');
    }
    if (!service.contains(first.sessionId)) {
      throw StateError('Unregister terminated the real Linux PTY.');
    }
    print('LINUX OBSERVER UNREGISTER ISOLATION PASS');

    // Detached output must continue being collected and replayed.
    final before = first.processId;
    first.write(utf8.encode(
      'sh -c \'sleep 0.3; echo RVTERM_DETACHED_OUTPUT\'\r',
    ));
    await first.detach();
    await Future<void>.delayed(const Duration(milliseconds: 650));
    final reattached = service.attach(first.sessionId);
    if (reattached.processId != before) {
      throw StateError('Reattach changed Linux shell PID.');
    }
    final lateViewer = _Capture();
    final lateToken = firstTerminal.registerHandler(
      onTerminalStream: (_, e) => lateViewer.receive(e),
    );
    subscriptions.add((firstTerminal, lateToken));
    await lateViewer.waitFor('RVTERM_DETACHED_OUTPUT');
    print('LINUX DETACHED OUTPUT / REPLAY / SAME PID PASS');

    reattached.write(utf8.encode('sleep 20\r'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    reattached.interrupt();
    reattached.write(utf8.encode('echo RVTERM_AFTER_CTRL_C\r'));
    await observerA.waitFor('RVTERM_AFTER_CTRL_C',
        timeout: const Duration(seconds: 6));
    print('LINUX CTRL+C / FOREGROUND SIGNAL PASS');

    reattached.write(utf8.encode('exit 7\r'));
    final code = await reattached.exitCode.timeout(
      const Duration(seconds: 8),
    );
    if (code != 7) {
      throw StateError('Expected Bash exit code 7, got $code.');
    }
    print('LINUX NATURAL EXIT CODE 7 PASS');

    await second.terminate();
    print('TERM-02A REAL LINUX PTY / MULTI-HANDLER SMOKE PASS');
  } finally {
    for (final (terminal, token) in subscriptions) {
      await terminal.unregisterHandler(token);
    }
    await service.close();
    await engine.close();
  }
}

final class _Capture {
  final StringBuffer _received = StringBuffer();

  String get text => _received.toString();

  void receive(TerminalStreamEvent event) {
    if (event.isGap) {
      // A bounded replay history may legitimately report an old gap.
      return;
    }
    _received.write(latin1.decode(event.bytes));
  }

  Future<void> waitFor(
    String value, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final until = DateTime.now().add(timeout);
    while (!text.contains(value)) {
      if (DateTime.now().isAfter(until)) {
        throw StateError('Timeout waiting for $value. Output tail: '
            '${text.length > 700 ? text.substring(text.length - 700) : text}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }
}
