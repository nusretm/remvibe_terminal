import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../remvibe_terminal.dart';

/// A locally hosted PTY; this interface also enables OS-free registry tests.
abstract interface class HostedTerminalProcess {
  int get processId;
  Stream<Uint8List> get output;
  Future<int?> get exitCode;
  bool get isClosed;
  void write(List<int> bytes);
  void resize({required int columns, required int rows});
  void interrupt();
  Future<void> close();
}

typedef HostedTerminalProcessFactory = HostedTerminalProcess Function({
  required String commandLine,
  required int columns,
  required int rows,
  required int maximumBufferBytes,
});

final class TerminalOutputFrame {
  TerminalOutputFrame({required this.sequence, required List<int> bytes})
      : bytes = Uint8List.fromList(bytes);
  final int sequence;
  final Uint8List bytes;
}

final class HostedTerminalInfo {
  const HostedTerminalInfo({
    required this.sessionId,
    required this.processId,
    required this.commandLine,
    required this.createdUtc,
    required this.lastActivityUtc,
    required this.attached,
    required this.detachedUtc,
    required this.lastOutputSequence,
    required this.firstRetainedSequence,
    required this.outputTruncated,
  });
  final String sessionId;
  final int processId;
  final String commandLine;
  final DateTime createdUtc;
  final DateTime lastActivityUtc;
  final bool attached;
  final DateTime? detachedUtc;
  final int lastOutputSequence;
  final int firstRetainedSequence;
  final bool outputTruncated;
}

/// Detaching a viewer does not kill its native process.
final class HostedTerminalAttachment {
  HostedTerminalAttachment._(this._pool, this._record, this._frames);
  final TerminalSessionPool _pool;
  final _HostedRecord _record;
  final StreamController<TerminalOutputFrame> _frames;
  bool _detached = false;

  String get sessionId => _record.id;
  int get processId => _record.process.processId;
  Stream<TerminalOutputFrame> get output => _frames.stream;
  Future<int?> get exitCode => _record.process.exitCode;
  bool get isAttached =>
      !_detached && identical(_record.attachment, this) && !_record.terminated;

  void write(List<int> bytes) {
    _requireAttached();
    if (bytes.isEmpty) return;
    _record.process.write(bytes);
    _pool._touch(_record);
  }

  void resize({required int columns, required int rows}) {
    _requireAttached();
    _record.process.resize(columns: columns, rows: rows);
    _pool._touch(_record);
  }

  void interrupt() {
    _requireAttached();
    _record.process.interrupt();
    _pool._touch(_record);
  }

  Future<void> detach() async {
    _pool._detach(this);
  }

  Future<void> terminate() => _pool.terminateSession(sessionId);

  void _requireAttached() {
    if (!isAttached || _pool.isClosed) {
      throw StateError('Terminal attachment is not active: $sessionId');
    }
  }

  void _closeStream() {
    if (_detached) return;
    _detached = true;
    unawaited(_frames.close());
  }
}

final class _HostedRecord {
  _HostedRecord({
    required this.id,
    required this.commandLine,
    required this.process,
    required this.createdUtc,
  }) : lastActivityUtc = createdUtc;

  final String id;
  final String commandLine;
  final HostedTerminalProcess process;
  final DateTime createdUtc;
  DateTime lastActivityUtc;
  DateTime? detachedUtc;
  StreamSubscription<Uint8List>? subscription;
  HostedTerminalAttachment? attachment;
  final List<TerminalOutputFrame> retained = [];
  int retainedBytes = 0;
  int lastOutputSequence = 0;
  bool outputTruncated = false;
  bool terminated = false;

  HostedTerminalInfo snapshot() => HostedTerminalInfo(
        sessionId: id,
        processId: process.processId,
        commandLine: commandLine,
        createdUtc: createdUtc,
        lastActivityUtc: lastActivityUtc,
        attached: attachment != null && attachment!.isAttached,
        detachedUtc: detachedUtc,
        lastOutputSequence: lastOutputSequence,
        firstRetainedSequence:
            retained.isEmpty ? lastOutputSequence + 1 : retained.first.sequence,
        outputTruncated: outputTruncated,
      );
}

/// Own one pool per Client process, not one pool per Console widget.
///
/// The application is responsible for authenticated routing and authorization.
/// The pool only tracks local processes and short bounded output replay.
/// Detached PTYs expire after 10 minutes by default; output does not extend
/// the timer. Long-running detached commands require an app-level exception.
final class TerminalSessionPool {
  TerminalSessionPool({
    required HostedTerminalProcessFactory processFactory,
    this.maximumSessions = 4,
    this.maximumReplayBytes = 64 * 1024,
    this.detachedIdleTimeout = const Duration(minutes: 10),
    this.sweepInterval = const Duration(seconds: 5),
    DateTime Function()? clock,
  })  : _createProcess = processFactory,
        _clock = clock ?? DateTime.now {
    if (maximumSessions < 1 ||
        maximumReplayBytes < 1 ||
        detachedIdleTimeout <= Duration.zero ||
        sweepInterval <= Duration.zero) {
      throw ArgumentError('Invalid session pool limits.');
    }
    _sweepTimer = Timer.periodic(sweepInterval, (_) {
      unawaited(expireIdleSessions());
    });
  }

  factory TerminalSessionPool.withEngine({
    required RemVibeTerminal engine,
    int maximumSessions = 4,
    int maximumReplayBytes = 64 * 1024,
    Duration detachedIdleTimeout = const Duration(minutes: 10),
    Duration sweepInterval = const Duration(seconds: 5),
  }) =>
      TerminalSessionPool(
        processFactory: ({
          required commandLine,
          required columns,
          required rows,
          required maximumBufferBytes,
        }) =>
            _NativeHostedProcess(
          engine.create(
            commandLine: commandLine,
            columns: columns,
            rows: rows,
            maximumBufferBytes: maximumBufferBytes,
          ),
        ),
        maximumSessions: maximumSessions,
        maximumReplayBytes: maximumReplayBytes,
        detachedIdleTimeout: detachedIdleTimeout,
        sweepInterval: sweepInterval,
      );

  final HostedTerminalProcessFactory _createProcess;
  final DateTime Function() _clock;
  final int maximumSessions;
  final int maximumReplayBytes;
  final Duration detachedIdleTimeout;
  final Duration sweepInterval;
  final Map<String, _HostedRecord> _sessions = {};
  late final Timer _sweepTimer;
  bool _closed = false;

  bool get isClosed => _closed;
  int get activeSessionCount => _sessions.length;
  DateTime _now() => _clock().toUtc();

  /// An application may pass its own Server-issued terminalSessionId.
  HostedTerminalAttachment create({
    String? sessionId,
    required String commandLine,
    int columns = 80,
    int rows = 24,
    int maximumBufferBytes = 256 * 1024,
  }) {
    _requireOpen();
    if (_sessions.length >= maximumSessions) {
      throw StateError('Maximum terminal sessions reached ($maximumSessions).');
    }
    if (commandLine.trim().isEmpty) {
      throw ArgumentError.value(commandLine, 'commandLine');
    }
    final id = sessionId ?? _generateId();
    if (id.trim().isEmpty || _sessions.containsKey(id)) {
      throw StateError('Duplicate or empty terminal session ID: $id');
    }

    final process = _createProcess(
      commandLine: commandLine,
      columns: columns,
      rows: rows,
      maximumBufferBytes: maximumBufferBytes,
    );
    final record = _HostedRecord(
      id: id,
      commandLine: commandLine,
      process: process,
      createdUtc: _now(),
    );
    _sessions[id] = record;
    try {
      record.subscription = process.output.listen(
        (bytes) => _onOutput(record, bytes),
        onError: (Object error, StackTrace trace) {
          unawaited(_terminateRecord(record));
        },
      );
      unawaited(_watchExit(record));
      return _attach(record);
    } catch (_) {
      _sessions.remove(id);
      unawaited(process.close());
      rethrow;
    }
  }

  /// Default replays retained frames; afterSequence resumes only new frames.
  HostedTerminalAttachment attach(
    String sessionId, {
    int afterSequence = 0,
  }) {
    _requireOpen();
    if (afterSequence < 0) {
      throw ArgumentError.value(afterSequence, 'afterSequence');
    }
    return _attach(_requireSession(sessionId), afterSequence: afterSequence);
  }

  List<HostedTerminalInfo> listSessions() {
    _requireOpen();
    final snapshots =
        _sessions.values.map((record) => record.snapshot()).toList();
    snapshots.sort((a, b) {
      final byCreation = a.createdUtc.compareTo(b.createdUtc);
      return byCreation != 0
          ? byCreation
          : a.sessionId.compareTo(b.sessionId);
    });
    return List.unmodifiable(snapshots);
  }

  bool contains(String sessionId) =>
      !_closed && _sessions.containsKey(sessionId);

  Future<void> terminateSession(String sessionId) async {
    _requireOpen();
    final record = _sessions[sessionId];
    if (record != null) await _terminateRecord(record);
  }

  Future<void> expireIdleSessions() async {
    if (_closed) return;
    final now = _now();
    final expired = _sessions.values
        .where((record) =>
            !record.terminated &&
            record.attachment == null &&
            record.detachedUtc != null &&
            now.difference(record.lastActivityUtc) >= detachedIdleTimeout)
        .toList(growable: false);
    for (final record in expired) {
      await _terminateRecord(record);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _sweepTimer.cancel();
    final records = _sessions.values.toList(growable: false);
    for (final record in records) {
      await _terminateRecord(record);
    }
  }

  HostedTerminalAttachment _attach(
    _HostedRecord record, {
    int afterSequence = 0,
  }) {
    if (record.attachment != null) {
      throw StateError('Terminal is already attached: ' + record.id);
    }
    final controller = StreamController<TerminalOutputFrame>();
    final attachment = HostedTerminalAttachment._(this, record, controller);
    record.attachment = attachment;
    record.detachedUtc = null;
    _touch(record);
    for (final frame in record.retained) {
      if (frame.sequence > afterSequence) controller.add(frame);
    }
    return attachment;
  }

  void _detach(HostedTerminalAttachment attachment) {
    if (attachment._detached) return;
    final record = attachment._record;
    attachment._closeStream();
    if (!identical(record.attachment, attachment)) return;
    record.attachment = null;
    record.detachedUtc = _now();
    _touch(record);
  }

  void _onOutput(_HostedRecord record, Uint8List bytes) {
    if (record.terminated || bytes.isEmpty) return;
    final frame = TerminalOutputFrame(
      sequence: ++record.lastOutputSequence,
      bytes: bytes,
    );
    record.retained.add(frame);
    record.retainedBytes += frame.bytes.length;
    while (record.retainedBytes > maximumReplayBytes &&
        record.retained.isNotEmpty) {
      final removed = record.retained.removeAt(0);
      record.retainedBytes -= removed.bytes.length;
      record.outputTruncated = true;
    }
    record.attachment?._frames.add(frame);
  }

  void _touch(_HostedRecord record) {
    if (!record.terminated) record.lastActivityUtc = _now();
  }

  Future<void> _watchExit(_HostedRecord record) async {
    try {
      await record.process.exitCode;
    } catch (_) {
      // Unexpected exit still releases the resource.
    }
    await _terminateRecord(record);
  }

  Future<void> _terminateRecord(_HostedRecord record) async {
    if (record.terminated) return;
    record.terminated = true;
    if (identical(_sessions[record.id], record)) _sessions.remove(record.id);
    final attachment = record.attachment;
    record.attachment = null;
    attachment?._closeStream();
    await record.subscription?.cancel();
    await record.process.close();
  }

  _HostedRecord _requireSession(String id) {
    final record = _sessions[id];
    if (record == null || record.terminated) {
      throw StateError('Terminal session not found or expired: $id');
    }
    return record;
  }

  void _requireOpen() {
    if (_closed) throw StateError('Terminal session pool closed.');
  }

  String _generateId() {
    final random = Random.secure();
    String hex(int count) => List.generate(
          count,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    return hex(4) + '-' + hex(2) + '-' + hex(2) + '-' +
        hex(2) + '-' + hex(6);
  }
}

final class _NativeHostedProcess implements HostedTerminalProcess {
  _NativeHostedProcess(this._session);
  final RemVibeTerminalSession _session;

  @override
  int get processId => _session.processId;
  @override
  bool get isClosed => _session.isClosed;
  @override
  Stream<Uint8List> get output => _session.output;
  @override
  Future<int?> get exitCode => _session.exitCode;
  @override
  void write(List<int> bytes) => _session.write(bytes);
  @override
  void resize({required int columns, required int rows}) =>
      _session.resize(columns: columns, rows: rows);
  @override
  void interrupt() => _session.interrupt();
  @override
  Future<void> close() => _session.close();
}
