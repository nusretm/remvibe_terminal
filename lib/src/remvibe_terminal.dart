import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'backend/terminal_backend.dart';
import 'linux/linux_pty.dart';
import 'windows/windows_conpty.dart';

export 'windows/windows_conpty.dart'
    show TerminalNativeException, TerminalNativeLibraryLoadException;

/// Local terminal engine. No Fleet, Flutter or RemVibe Networking dependencies.
final class RemVibeTerminal {
  RemVibeTerminal._(this._native, this._pollInterval);

  /// Select the available native platform backend.
  /// Other platform implementations will be added without changing sessions.
  factory RemVibeTerminal.currentPlatform({
    String? libraryPath,
    List<String> libraryPaths = const [],
    List<String> searchDirectories = const [],
    Duration pollInterval = const Duration(milliseconds: 15),
  }) {
    if (Platform.isWindows) {
      return RemVibeTerminal.windows(
        libraryPath: libraryPath,
        libraryPaths: libraryPaths,
        searchDirectories: searchDirectories,
        pollInterval: pollInterval,
      );
    }
    if (Platform.isLinux) {
      if (libraryPaths.isNotEmpty || searchDirectories.isNotEmpty) {
        throw ArgumentError('Linux currently accepts only libraryPath as an explicit override.');
      }
      return RemVibeTerminal.linux(
        libraryPath: libraryPath,
        pollInterval: pollInterval,
      );
    }
    throw UnsupportedError('A native PTY backend is not yet available on '
        '${Platform.operatingSystem}.');
  }

  /// Windows x64 ConPTY backend. With no [libraryPath], resolves the
  /// DLL as a Dart Code Asset from hook/build.dart. The CLI bundle places it
  /// under lib/, without consumers copying it beside the executable.
  /// Manual DLL loading can try more than one candidate, in this order:
  /// [libraryPath], each [libraryPaths] entry, then
  /// remvibe_terminal_windows.dll inside each [searchDirectories] entry.
  ///
  /// If no candidate is configured, the bundled Native Asset is used.
  /// Explicit candidates never silently fall back to a different DLL.
  factory RemVibeTerminal.windows({
    String? libraryPath,
    List<String> libraryPaths = const [],
    List<String> searchDirectories = const [],
    Duration pollInterval = const Duration(milliseconds: 15),
  }) {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows ConPTY is only available on Windows.');
    }
    if (pollInterval < const Duration(milliseconds: 1)) {
      throw ArgumentError.value(pollInterval, 'pollInterval');
    }
    return RemVibeTerminal._(
      WindowsConPtyLibrary(
        libraryPath: libraryPath,
        libraryPaths: libraryPaths,
        searchDirectories: searchDirectories,
      ),
      pollInterval,
    );
  }

  /// Linux PTY backend. Uses the bundled Linux Native Asset by default.
  /// A manual .so path is an explicit override, never an implicit fallback.
  factory RemVibeTerminal.linux({
    String? libraryPath,
    Duration pollInterval = const Duration(milliseconds: 15),
  }) {
    if (!Platform.isLinux) {
      throw UnsupportedError('Linux PTY is only available on Linux.');
    }
    if (pollInterval < const Duration(milliseconds: 1)) {
      throw ArgumentError.value(pollInterval, 'pollInterval');
    }
    return RemVibeTerminal._(
      LinuxPtyLibrary(libraryPath: libraryPath),
      pollInterval,
    );
  }

  final TerminalBackend _native;
  final Duration _pollInterval;
  final Set<RemVibeTerminalSession> _sessions = {};
  bool _closed = false;

  bool get isClosed => _closed;
  int get activeSessionCount => _sessions.length;

  /// Starts a real interactive terminal. Subscribe to [RemVibeTerminalSession.output]
  /// promptly to receive startup output.
  RemVibeTerminalSession create({
    required String commandLine,
    int columns = 100,
    int rows = 30,
    int maximumBufferBytes = 256 * 1024,
  }) {
    if (_closed) throw StateError('Terminal engine is closed.');
    if (commandLine.trim().isEmpty) {
      throw ArgumentError.value(commandLine, 'commandLine');
    }
    _validateSize(columns, rows);
    if (maximumBufferBytes <= 0) {
      throw ArgumentError.value(maximumBufferBytes, 'maximumBufferBytes');
    }
    final native = _native.create(
      commandLine: commandLine,
      columns: columns,
      rows: rows,
      maximumBufferBytes: maximumBufferBytes,
    );
    late final RemVibeTerminalSession session;
    try {
      session = RemVibeTerminalSession._(
        native,
        _pollInterval,
        () => _sessions.remove(session),
      );
      _sessions.add(session);
      session._start();
      return session;
    } catch (_) {
      native.close();
      rethrow;
    }
  }

  /// Closes all sessions owned by this engine. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final session in _sessions.toList(growable: false)) {
      await session.close();
    }
  }
}

/// One OS process + PTY. Native calls are serialized on this Dart isolate.
final class RemVibeTerminalSession {
  RemVibeTerminalSession._(
    TerminalHandle native,
    this._pollInterval,
    this._onClosed,
  ) : _native = native,
      processId = native.processId;

  final TerminalHandle _native;
  final Duration _pollInterval;
  final void Function() _onClosed;
  final int processId;
  final StreamController<Uint8List> _output =
      StreamController<Uint8List>.broadcast();
  final Completer<int?> _exit = Completer<int?>();
  Timer? _timer;
  bool _closed = false;
  DateTime? _exitObservedAt;
  int? _observedExitCode;
  Object? _failure;

  /// Numeric child PID, retained even after close (useful for diagnostics).
  /// Does not imply permission to control processes owned by another engine.
  bool get isClosed => _closed;

  /// Raw PTY bytes (including ANSI/VT control sequences). Broadcast stream:
  /// subscribe immediately; events emitted before subscription are not retained.
  Stream<Uint8List> get output => _output.stream;

  /// Natural exit code, or null if explicitly closed/cancelled or native I/O
  /// failed. Completes after the final output drain/cleanup.
  Future<int?> get exitCode => _exit.future;

  /// Diagnostic error observed by the background output polling loop.
  Object? get failure => _failure;

  void _start() {
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  /// Write raw input bytes. Send a carriage return (`\r`) for Enter.
  void write(List<int> bytes) {
    _requireOpen();
    _native.write(bytes);
  }

  /// Resize the live terminal screen. Dimensions fit Windows COORD and PTY winsize.
  void resize({required int columns, required int rows}) {
    _requireOpen();
    _validateSize(columns, rows);
    _native.resize(columns: columns, rows: rows);
  }

  /// Send ETX/Ctrl+C to the terminal. This does NOT close the session.
  void interrupt() {
    _requireOpen();
    _native.ctrlC();
  }

  /// Force terminate the child job and release the native session. The exit
  /// result is null if cancelled before a natural exit was observed.
  Future<void> cancel() => close();

  /// Terminate (if still running) and dispose native resources. Idempotent.
  Future<void> close() async {
    _shutdown();
  }

  void _poll() {
    if (_closed) return;
    try {
      bool eof = false;
      bool bufferEmpty = false;
      // Bounded work per tick. Native reader thread remains the sole pipe reader.
      for (var i = 0; i < 16; i++) {
        final data = _native.read();
        if (data.overflow) {
          throw StateError('Native ConPTY output buffer overflow.');
        }
        if (data.bytes.isNotEmpty) {
          _output.add(data.bytes);
        }
        eof = data.eof;
        bufferEmpty = data.bytes.length < 16 * 1024;
        if (bufferEmpty) break;
      }
      final status = _native.wait();
      if (!status.exited) return;
      _exitObservedAt ??= DateTime.now();
      _observedExitCode ??= status.exitCode;
      // Wait for native EOF or for a short, quiet post-exit drain interval.
      // The final native read happens before the output stream is closed.
      if (eof ||
          (bufferEmpty &&
              DateTime.now().difference(_exitObservedAt!) >=
                  const Duration(milliseconds: 150))) {
        _shutdown(naturalExitCode: _observedExitCode);
      }
    } catch (error, stackTrace) {
      if (_closed) return;
      _failure = error;
      _output.addError(error, stackTrace);
      _shutdown();
    }
  }

  void _shutdown({int? naturalExitCode}) {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    try {
      _native.close();
    } catch (error, stackTrace) {
      _failure ??= error;
      _output.addError(error, stackTrace);
    } finally {
      _output.close();
      if (!_exit.isCompleted) _exit.complete(naturalExitCode);
      _onClosed();
    }
  }

  void _requireOpen() {
    if (_closed) throw StateError('Terminal session is closed.');
  }
}

void _validateSize(int columns, int rows) {
  if (columns < 1 || columns > 32767 || rows < 1 || rows > 32767) {
    throw RangeError('Terminal columns/rows must be within 1..32767.');
  }
}
