import 'dart:io';

import 'package:remvibe_terminal/remvibe_terminal.dart';
import 'package:test/test.dart';

void main() {
  test('Windows constructor rejects unsupported OS', () {
    if (Platform.isWindows) return;
    expect(
      () => RemVibeTerminal.windows(libraryPath: 'nonexistent.dll'),
      throwsUnsupportedError,
    );
  });

  test('a missing DLL does not silently create an engine on Windows', () {
    if (!Platform.isWindows) return;
    expect(
      () => RemVibeTerminal.windows(
        libraryPath: '__remvibe_terminal_missing_test_library__.dll',
      ),
      throwsA(
        isA<TerminalNativeLibraryLoadException>()
            .having(
              (error) => error.attemptedPaths,
              'attemptedPaths',
              hasLength(1),
            )
            .having(
              (error) => error.attemptedPaths.single,
              'missing DLL path',
              endsWith('__remvibe_terminal_missing_test_library__.dll'),
            )
            .having(
              (error) => error.failures.join(' '),
              'failure diagnostics',
              contains('file not found'),
            ),
      ),
    );
  });
}
