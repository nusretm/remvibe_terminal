import 'dart:io';

/// Builds ordered, distinct native DLL candidates without loading them.
///
/// All explicitly supplied paths are treated as Windows DLL file paths.
/// Directories are expanded with the expected Windows terminal DLL filename.
/// The production default with no candidates is the Dart Native Asset.
abstract final class TerminalNativeLibraryPaths {
  static const fileName = 'remvibe_terminal_windows.dll';

  static List<String> resolve({
    String? libraryPath,
    List<String> libraryPaths = const [],
    List<String> searchDirectories = const [],
  }) {
    final candidates = <String>[];
    final seen = <String>{};

    void addPath(String value) {
      if (value.trim().isEmpty) {
        throw ArgumentError.value(value, 'nativeLibraryPath',
            'Native DLL paths and search directories cannot be empty.');
      }
      final absolute = File(value).absolute.path;
      // Windows file paths are case-insensitive. Preserve the original
      // path spelling while avoiding duplicate candidate attempts.
      final key = Platform.isWindows ? absolute.toLowerCase() : absolute;
      if (seen.add(key)) candidates.add(absolute);
    }

    if (libraryPath != null) addPath(libraryPath);
    for (final path in libraryPaths) {
      addPath(path);
    }
    for (final directory in searchDirectories) {
      if (directory.trim().isEmpty) {
        throw ArgumentError.value(directory, 'searchDirectories',
            'Native search directories cannot be empty.');
      }
      addPath(
        '${Directory(directory).absolute.path}'
        '${Platform.pathSeparator}$fileName',
      );
    }
    return List.unmodifiable(candidates);
  }
}
