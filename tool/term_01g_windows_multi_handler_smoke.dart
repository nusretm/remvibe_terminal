import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:remvibe_terminal/remvibe_terminal.dart';

/// TERM-01G-B: REAL Windows ConPTY two-PTY / multi-subscriber acceptance.
/// Requires a built DLL and must never be counted as PASS unless executed.
Future<void> main(List<String> args) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('TERM-01G live smoke requires Windows x64.');
  }
  final dll = _dllPath(args);
  if (!File(dll).existsSync()) {
    throw FileSystemException('Native DLL not found; build Debug first.', dll);
  }

  final engine = RemVibeTerminal.windows(libraryPath: dll);
  TerminalSessionService? service;
  try {
    service = TerminalSessionService.register(
      TerminalSessionService.withEngine(
        engine: engine,
        maximumSessions: 2,
        maximumReplayBytes: 64 * 1024,
      ),
    );
    final first = service.newTerminal(
      sessionId: 'term01g-first',
      commandLine: 'powershell.exe -NoLogo -NoProfile',
    );
    final second = service.newTerminal(
      sessionId: 'term01g-second',
      commandLine: 'powershell.exe -NoLogo -NoProfile',
    );
    if (first.processId == second.processId ||
        service.activeSessionCount != 2 ||
        engine.activeSessionCount != 2) {
      throw StateError('Two independent PTYs were not created.');
    }

    final t1 = TerminalSessionService.getTerminal(first.sessionId)!;
    final t2 = TerminalSessionService.getTerminal(second.sessionId)!;
    final a = TerminalHandlerLocal(terminal: t1);
    final b = TerminalHandlerLocal(terminal: t1);
    final c = TerminalHandlerLocal(terminal: t2);
    final probeA = _Probe(t1.terminalId);
    final probeB = _Probe(t1.terminalId);
    final probeC = _Probe(t2.terminalId);

    final regA = a.registerHandler(onTerminalStream: probeA.receive);
    final regB = b.registerHandler(onTerminalStream: probeB.receive);
    final regC = c.registerHandler(onTerminalStream: probeC.receive);

    try {
      first.write(utf8.encode(
        "Write-Output ('RVTERM-' + '01G-FIRST-A')\r",
      ));
      second.write(utf8.encode(
        "Write-Output ('RVTERM-' + '01G-SECOND-A')\r",
      ));
      await Future.wait([
        probeA.waitFor('RVTERM-01G-FIRST-A'),
        probeB.waitFor('RVTERM-01G-FIRST-A'),
        probeC.waitFor('RVTERM-01G-SECOND-A'),
      ]);
      if (service.activeSessionCount != 2 || engine.activeSessionCount != 2) {
        throw StateError('Subscribing unexpectedly duplicated a process.');
      }
      stdout.writeln('TERM-01G REAL TWO PTYS / TWO VIEWERS ONE PTY PASS');

      await a.unregisterHandler(regA);
      first.write(utf8.encode(
        "Write-Output ('RVTERM-' + '01G-FIRST-B')\r",
      ));
      second.write(utf8.encode(
        "Write-Output ('RVTERM-' + '01G-SECOND-B')\r",
      ));
      await Future.wait([
        probeB.waitFor('RVTERM-01G-FIRST-B'),
        probeC.waitFor('RVTERM-01G-SECOND-B'),
      ]);
      if (probeA.contains('RVTERM-01G-FIRST-B')) {
        throw StateError('Removed subscriber received further PTY output.');
      }
      stdout.writeln('TERM-01G REAL UNREGISTER ISOLATION PASS');

      // Start a process command before detaching the controller. The
      // independent watcher must observe completion while detached.
      first.write(utf8.encode(
        "Start-Sleep -Milliseconds 500; "
        "Write-Output ('RVTERM-' + '01G-DETACHED')\r",
      ));
      await first.detach();
      await probeB.waitFor('RVTERM-01G-DETACHED');
      if (!service.contains(first.sessionId) || engine.activeSessionCount != 2) {
        throw StateError('Detaching terminated a PTY unexpectedly.');
      }
      stdout.writeln('TERM-01G REAL DETACHED OUTPUT PASS');

      final reattached = service.attach(first.sessionId);
      if (reattached.processId != first.processId) {
        throw StateError('Reattach created a different PTY.');
      }
      await reattached.detach();
      stdout.writeln('TERM-01G REAL REATTACH SAME PID PASS');
    } finally {
      await a.unregisterHandler(regA);
      await b.unregisterHandler(regB);
      await c.unregisterHandler(regC);
    }
  } finally {
    try {
      await service?.close();
    } finally {
      await engine.close();
    }
  }
  stdout.writeln('TERM-01G WINDOWS LIVE MULTI-HANDLER SMOKE PASS');
}

String _dllPath(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--dll' && i + 1 < args.length) return args[i + 1];
    if (args[i].startsWith('--dll=')) return args[i].substring(6);
  }
  throw ArgumentError('Pass --dll <absolute path to Debug native DLL>.');
}

final class _Probe {
  _Probe(this.expectedTerminalId);
  final String expectedTerminalId;
  String _text = '';
  int _lastSequence = 0;
  String? _failure;

  void receive(TerminalEventSource source, TerminalStreamEvent event) {
    if (source.terminalId != expectedTerminalId ||
        event.terminalId != expectedTerminalId) {
      _failure = 'Wrong terminal identity in stream event.';
      return;
    }
    if (event.isGap) {
      _failure = 'Missing PTY frames: '
          '${event.gapFromSequence}..${event.gapToSequence}';
      return;
    }
    if (event.sequence <= _lastSequence) {
      _failure = 'Output sequence not increasing: ${event.sequence}';
      return;
    }
    _lastSequence = event.sequence;
    _text += utf8.decode(event.bytes, allowMalformed: true);
    if (_text.length > 64000) {
      _text = _text.substring(_text.length - 64000);
    }
  }

  bool contains(String marker) => _text.contains(marker);

  Future<void> waitFor(String marker) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      if (_failure != null) {
        throw StateError('Real terminal stream failure: $_failure');
      }
      if (contains(marker)) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    throw TimeoutException('ConPTY marker $marker not found. '
        'Last 1200 chars: '
        '${_text.length > 1200 ? _text.substring(_text.length - 1200) : _text}');
  }
}
