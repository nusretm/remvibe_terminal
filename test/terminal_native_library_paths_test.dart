import 'dart:io';

import 'package:remvibe_terminal/src/windows/terminal_native_library_paths.dart';
import 'package:test/test.dart';

void main() {
  test('no manual candidates leaves bundled Native Asset as default', () {
    expect(TerminalNativeLibraryPaths.resolve(), isEmpty);
  });

  test('singular path precedes plural paths, followed by search directories',
      () {
    final root = Directory.systemTemp.createTempSync('rvterm-paths-');
    addTearDown(() => root.deleteSync(recursive: true));
    final first = File(
      '${root.path}${Platform.pathSeparator}first.dll',
    ).absolute.path;
    final second = File(
      '${root.path}${Platform.pathSeparator}second.dll',
    ).absolute.path;
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}lib',
    ).absolute.path;

    final result = TerminalNativeLibraryPaths.resolve(
      libraryPath: first,
      libraryPaths: [second],
      searchDirectories: [directory],
    );
    expect(result, [
      first,
      second,
      '$directory${Platform.pathSeparator}remvibe_terminal_windows.dll',
    ]);
  });

  test('deduplicates paths and preserves first successful order', () {
    final temp = Directory.systemTemp.createTempSync('rvterm-path-dedup-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final primary = File(
      '${temp.path}${Platform.pathSeparator}candidate.dll',
    ).absolute.path;
    final other = File(
      '${temp.path}${Platform.pathSeparator}other.dll',
    ).absolute.path;

    expect(
      TerminalNativeLibraryPaths.resolve(
        libraryPath: primary,
        libraryPaths: [primary, other, primary],
      ),
      [primary, other],
    );
  });

  test('returns immutable candidates; ignores no configured candidates', () {
    final paths = TerminalNativeLibraryPaths.resolve(
      libraryPaths: ['arbitrary-library.dll'],
    );
    expect(paths, hasLength(1));
    expect(() => paths.add('another.dll'), throwsUnsupportedError);
  });

  test('rejects empty library paths and directories', () {
    expect(
      () => TerminalNativeLibraryPaths.resolve(libraryPath: ' '),
      throwsArgumentError,
    );
    expect(
      () => TerminalNativeLibraryPaths.resolve(libraryPaths: ['']),
      throwsArgumentError,
    );
    expect(
      () => TerminalNativeLibraryPaths.resolve(searchDirectories: [' ']),
      throwsArgumentError,
    );
  });
}
