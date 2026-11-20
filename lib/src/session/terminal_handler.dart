import 'dart:async';

import 'terminal_events.dart';
import 'terminal_session_service.dart';

/// A terminal viewer's neutral, transport-free event and control surface.
///
/// Observation is independent of control: registering a handler does not
/// claim native keyboard input, resize or interrupt ownership.
abstract interface class TerminalHandler implements TerminalEventSource {
  Future<void> input(List<int> bytes);
  Future<void> resize({required int columns, required int rows});
  Future<void> interrupt();

  /// Releases this handler's optional controller; does not stop the PTY.
  Future<void> detach();
}

/// Local implementation over one already hosted terminal.
///
/// Read-only use: TerminalHandlerLocal(terminal: session).
/// Controller use: pass an existing matching HostedTerminalAttachment.
/// A second controller is NOT created by this constructor.
final class TerminalHandlerLocal implements TerminalHandler {
  TerminalHandlerLocal({
    required this.terminal,
    this.controller,
  }) {
    if (controller != null && controller!.sessionId != terminal.terminalId) {
      throw ArgumentError('Controller and terminal IDs do not match.');
    }
  }

  final TerminalSession terminal;
  final HostedTerminalAttachment? controller;

  @override
  String get terminalId => terminal.terminalId;

  @override
  TerminalHandlerRegistration registerHandler({
    TerminalStateCallback? onTerminalState,
    TerminalStreamCallback? onTerminalStream,
    int afterSequence = 0,
  }) {
    return terminal.registerHandler(
      afterSequence: afterSequence,
      onTerminalState: onTerminalState == null
          ? null
          : (_, event) => onTerminalState(this, event),
      onTerminalStream: onTerminalStream == null
          ? null
          : (_, event) => onTerminalStream(this, event),
    );
  }

  @override
  Future<void> unregisterHandler(TerminalHandlerRegistration registration) =>
      terminal.unregisterHandler(registration);

  HostedTerminalAttachment get _activeController {
    final attachment = controller;
    if (attachment == null || !attachment.isAttached) {
      throw StateError('No active local controller for terminal $terminalId');
    }
    return attachment;
  }

  @override
  Future<void> input(List<int> bytes) async => _activeController.write(bytes);

  @override
  Future<void> resize({required int columns, required int rows}) async =>
      _activeController.resize(columns: columns, rows: rows);

  @override
  Future<void> interrupt() async => _activeController.interrupt();

  @override
  Future<void> detach() async {
    // A read-only viewer has no controller to release.
    await controller?.detach();
  }
}
