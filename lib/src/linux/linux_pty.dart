import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../backend/terminal_backend.dart';

/// A nonzero Linux errno from the local native PTY implementation.
final class TerminalLinuxNativeException implements Exception {
  const TerminalLinuxNativeException(this.operation, this.errno);

  final String operation;
  final int errno;

  @override
  String toString() =>
      'TerminalLinuxNativeException($operation, errno=$errno)';
}

/// Only an explicitly selected manual .so failed to load or bind.
final class TerminalLinuxLibraryLoadException implements Exception {
  const TerminalLinuxLibraryLoadException(this.path, this.cause);

  final String path;
  final Object cause;

  @override
  String toString() =>
      'TerminalLinuxLibraryLoadException($path): $cause';
}

final class LinuxPtyReadResult implements TerminalReadResult {
  const LinuxPtyReadResult(this.bytes, this.eof, this.overflow);

  @override
  final Uint8List bytes;
  @override
  final bool eof;
  @override
  final bool overflow;
}

final class LinuxPtyExitResult implements TerminalExitResult {
  const LinuxPtyExitResult(this.exited, this.exitCode);

  @override
  final bool exited;
  @override
  final int? exitCode;
}

/// Linux native PTYs via forkpty, kernel PTY master and a real child process.
///
/// No Flutter, networking, Update Center, Fleet or application responsibilities.
final class LinuxPtyLibrary implements TerminalBackend {
  LinuxPtyLibrary({String? libraryPath}) : _bindings = _load(libraryPath);

  static _LinuxBindings _load(String? libraryPath) {
    if (!Platform.isLinux) {
      throw UnsupportedError('Linux PTY is available only on Linux.');
    }
    if (libraryPath == null) return _LinuxBindings.codeAsset();
    if (libraryPath.trim().isEmpty) {
      throw ArgumentError.value(libraryPath, 'libraryPath');
    }
    try {
      return _LinuxBindings(DynamicLibrary.open(libraryPath));
    } catch (error) {
      throw TerminalLinuxLibraryLoadException(libraryPath, error);
    }
  }

  final _LinuxBindings _bindings;

  @override
  LinuxPtySession create({
    required String commandLine,
    required int columns,
    required int rows,
    required int maximumBufferBytes,
  }) {
    final command = commandLine.toNativeUtf8();
    final out = calloc<Pointer<Void>>();
    try {
      _requireSuccess('create', _bindings.create(
        command,
        columns,
        rows,
        maximumBufferBytes,
        out,
      ));
      if (out.value == nullptr) {
        throw StateError('Linux PTY create returned a null handle.');
      }
      return LinuxPtySession._(_bindings, out.value);
    } finally {
      calloc.free(command);
      calloc.free(out);
    }
  }
}

final class LinuxPtySession implements TerminalHandle {
  LinuxPtySession._(this._bindings, this._handle);

  final _LinuxBindings _bindings;
  Pointer<Void> _handle;
  bool _closed = false;

  @override
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

  @override
  void write(List<int> bytes) {
    _requireOpen();
    if (bytes.isEmpty) return;
    final data = calloc<Uint8>(bytes.length);
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      _requireSuccess('write', _bindings.write(_handle, data, bytes.length));
    } finally {
      calloc.free(data);
    }
  }

  @override
  void resize({required int columns, required int rows}) {
    _requireOpen();
    _requireSuccess('resize', _bindings.resize(_handle, columns, rows));
  }

  @override
  void ctrlC() {
    _requireOpen();
    _requireSuccess('interrupt', _bindings.ctrlC(_handle));
  }

  @override
  LinuxPtyReadResult read({int maximumBytes = 16 * 1024}) {
    _requireOpen();
    if (maximumBytes < 1) throw RangeError.range(maximumBytes, 1, null);
    final buffer = calloc<Uint8>(maximumBytes);
    final length = calloc<Size>();
    final eof = calloc<Int32>();
    final overflow = calloc<Int32>();
    try {
      _requireSuccess('read', _bindings.read(
        _handle,
        buffer,
        maximumBytes,
        length,
        eof,
        overflow,
      ));
      return LinuxPtyReadResult(
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

  @override
  LinuxPtyExitResult wait() {
    _requireOpen();
    final exited = calloc<Int32>();
    final exitCode = calloc<Int32>();
    try {
      _requireSuccess('wait', _bindings.wait(_handle, 0, exited, exitCode));
      return LinuxPtyExitResult(
        exited.value != 0,
        exited.value != 0 ? exitCode.value : null,
      );
    } finally {
      calloc.free(exited);
      calloc.free(exitCode);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    final handle = _handle;
    _handle = nullptr;
    _requireSuccess('close', _bindings.close(handle));
  }

  void _requireOpen() {
    if (_closed) throw StateError('Linux PTY session is closed.');
  }
}

void _requireSuccess(String operation, int result) {
  if (result != 0) throw TerminalLinuxNativeException(operation, result);
}

final class _LinuxBindings {
  _LinuxBindings.codeAsset()
      : create = _assetCreate,
        write = _assetWrite,
        resize = _assetResize,
        read = _assetRead,
        ctrlC = _assetCtrlC,
        wait = _assetWait,
        processId = _assetPid,
        close = _assetClose;

  _LinuxBindings(DynamicLibrary library)
      : create = library.lookupFunction<_CreateNative, _CreateDart>(
          'rvterm_linux_create'),
        write = library.lookupFunction<_WriteNative, _WriteDart>(
          'rvterm_linux_write'),
        resize = library.lookupFunction<_ResizeNative, _ResizeDart>(
          'rvterm_linux_resize'),
        read = library.lookupFunction<_ReadNative, _ReadDart>(
          'rvterm_linux_read'),
        ctrlC = library.lookupFunction<_CtrlCNative, _CtrlCDart>(
          'rvterm_linux_ctrl_c'),
        wait = library.lookupFunction<_WaitNative, _WaitDart>(
          'rvterm_linux_wait'),
        processId = library.lookupFunction<_PidNative, _PidDart>(
          'rvterm_linux_process_id'),
        close = library.lookupFunction<_CloseNative, _CloseDart>(
          'rvterm_linux_close');

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
  Pointer<Utf8>, Uint16, Uint16, Size, Pointer<Pointer<Void>>);
typedef _CreateDart = int Function(
  Pointer<Utf8>, int, int, int, Pointer<Pointer<Void>>);
typedef _WriteNative = Int32 Function(Pointer<Void>, Pointer<Uint8>, Size);
typedef _WriteDart = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _ResizeNative = Int32 Function(Pointer<Void>, Uint16, Uint16);
typedef _ResizeDart = int Function(Pointer<Void>, int, int);
typedef _ReadNative = Int32 Function(
  Pointer<Void>, Pointer<Uint8>, Size, Pointer<Size>, Pointer<Int32>,
  Pointer<Int32>);
typedef _ReadDart = int Function(
  Pointer<Void>, Pointer<Uint8>, int, Pointer<Size>, Pointer<Int32>,
  Pointer<Int32>);
typedef _CtrlCNative = Int32 Function(Pointer<Void>);
typedef _CtrlCDart = int Function(Pointer<Void>);
typedef _WaitNative = Int32 Function(
  Pointer<Void>, Uint32, Pointer<Int32>, Pointer<Int32>);
typedef _WaitDart = int Function(
  Pointer<Void>, int, Pointer<Int32>, Pointer<Int32>);
typedef _PidNative = Int32 Function(Pointer<Void>, Pointer<Uint32>);
typedef _PidDart = int Function(Pointer<Void>, Pointer<Uint32>);
typedef _CloseNative = Int32 Function(Pointer<Void>);
typedef _CloseDart = int Function(Pointer<Void>);

const _assetId = 'package:remvibe_terminal/src/linux/linux_pty.dart';

@Native<_CreateNative>(symbol: 'rvterm_linux_create', assetId: _assetId)
external int _assetCreate(
  Pointer<Utf8> command, int columns, int rows, int maximumBufferBytes,
  Pointer<Pointer<Void>> outSession);

@Native<_WriteNative>(symbol: 'rvterm_linux_write', assetId: _assetId)
external int _assetWrite(Pointer<Void> session, Pointer<Uint8> bytes, int length);

@Native<_ResizeNative>(symbol: 'rvterm_linux_resize', assetId: _assetId)
external int _assetResize(Pointer<Void> session, int columns, int rows);

@Native<_ReadNative>(symbol: 'rvterm_linux_read', assetId: _assetId)
external int _assetRead(
  Pointer<Void> session, Pointer<Uint8> bytes, int capacity,
  Pointer<Size> outLength, Pointer<Int32> outEof,
  Pointer<Int32> outOverflow);

@Native<_CtrlCNative>(symbol: 'rvterm_linux_ctrl_c', assetId: _assetId)
external int _assetCtrlC(Pointer<Void> session);

@Native<_WaitNative>(symbol: 'rvterm_linux_wait', assetId: _assetId)
external int _assetWait(
  Pointer<Void> session, int timeoutMillis,
  Pointer<Int32> outExited, Pointer<Int32> outExitCode);

@Native<_PidNative>(symbol: 'rvterm_linux_process_id', assetId: _assetId)
external int _assetPid(Pointer<Void> session, Pointer<Uint32> outProcessId);

@Native<_CloseNative>(symbol: 'rvterm_linux_close', assetId: _assetId)
external int _assetClose(Pointer<Void> session);
