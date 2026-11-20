import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:remvibe_terminal/remvibe_terminal.dart';

// This file is copied into an isolated CLI consumer and built with
// 'dart build cli'. It deliberately uses NO explicit DLL path.
Future<void> main() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Native asset smoke needs Windows x64.');
  }

  final engine = RemVibeTerminal.currentPlatform();
  final session = engine.create(
    commandLine: 'powershell.exe -NoLogo -NoProfile',
    columns: 90,
    rows: 28,
  );
  final marker = Completer<void>();
  final text = StringBuffer();
  final subscription = session.output
      .cast<List<int>>()
      .transform(utf8.decoder)
      .listen(
        (chunk) {
          text.write(chunk);
          if (!marker.isCompleted &&
              text.toString().contains('RVTERM-BUNDLED-ASSET-PASS')) {
            marker.complete();
          }
        },
        onError: (Object error, StackTrace trace) {
          if (!marker.isCompleted) marker.completeError(error, trace);
        },
      );

  try {
    session.write(utf8.encode(
      "Write-Output 'RVTERM-BUNDLED-ASSET-PASS'; exit\r",
    ));
    await marker.future.timeout(const Duration(seconds: 25));
    final exit = await session.exitCode.timeout(const Duration(seconds: 25));
    if (exit != 0) {
      throw StateError('PowerShell exited with unexpected code $exit');
    }
    stdout.writeln('REMVIBE_TERMINAL_CLI_NATIVE_ASSET_PASS');
  } finally {
    await subscription.cancel();
    await session.close();
    await engine.close();
  }
}
