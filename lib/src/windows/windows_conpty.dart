import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../backend/terminal_backend.dart';

/// A nonzero result from the native Win32/ConPTY C interface.
final class TerminalNativeException implements Exception {
  const TerminalNativeException(this.operation, this.windowsError);

  final String operation;
  final int windowsError;

  @override
  String toString() =>
      'TerminalNativeException($operation, windowsError=$windowsError)';
}

final class NativeReadResult implements TerminalReadResult {
  const NativeReadResult(this.bytes, this.eof, this.overflow);
  final Uint8List bytes;
  final bool eof;
  final bool overflow;
}

final class NativeExitResult implements TerminalExitResult {
  const NativeExitResult(this.exited, this.exitCode);
  final bool exited;
  final int? exitCode;
}

/// Low-level Windows ABI access. Kept internal to the Dart public package.
final class WindowsConPtyLibrary implements TerminalBackend {
  /// No path: resolve the bundled Dart code asset. An explicit path keeps
  /// compatibility with the existing standalone native smoke and Debug tools.
  WindowsConPtyLibrary([String? path])
      : _bindings = path == null
            ? _Bindings.codeAsset()
            : _Bindings(_load(path));

  static DynamicLibrary _load(String path) {
    if (!Platform.isWindows) {
      throw UnsupportedError('ConPTY is available only on Windows.');
    }
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'libraryPath', 'A DLL path is required.');
    }
    return DynamicLibrary.open(path);
  }

  final _Bindings _bindings;

  NativeConPtySession create({
    required String commandLine,
    required int columns,
    required int rows,
    required int maximumBufferBytes,
  }) {
    final command = commandLine.toNativeUtf16();
    final outSession = calloc<Pointer<Void>>();
    try {
      _requireSuccess(
        'create',
        _bindings.create(
          command,
          columns,
          rows,
          maximumBufferBytes,
          outSession,
        ),
      );
      final handle = outSession.value;
      if (handle == nullptr) {
        throw StateError('Native ConPTY returned a null session handle.');
      }
      return NativeConPtySession._(_bindings, handle);
    } finally {
      calloc.free(command);
      calloc.free(outSession);
    }
  }
}

final class NativeConPtySession implements TerminalHandle {
  NativeConPtySession._(this._bindings, this._handle);

  final _Bindings _bindings;
  Pointer<Void> _handle;
  bool _closed = false;

  int get processId {
    _requireOpen();
    final pid = calloc<Uint32>();
    try {
      _requireSuccess('processId', _bindings.processId(_handle, pid));
      return pid.value;
    } finally {
      calloc.free(pid);
    }
  }

  void write(List<int> bytes) {
    _requireOpen();
    if (bytes.isEmpty) return;
    final buffer = calloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      _requireSuccess('write', _bindings.write(_handle, buffer, bytes.length));
    } finally {
      calloc.free(buffer);
    }
  }

  void resize({required int columns, required int rows}) {
    _requireOpen();
    _requireSuccess('resize', _bindings.resize(_handle, columns, rows));
  }

  void ctrlC() {
    _requireOpen();
    _requireSuccess('interrupt', _bindings.ctrlC(_handle));
  }

  NativeReadResult read({int maximumBytes = 16 * 1024}) {
    _requireOpen();
    final buffer = calloc<Uint8>(maximumBytes);
    final length = calloc<Size>();
    final eof = calloc<Int32>();
    final overflow = calloc<Int32>();
    try {
      _requireSuccess(
        'read',
        _bindings.read(
          _handle,
          buffer,
          maximumBytes,
          length,
          eof,
          overflow,
        ),
      );
      return NativeReadResult(
        Uint8List.fromList(buffer.asTypedList(length.value)),
        eof.value != 0,
        overflow.value != 0,
      );
    } finally {
      calloc.free(buffer);
      calloc.free(length);
      calloc.free(eof);
      calloc.free(overflow);
    }
  }

  NativeExitResult wait() {
    _requireOpen();
    final exited = calloc<Int32>();
    final exitCode = calloc<Int32>();
    try {
      _requireSuccess(
        'wait',
        _bindings.wait(_handle, 0, exited, exitCode),
      );
      return NativeExitResult(
        exited.value != 0,
        exited.value != 0 ? exitCode.value : null,
      );
    } finally {
      calloc.free(exited);
      calloc.free(exitCode);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final handle = _handle;
    _handle = nullptr;
    _requireSuccess('close', _bindings.close(handle));
  }

  void _requireOpen() {
    if (_closed) throw StateError('ConPTY session is closed.');
  }
}

void _requireSuccess(String operation, int code) {
  if (code != 0) throw TerminalNativeException(operation, code);
}

final class _Bindings {
  // Functions with @Native use the code-asset routing installed by Dart's
  // build hooks. No executable-relative DLL path assumptions are needed.
  _Bindings.codeAsset()
      : create = _assetCreate,
        write = _assetWrite,
        resize = _assetResize,
        read = _assetRead,
        ctrlC = _assetCtrlC,
        wait = _assetWait,
        processId = _assetPid,
        close = _assetClose;

  _Bindings(DynamicLibrary library)
      : create = library.lookupFunction<_CreateNative, _CreateDart>(
          'rvterm_create',
        ),
        write = library.lookupFunction<_WriteNative, _WriteDart>(
          'rvterm_write',
        ),
        resize = library.lookupFunction<_ResizeNative, _ResizeDart>(
          'rvterm_resize',
        ),
        read = library.lookupFunction<_ReadNative, _ReadDart>(
          'rvterm_read',
        ),
        ctrlC = library.lookupFunction<_CtrlCNative, _CtrlCDart>(
          'rvterm_ctrl_c',
        ),
        wait = library.lookupFunction<_WaitNative, _WaitDart>(
          'rvterm_wait',
        ),
        processId = library.lookupFunction<_PidNative, _PidDart>(
          'rvterm_process_id',
        ),
        close = library.lookupFunction<_CloseNative, _CloseDart>(
          'rvterm_close',
        );

  final _CreateDart create;
  final _WriteDart write;
  final _ResizeDart resize;
  final _ReadDart read;
  final _CtrlCDart ctrlC;
  final _WaitDart wait;
  final _PidDart processId;
  final _CloseDart close;
}

typedef _CreateNative = Int32 Function(
  Pointer<Utf16>,
  Uint16,
  Uint16,
  Size,
  Pointer<Pointer<Void>>,
);
typedef _CreateDart = int Function(
  Pointer<Utf16>,
  int,
  int,
  int,
  Pointer<Pointer<Void>>,
);
typedef _WriteNative = Int32 Function(Pointer<Void>, Pointer<Uint8>, Size);
typedef _WriteDart = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _ResizeNative = Int32 Function(Pointer<Void>, Uint16, Uint16);
typedef _ResizeDart = int Function(Pointer<Void>, int, int);
typedef _ReadNative = Int32 Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Size,
  Pointer<Size>,
  Pointer<Int32>,
  Pointer<Int32>,
);
typedef _ReadDart = int Function(
  Pointer<Void>,
  Pointer<Uint8>,
  int,
  Pointer<Size>,
  Pointer<Int32>,
  Pointer<Int32>,
);
typedef _CtrlCNative = Int32 Function(Pointer<Void>);
typedef _CtrlCDart = int Function(Pointer<Void>);
typedef _WaitNative = Int32 Function(
  Pointer<Void>,
  Uint32,
  Pointer<Int32>,
  Pointer<Int32>,
);
typedef _WaitDart = int Function(
  Pointer<Void>,
  int,
  Pointer<Int32>,
  Pointer<Int32>,
);
typedef _PidNative = Int32 Function(Pointer<Void>, Pointer<Uint32>);
typedef _PidDart = int Function(Pointer<Void>, Pointer<Uint32>);
typedef _CloseNative = Int32 Function(Pointer<Void>);
typedef _CloseDart = int Function(Pointer<Void>);

const _nativeAssetId = 'package:remvibe_terminal/src/windows/windows_conpty.dart';

@Native<_CreateNative>(symbol: 'rvterm_create', assetId: _nativeAssetId)
external int _assetCreate(
  Pointer<Utf16> commandLine,
  int columns,
  int rows,
  int maximumBufferBytes,
  Pointer<Pointer<Void>> outSession,
);

@Native<_WriteNative>(symbol: 'rvterm_write', assetId: _nativeAssetId)
external int _assetWrite(Pointer<Void> session, Pointer<Uint8> bytes, int length);

@Native<_ResizeNative>(symbol: 'rvterm_resize', assetId: _nativeAssetId)
external int _assetResize(Pointer<Void> session, int columns, int rows);

@Native<_ReadNative>(symbol: 'rvterm_read', assetId: _nativeAssetId)
external int _assetRead(
  Pointer<Void> session,
  Pointer<Uint8> bytes,
  int capacity,
  Pointer<Size> outLength,
  Pointer<Int32> outEof,
  Pointer<Int32> outOverflow,
);

@Native<_CtrlCNative>(symbol: 'rvterm_ctrl_c', assetId: _nativeAssetId)
external int _assetCtrlC(Pointer<Void> session);

@Native<_WaitNative>(symbol: 'rvterm_wait', assetId: _nativeAssetId)
external int _assetWait(
  Pointer<Void> session,
  int timeoutMillis,
  Pointer<Int32> outExited,
  Pointer<Int32> outExitCode,
);

@Native<_PidNative>(symbol: 'rvterm_process_id', assetId: _nativeAssetId)
external int _assetPid(Pointer<Void> session, Pointer<Uint32> outProcessId);

@Native<_CloseNative>(symbol: 'rvterm_close', assetId: _nativeAssetId)
external int _assetClose(Pointer<Void> session);
