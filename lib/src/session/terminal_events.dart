import 'dart:async';
import 'dart:typed_data';

/// A terminal's command activity is independent of viewer attachment.
///
/// Busy/idle transitions require an authoritative caller. Raw output,
/// prompt text and silence do not establish command completion.
enum TerminalCommandState { busy, idle, unknown }

enum TerminalStateEventKind {
  created,
  snapshot,
  attached,
  detached,
  commandActivityChanged,
  exited,
  terminated,
  expired,
}

/// Terminal lifecycle or explicitly supplied command state.
final class TerminalStateEvent {
  const TerminalStateEvent({
    required this.terminalId,
    required this.kind,
    required this.timestampUtc,
    required this.commandState,
    required this.controllerAttached,
    this.exitCode,
    this.replayed = false,
  });

  final String terminalId;
  final TerminalStateEventKind kind;
  final DateTime timestampUtc;
  final TerminalCommandState commandState;
  final bool controllerAttached;
  final int? exitCode;
  final bool replayed;
}

/// One raw PTY output frame, or an explicit inclusive missing-frame range.
final class TerminalStreamEvent {
  TerminalStreamEvent.output({
    required this.terminalId,
    required this.sequence,
    required List<int> bytes,
    this.replayed = false,
  })  : bytes = Uint8List.fromList(bytes),
        isGap = false,
        gapFromSequence = null,
        gapToSequence = null;

  TerminalStreamEvent.gap({
    required this.terminalId,
    required int fromSequence,
    required int toSequence,
  })  : sequence = toSequence,
        bytes = Uint8List(0),
        replayed = false,
        isGap = true,
        gapFromSequence = fromSequence,
        gapToSequence = toSequence {
    if (fromSequence < 1 || toSequence < fromSequence) {
      throw ArgumentError('Invalid terminal output gap.');
    }
  }

  final String terminalId;
  final int sequence;
  final Uint8List bytes;
  final bool replayed;
  final bool isGap;
  final int? gapFromSequence;
  final int? gapToSequence;
}

/// Identity-owned subscription token, not a PTY or control handle.
final class TerminalHandlerRegistration {
  TerminalHandlerRegistration();
}

/// A terminal-specific, UI- and transport-independent event source.
///
/// Each registration is independent. Unregistration never detaches, closes,
/// terminates, or mutates the underlying terminal's command state.
abstract interface class TerminalEventSource {
  String get terminalId;

  TerminalHandlerRegistration registerHandler({
    TerminalStateCallback? onTerminalState,
    TerminalStreamCallback? onTerminalStream,
    int afterSequence = 0,
  });

  Future<void> unregisterHandler(TerminalHandlerRegistration registration);
}

typedef TerminalStateCallback = FutureOr<void> Function(
  TerminalEventSource terminal,
  TerminalStateEvent event,
);

typedef TerminalStreamCallback = FutureOr<void> Function(
  TerminalEventSource terminal,
  TerminalStreamEvent event,
);
