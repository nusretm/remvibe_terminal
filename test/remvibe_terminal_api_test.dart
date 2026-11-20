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
      throwsA(isA<ArgumentError>().having(
        (error) => error.message,
        'message',
        isNotEmpty,
      )),
    );
  });
}
