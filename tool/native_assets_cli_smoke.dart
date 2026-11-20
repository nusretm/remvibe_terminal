import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:remvibe_terminal/remvibe_terminal.dart';

// This file is copied into an isolated CLI consumer and built with
// 'dart build cli'. It deliberately uses NO explicit DLL path.
Future<void> main(List<String> args) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Native asset smoke needs Windows x64.');
  }

  final binary = File(Platform.resolvedExecutable);
  final bundleLib = Directory(
    '${binary.parent.parent.path}${Platform.pathSeparator}lib',
  );
  final realDll = File(
    '${bundleLib.path}${Platform.pathSeparator}'
    'remvibe_terminal_windows.dll',
  );

  // These modes exercise explicitly configured native candidate fallbacks.
  // Default mode still proves automatic Native Assets, with NO DLL path.
  final bool manualCandidates = args.contains('--library-paths');
  final bool searchDirectories = args.contains('--search-directories');
  if (manualCandidates && searchDirectories) {
    throw ArgumentError('Choose one manual library search mode.');
  }
  final temporary = manualCandidates
      ? Directory.systemTemp.createTempSync('rvterm-invalid-library-')
      : null;
  if (temporary != null) {
    File('${temporary.path}${Platform.pathSeparator}invalid.dll')
        .writeAsBytesSync([0, 1, 2, 3]);
  }
  final engine = manualCandidates
      ? RemVibeTerminal.currentPlatform(
          libraryPath:
              '${bundleLib.path}${Platform.pathSeparator}missing.dll',
          libraryPaths: [
            '${temporary!.path}${Platform.pathSeparator}invalid.dll',
            realDll.path,
          ],
        )
      : searchDirectories
          ? RemVibeTerminal.currentPlatform(
              searchDirectories: [
                '${bundleLib.path}${Platform.pathSeparator}missing',
                bundleLib.path,
              ],
            )
          : RemVibeTerminal.currentPlatform();
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
    stdout.writeln(
      manualCandidates
          ? 'REMVIBE_TERMINAL_MULTI_PATH_FALLBACK_PASS'
          : searchDirectories
              ? 'REMVIBE_TERMINAL_SEARCH_DIRECTORIES_PASS'
              : 'REMVIBE_TERMINAL_CLI_NATIVE_ASSET_PASS',
    );
  } finally {
    await subscription.cancel();
    await session.close();
    await engine.close();
    temporary?.deleteSync(recursive: true);
  }
}
