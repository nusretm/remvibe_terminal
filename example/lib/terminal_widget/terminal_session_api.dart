import 'dart:typed_data';

/// UI-owned output frame. A remote adapter maps its routed output sequence
/// and raw bytes here; a local adapter maps HostedTerminalAttachment output.
final class TerminalViewOutputFrame {
  const TerminalViewOutputFrame({required this.sequence, required this.bytes});
  final int sequence;
  final Uint8List bytes;
}

/// A device-scoped discovery entry. The transport decides whether an actor is
/// authorized to see or reattach it; session IDs are NOT bearer credentials.
final class TerminalSessionDescriptor {
  const TerminalSessionDescriptor({
    required this.sessionId,
    required this.label,
    required this.createdUtc,
    required this.lastActivityUtc,
    required this.attached,
    required this.reattachable,
    this.deviceUuid,
    this.replayTruncated = false,
  });

  final String sessionId;
  final String label;
  final String? deviceUuid;
  final DateTime createdUtc;
  final DateTime lastActivityUtc;
  final bool attached;
  final bool reattachable;
  final bool replayTruncated;
}

/// A single attached terminal view. No ConPTY, Fleet or Networking type is
/// exposed to the Flutter widget. A Console adapter implements this interface
/// by routing messages through its existing authorized Server/Client path.
///
/// IMPORTANT: detach is non-destructive; terminate belongs to the provider.
/// interrupt means Ctrl+C input, NEVER a destructive remote cancel.
abstract interface class TerminalSessionBinding {
  String get sessionId;
  String get label;
  Stream<TerminalViewOutputFrame> get output;
  Future<int?> get exitCode;

  Future<void> input(List<int> bytes);
  Future<void> resize({required int columns, required int rows});
  Future<void> interrupt();
  Future<void> detach();
}

/// The Console owns the device selection and authorized session routing.
///
/// The widget itself only needs a TerminalSessionBinding. A remote Console
/// provider maps create/list/attach/detach/terminate to the existing Fleet
/// protocol. The example uses a local in-process TerminalSessionPool instead.
abstract interface class TerminalSessionProvider {
  Future<TerminalSessionBinding> create({
    required String profile,
    required int columns,
    required int rows,
  });

  Future<List<TerminalSessionDescriptor>> listSessions();

  Future<TerminalSessionBinding> attach(
    String sessionId, {
    int afterSequence = 0,
  });

  Future<void> terminate(String sessionId);
}
