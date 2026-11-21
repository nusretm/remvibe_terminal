import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:remvibe_terminal/remvibe_terminal.dart';

/// Real Windows/PowerShell integration. Must not be counted as PASS on Linux,
/// when no native DLL exists, or when this file is only analyzed.
Future<void> main(List<String> args) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('The real smoke requires Windows x64.');
  }
  final dllPath = _parseDllPath(args);
  if (!File(dllPath).existsSync()) {
    throw FileSystemException('Build the native ConPTY DLL first.', dllPath);
  }

  final engine = RemVibeTerminal.windows(libraryPath: dllPath);
  RemVibeTerminalSession? first;
  RemVibeTerminalSession? second;
  RemVibeTerminalSession? cancelled;
  _OutputProbe? firstProbe;
  _OutputProbe? secondProbe;
  _OutputProbe? cancelProbe;
  try {
    first = engine.create(
      commandLine: 'powershell.exe -NoLogo -NoProfile',
      columns: 100,
      rows: 30,
    );
    firstProbe = _OutputProbe(first);
    stdout.writeln('TERM-01A START first PID=${first.processId}');

    first.write(utf8.encode(
      "Get-Location | Out-String | Write-Output; "
      "Write-Output ('RVTERM-' + 'LOC:' + (Get-Location).Path + ':END')\r",
    ));
    await firstProbe.waitFor(RegExp(r'RVTERM-LOC:[^\r\n]+:END'));
    stdout.writeln('TERM-01A Get-Location PASS');

    first.write(utf8.encode(
      'Get-Process -Id \$PID | Out-String | Write-Output; '
      "Write-Output ('RVTERM-' + 'PROC:' + "
      '(Get-Process -Id \$PID).ProcessName + \':END\')\r',
    ));
    await firstProbe.waitFor(RegExp(r'RVTERM-PROC:[^\r\n]+:END'));
    stdout.writeln('TERM-01A Get-Process PASS');

    first.resize(columns: 120, rows: 40);
    first.write(utf8.encode("Write-Output ('RVTERM-' + 'RESIZED')\r"));
    await firstProbe.waitFor(RegExp(r'RVTERM-RESIZED'));
    stdout.writeln('TERM-01A resize PASS');

    second = engine.create(
      commandLine: 'powershell.exe -NoLogo -NoProfile',
      columns: 80,
      rows: 24,
    );
    secondProbe = _OutputProbe(second);
    if (first.processId == second.processId || engine.activeSessionCount != 2) {
      throw StateError('Expected two independent active processes.');
    }
    first.write(utf8.encode("Write-Output ('RVTERM-' + 'FIRST-ALIVE')\r"));
    second.write(utf8.encode("Write-Output ('RVTERM-' + 'SECOND-ALIVE')\r"));
    await firstProbe.waitFor(RegExp(r'RVTERM-FIRST-ALIVE'));
    await secondProbe.waitFor(RegExp(r'RVTERM-SECOND-ALIVE'));
    stdout.writeln('TERM-01A two independent terminals PASS');

    final firstPid = first.processId;
    await first.close();
    if (await first.exitCode != null) {
      throw StateError('Explicitly closed terminal should report null exit.');
    }
    await _requireProcessGone(firstPid);
    second.write(utf8.encode("Write-Output ('RVTERM-' + 'SURVIVES')\r"));
    await secondProbe.waitFor(RegExp(r'RVTERM-SURVIVES'));
    stdout.writeln('TERM-01A close-first/second-survives PASS');

    final secondPid = second.processId;
    second.write(utf8.encode('exit\r'));
    final code = await second.exitCode.timeout(const Duration(seconds: 25));
    if (code != 0) throw StateError('Expected PowerShell exit 0, got $code');
    await _requireProcessGone(secondPid);
    stdout.writeln('TERM-01A natural exit code=0 PASS');

    cancelled = engine.create(
      commandLine: 'powershell.exe -NoLogo -NoProfile',
      columns: 80,
      rows: 24,
    );
    cancelProbe = _OutputProbe(cancelled);
    cancelled.write(utf8.encode("Write-Output ('RVTERM-' + 'CANCEL-READY')\r"));
    await cancelProbe.waitFor(RegExp(r'RVTERM-CANCEL-READY'));
    final cancelledPid = cancelled.processId;
    await cancelled.cancel();
    if (await cancelled.exitCode != null) {
      throw StateError('Cancelled terminal must return null exit result.');
    }
    await _requireProcessGone(cancelledPid);
    if (engine.activeSessionCount != 0 ||
        first.failure != null ||
        second.failure != null ||
        cancelled.failure != null) {
      throw StateError('Terminal lifecycle error or leaked engine session.');
    }
    stdout.writeln('TERM-01A cancel and cleanup PASS');
    stdout.writeln('TERM-01A WINDOWS REAL CONPTY ACCEPTANCE PASS');
  } finally {
    await firstProbe?.close();
    await secondProbe?.close();
    await cancelProbe?.close();
    await engine.close();
  }
}

String _parseDllPath(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--dll' && i + 1 < args.length) return args[i + 1];
    if (args[i].startsWith('--dll=')) return args[i].substring(6);
  }
  final fromEnv = Platform.environment['REMVIBE_TERMINAL_FFI_LIB'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  throw ArgumentError('Pass --dll <absolute DLL path> or set '
      'REMVIBE_TERMINAL_FFI_LIB.');
}

final class _OutputProbe {
  _OutputProbe(RemVibeTerminalSession session) {
    _subscription =
        session.output.cast<List<int>>().transform(utf8.decoder).listen(
      (text) {
        _tail += text;
        if (_tail.length > 64000) {
          _tail = _tail.substring(_tail.length - 64000);
        }
      },
      onError: (Object error, StackTrace stackTrace) => _failure = error,
    );
  }

  late final StreamSubscription<String> _subscription;
  String _tail = '';
  Object? _failure;

  Future<void> waitFor(RegExp marker) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      if (_failure != null) throw StateError('ConPTY output error: $_failure');
      if (marker.hasMatch(_tail)) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    throw TimeoutException('Marker $marker not found in real PTY output. '
        'Last 1600 chars: ${_tail.length > 1600 ? _tail.substring(_tail.length - 1600) : _tail}');
  }

  Future<void> close() => _subscription.cancel();
}

Future<void> _requireProcessGone(int pid) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '\$p = Get-Process -Id $pid -ErrorAction SilentlyContinue; '
            "if (\$null -eq \$p) { 'STOPPED' } else { 'RUNNING' }",
      ],
    ).timeout(const Duration(seconds: 12));
    if (result.exitCode != 0) {
      throw StateError('Process check failed: ${result.stderr}');
    }
    if (result.stdout.toString().trim() == 'STOPPED') return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError('ConPTY child PID $pid remains running after cleanup.');
}
