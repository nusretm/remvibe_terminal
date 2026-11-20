import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import '../remvibe_terminal.dart';
import 'terminal_events.dart';

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

enum HostedTerminalCommandActivity { idle, running, unknown }

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
    required this.commandActivity,
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
  final HostedTerminalCommandActivity commandActivity;
}

/// Detaching a viewer does not kill its native process.
final class HostedTerminalAttachment {
  HostedTerminalAttachment._(this._service, this._record, this._frames);
  final TerminalSessionService _service;
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
    _service._touch(_record);
  }

  void resize({required int columns, required int rows}) {
    _requireAttached();
    _record.process.resize(columns: columns, rows: rows);
    _service._touch(_record);
  }

  void interrupt() {
    _requireAttached();
    _record.process.interrupt();
    _service._touch(_record);
  }

  Future<void> detach() async {
    _service._detach(this);
  }

  Future<void> terminate() => _service.terminateSession(sessionId);

  void _requireAttached() {
    if (!isAttached || _service.isClosed) {
      throw StateError('Terminal attachment is not active: $sessionId');
    }
  }

  void _closeStream() {
    if (_detached) return;
    _detached = true;
    unawaited(_frames.close());
  }
}

/// Stable, non-owning local terminal handle. Observation is not attachment.
final class TerminalSession implements TerminalEventSource {
  TerminalSession._(this._service, this._record);

  final TerminalSessionService _service;
  final _HostedRecord _record;
  final Map<TerminalHandlerRegistration, _RegisteredTerminalHandler>
      _registrations = {};

  @override
  String get terminalId => _record.id;

  HostedTerminalInfo get info => _record.snapshot();

  @override
  TerminalHandlerRegistration registerHandler({
    TerminalStateCallback? onTerminalState,
    TerminalStreamCallback? onTerminalStream,
    int afterSequence = 0,
  }) {
    if (_service.isClosed || _record.terminated) {
      throw StateError('Terminal is not active: $terminalId');
    }
    if (onTerminalState == null && onTerminalStream == null) {
      throw ArgumentError('At least one terminal callback is required.');
    }
    if (afterSequence < 0 ||
        afterSequence > _record.lastOutputSequence) {
      throw RangeError.range(
        afterSequence, 0, _record.lastOutputSequence, 'afterSequence',
      );
    }
    final token = TerminalHandlerRegistration();
    final subscriber = _RegisteredTerminalHandler(
      source: this,
      record: _record,
      onState: onTerminalState,
      onStream: onTerminalStream,
      afterSequence: afterSequence,
    );
    _registrations[token] = subscriber;

    // Registration, snapshot and replay enqueue synchronously in one isolate.
    // Output that arrives later always follows replay for this subscriber.
    if (onTerminalState != null) {
      subscriber.addState(_event(
        TerminalStateEventKind.created,
        when: _record.createdUtc,
        replayed: true,
      ));
      subscriber.addState(_event(TerminalStateEventKind.snapshot));
    }
    if (onTerminalStream != null) {
      for (final frame in _record.retained) {
        if (frame.sequence > afterSequence) {
          subscriber.addOutput(frame, replayed: true);
        }
      }
    }
    return token;
  }

  @override
  Future<void> unregisterHandler(
    TerminalHandlerRegistration registration,
  ) async {
    // Cancels only this registration, not the controller or process.
    _registrations.remove(registration)?.cancel();
  }

  TerminalStateEvent _event(
    TerminalStateEventKind kind, {
    DateTime? when,
    int? exitCode,
    bool replayed = false,
  }) =>
      TerminalStateEvent(
        terminalId: terminalId,
        kind: kind,
        timestampUtc: when ?? _service._now(),
        commandState: switch (_record.commandActivity) {
          HostedTerminalCommandActivity.idle => TerminalCommandState.idle,
          HostedTerminalCommandActivity.running => TerminalCommandState.busy,
          HostedTerminalCommandActivity.unknown => TerminalCommandState.unknown,
        },
        controllerAttached:
            _record.attachment != null && _record.attachment!.isAttached,
        exitCode: exitCode,
        replayed: replayed,
      );

  void _emitState(TerminalStateEventKind kind, {int? exitCode}) {
    final event = _event(kind, exitCode: exitCode);
    for (final subscriber in _registrations.values.toList()) {
      subscriber.addState(event);
    }
  }

  void _emitOutput(TerminalOutputFrame frame) {
    for (final subscriber in _registrations.values.toList()) {
      subscriber.addOutput(frame);
    }
  }

  void _finish() {
    for (final subscriber in _registrations.values.toList()) {
      subscriber.finish();
    }
    _registrations.clear();
  }
}

final class _PendingTerminalDelivery {
  _PendingTerminalDelivery.state(this.state)
      : frame = null, replayed = false;
  _PendingTerminalDelivery.output(this.frame, this.replayed) : state = null;

  final TerminalStateEvent? state;
  final TerminalOutputFrame? frame;
  final bool replayed;
  int get byteLength => frame?.bytes.length ?? 0;
}

/// One bounded async queue per viewer. Slow futures and callback failures
/// cannot stop the PTY reader or other viewers' delivery queues.
final class _RegisteredTerminalHandler {
  _RegisteredTerminalHandler({
    required this.source,
    required this.record,
    required this.onState,
    required this.onStream,
    required int afterSequence,
  }) : _lastSequence = afterSequence;

  static const int _maximumPendingEvents = 128;
  static const int _maximumPendingBytes = 128 * 1024;

  final TerminalSession source;
  final _HostedRecord record;
  final TerminalStateCallback? onState;
  final TerminalStreamCallback? onStream;
  final Queue<_PendingTerminalDelivery> _pending = Queue();
  int _pendingBytes = 0;
  int _lastSequence;
  bool _processing = false;
  bool _cancelled = false;
  bool _finishing = false;

  void addState(TerminalStateEvent event) {
    if (onState != null) _enqueue(_PendingTerminalDelivery.state(event));
  }

  void addOutput(TerminalOutputFrame frame, {bool replayed = false}) {
    if (onStream == null || _cancelled) return;
    // Oversized data is deliberately dropped; the sequence-gap event
    // exposes loss instead of growing an unbounded subscriber queue.
    if (frame.bytes.length > _maximumPendingBytes) {
      _schedule();
      return;
    }
    _enqueue(_PendingTerminalDelivery.output(frame, replayed));
  }

  void _enqueue(_PendingTerminalDelivery event) {
    if (_cancelled) return;
    while (_pending.isNotEmpty &&
        (_pending.length >= _maximumPendingEvents ||
            _pendingBytes + event.byteLength > _maximumPendingBytes)) {
      _pendingBytes -= _pending.removeFirst().byteLength;
    }
    _pending.addLast(event);
    _pendingBytes += event.byteLength;
    _schedule();
  }

  void _schedule() {
    if (_processing || _cancelled) return;
    _processing = true;
    scheduleMicrotask(() { unawaited(_drain()); });
  }

  Future<void> _deliverGap(int first, int last) async {
    if (onStream == null || last < first || _cancelled) return;
    _lastSequence = last;
    try {
      await onStream!(
        source,
        TerminalStreamEvent.gap(
          terminalId: source.terminalId,
          fromSequence: first,
          toSequence: last,
        ),
      );
    } catch (_) {
      // Subscribers are not allowed to crash the native output reader.
    }
  }

  Future<void> _drain() async {
    try {
      while (!_cancelled) {
        if (_pending.isEmpty) {
          // Also report replay truncation with no retained output, and a
          // discarded tail after queue overflow even if no later frame arrives.
          if (onStream != null && record.lastOutputSequence > _lastSequence) {
            await _deliverGap(_lastSequence + 1, record.lastOutputSequence);
            continue;
          }
          break;
        }
        final next = _pending.removeFirst();
        _pendingBytes -= next.byteLength;
        final state = next.state;
        if (state != null && onState != null) {
          try {
            await onState!(source, state);
          } catch (_) {
            // One callback cannot affect another subscriber.
          }
          continue;
        }
        final frame = next.frame;
        if (frame == null || onStream == null ||
            frame.sequence <= _lastSequence) {
          continue;
        }
        if (frame.sequence > _lastSequence + 1) {
          await _deliverGap(_lastSequence + 1, frame.sequence - 1);
        }
        if (_cancelled) break;
        _lastSequence = frame.sequence;
        try {
          await onStream!(
            source,
            TerminalStreamEvent.output(
              terminalId: source.terminalId,
              sequence: frame.sequence,
              bytes: frame.bytes,
              replayed: next.replayed,
            ),
          );
        } catch (_) {
          // Deliver subsequent events even after a consumer callback fails.
        }
      }
    } finally {
      _processing = false;
      if (_finishing) {
        cancel();
      } else if (!_cancelled && _pending.isNotEmpty) {
        _schedule();
      }
    }
  }

  void finish() {
    if (_cancelled) return;
    _finishing = true;
    _schedule();
  }

  void cancel() {
    _cancelled = true;
    _pending.clear();
    _pendingBytes = 0;
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
  late final TerminalSession terminal;
  HostedTerminalAttachment? attachment;
  final List<TerminalOutputFrame> retained = [];
  int retainedBytes = 0;
  int lastOutputSequence = 0;
  bool outputTruncated = false;
  HostedTerminalCommandActivity commandActivity =
      HostedTerminalCommandActivity.idle;
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
        commandActivity: commandActivity,
      );
}

/// Own one service per Client Dart isolate, not one per Console widget.
///
/// The application is responsible for authenticated routing and authorization.
/// The service tracks local processes and short bounded output replay.
/// Detached idle PTYs expire after 10 minutes by default. The Server may mark
/// running commands to preserve them and unknown activity gets a 30-minute
/// fail-safe. Output by itself never silently refreshes activity.
final class TerminalSessionService {
  /// Returns the explicitly registered service for this Dart isolate.
  ///
  /// A Client creates one service during process startup with [withEngine],
  /// then calls [register]. A Console may also host its own local service;
  /// remote sessions use a separately implemented consumer adapter.
  factory TerminalSessionService() => instance;

  static TerminalSessionService? _registered;

  static TerminalSessionService get instance {
    final service = _registered;
    if (service == null || service.isClosed) {
      throw StateError(
        'TerminalSessionService has not been registered for this isolate. '
        'Create with .withEngine(...) and call TerminalSessionService.register().',
      );
    }
    return service;
  }

  /// Explicitly registers one hosting service. Re-registering a DIFFERENT
  /// live service fails; closing the registered instance releases the slot.
  /// Resolve a terminal from the explicitly registered local service.
  static TerminalSession? getTerminal(String terminalId) =>
      instance.findTerminal(terminalId);

  static TerminalSessionService register(TerminalSessionService service) {
    if (service.isClosed) {
      throw StateError('Cannot register a closed terminal session service.');
    }
    final current = _registered;
    if (current != null && !current.isClosed && !identical(current, service)) {
      throw StateError('Another TerminalSessionService is already registered.');
    }
    _registered = service;
    return service;
  }

  /// Independent instance for tests or a separately scoped local host.
  /// Does not overwrite the registered process-wide instance.
  TerminalSessionService.withFactory({
    required HostedTerminalProcessFactory processFactory,
    this.maximumSessions = 4,
    this.maximumReplayBytes = 64 * 1024,
    this.detachedIdleTimeout = const Duration(minutes: 10),
    this.unknownCommandFailSafeTimeout = const Duration(minutes: 30),
    this.sweepInterval = const Duration(seconds: 5),
    DateTime Function()? clock,
  })  : _createProcess = processFactory,
        _clock = clock ?? DateTime.now {
    if (maximumSessions < 1 ||
        maximumReplayBytes < 1 ||
        detachedIdleTimeout <= Duration.zero ||
        unknownCommandFailSafeTimeout <= Duration.zero ||
        sweepInterval <= Duration.zero) {
      throw ArgumentError('Invalid terminal session service limits.');
    }
    _sweepTimer = Timer.periodic(sweepInterval, (_) {
      unawaited(expireIdleSessions());
    });
  }

  factory TerminalSessionService.withEngine({
    required RemVibeTerminal engine,
    int maximumSessions = 4,
    int maximumReplayBytes = 64 * 1024,
    Duration detachedIdleTimeout = const Duration(minutes: 10),
    Duration unknownCommandFailSafeTimeout = const Duration(minutes: 30),
    Duration sweepInterval = const Duration(seconds: 5),
  }) =>
      TerminalSessionService.withFactory(
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
        unknownCommandFailSafeTimeout: unknownCommandFailSafeTimeout,
        sweepInterval: sweepInterval,
      );

  final HostedTerminalProcessFactory _createProcess;
  final DateTime Function() _clock;
  final int maximumSessions;
  final int maximumReplayBytes;
  final Duration detachedIdleTimeout;
  final Duration unknownCommandFailSafeTimeout;
  final Duration sweepInterval;
  final Map<String, _HostedRecord> _sessions = {};
  final StreamController<List<HostedTerminalInfo>> _itemChanges =
      StreamController<List<HostedTerminalInfo>>.broadcast();
  late final Timer _sweepTimer;
  bool _closed = false;

  bool get isClosed => _closed;
  int get activeSessionCount => _sessions.length;

  /// Immutable live snapshots; call this getter again for the latest list.
  /// Do not store these snapshots as process handles.
  List<HostedTerminalInfo> get items => listSessions();

  /// Notifies when sessions are created, attached, detached, removed or their
  /// command state changes. Subscribe after reading [items] for initial data.
  /// Output frames are NOT emitted as list updates on every chunk.
  Stream<List<HostedTerminalInfo>> get itemsChanged => _itemChanges.stream;

  void _notifyItems() {
    if (!_closed && !_itemChanges.isClosed) _itemChanges.add(listSessions());
  }

  DateTime _now() => _clock().toUtc();

  /// An application may pass its own Server-issued terminalSessionId.
  HostedTerminalAttachment newTerminal({
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
    record.terminal = TerminalSession._(this, record);
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

  /// Lookup for independent test hosts; never attaches or creates a PTY.
  TerminalSession? findTerminal(String sessionId) {
    if (_closed) return null;
    return _sessions[sessionId]?.terminal;
  }

  /// The authoritative application/Server can mark a command running,
  /// unknown or idle. Running detached commands are exempt from idle expiry,
  /// matching the earlier Fleet session policy.
  void setCommandActivity(
    String sessionId,
    HostedTerminalCommandActivity activity,
  ) {
    _requireOpen();
    final record = _requireSession(sessionId);
    if (record.commandActivity == activity) return;
    record.commandActivity = activity;
    _touch(record);
    _notifyItems();
    record.terminal._emitState(TerminalStateEventKind.commandActivityChanged);
  }

  Future<void> terminateSession(String sessionId) async {
    _requireOpen();
    final record = _sessions[sessionId];
    if (record != null) await _terminateRecord(record);
  }

  Future<void> expireIdleSessions() async {
    if (_closed) return;
    final now = _now();
    final expired = _sessions.values.where((record) {
      if (record.terminated ||
          record.attachment != null ||
          record.detachedUtc == null) {
        return false;
      }
      final timeout = switch (record.commandActivity) {
        HostedTerminalCommandActivity.idle => detachedIdleTimeout,
        HostedTerminalCommandActivity.unknown => unknownCommandFailSafeTimeout,
        HostedTerminalCommandActivity.running => null,
      };
      return timeout != null &&
          now.difference(record.lastActivityUtc) >= timeout;
    }).toList(growable: false);
    for (final record in expired) {
      await _terminateRecord(record, kind: TerminalStateEventKind.expired);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _sweepTimer.cancel();
    final records = _sessions.values.toList(growable: false);
    try {
      for (final record in records) {
        await _terminateRecord(record);
      }
    } finally {
      // Even when native close fails, do not keep a dead singleton registered.
      if (identical(_registered, this)) _registered = null;
      await _itemChanges.close();
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
    _notifyItems();
    record.terminal._emitState(TerminalStateEventKind.attached);
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
    _notifyItems();
    record.terminal._emitState(TerminalStateEventKind.detached);
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
    record.terminal._emitOutput(frame);
  }

  void _touch(_HostedRecord record) {
    if (!record.terminated) record.lastActivityUtc = _now();
  }

  Future<void> _watchExit(_HostedRecord record) async {
    int? code;
    try {
      code = await record.process.exitCode;
    } catch (_) {
      // An unexpected native exit does not imply a known exit code.
    }
    await _terminateRecord(
      record,
      kind: TerminalStateEventKind.exited,
      exitCode: code,
    );
  }

  Future<void> _terminateRecord(
    _HostedRecord record, {
    TerminalStateEventKind kind = TerminalStateEventKind.terminated,
    int? exitCode,
  }) async {
    if (record.terminated) return;
    record.terminated = true;
    if (identical(_sessions[record.id], record)) _sessions.remove(record.id);
    final attachment = record.attachment;
    record.attachment = null;
    _notifyItems();
    record.terminal._emitState(kind, exitCode: exitCode);
    record.terminal._finish();
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
    if (_closed) throw StateError('Terminal session service closed.');
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
