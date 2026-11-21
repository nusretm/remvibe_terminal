import 'dart:typed_data';

/// The OS-specific implementation boundary. This package exposes a single
/// Dart terminal API; each platform supplies its own PTY backend.
abstract interface class TerminalBackend {
  TerminalHandle create({
    required String commandLine,
    required int columns,
    required int rows,
    required int maximumBufferBytes,
  });
}

/// Native terminal handle; the owning engine serializes calls on its isolate.
abstract interface class TerminalHandle {
  int get processId;
  void write(List<int> bytes);
  void resize({required int columns, required int rows});
  void ctrlC();
  TerminalReadResult read({int maximumBytes = 16 * 1024});
  TerminalExitResult wait();
  void close();
}

abstract interface class TerminalReadResult {
  Uint8List get bytes;
  bool get eof;
  bool get overflow;
}

abstract interface class TerminalExitResult {
  bool get exited;
  int? get exitCode;
}
