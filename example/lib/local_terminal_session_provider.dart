import 'dart:async';
import 'package:remvibe_terminal/remvibe_terminal.dart';

import 'terminal_widget/terminal_session_api.dart';

/// In-process adapter used ONLY by the Flutter example. The Console will
/// implement TerminalSessionProvider using its existing remote terminal
/// Server/Client protocol without importing any Windows PTY implementation.
final class LocalTerminalSessionProvider implements TerminalSessionProvider {
  const LocalTerminalSessionProvider(this.service);

  final TerminalSessionService service;

  @override
  Future<TerminalSessionBinding> create({
    required String profile,
    required int columns,
    required int rows,
  }) async {
    final commandLine = switch (profile) {
      'PowerShell' => 'powershell.exe -NoLogo -NoProfile',
      'CMD' => 'cmd.exe',
      _ => throw ArgumentError.value(profile, 'profile'),
    };
    final attachment = service.newTerminal(
      commandLine: commandLine,
      columns: columns,
      rows: rows,
    );
    return _LocalTerminalBinding(attachment, profile);
  }

  @override
  Future<List<TerminalSessionDescriptor>> listSessions() async =>
      service.items.map((state) {
        final label = state.commandLine.startsWith('powershell')
            ? 'PowerShell'
            : 'CMD';
        return TerminalSessionDescriptor(
          sessionId: state.sessionId,
          label: label,
          createdUtc: state.createdUtc,
          lastActivityUtc: state.lastActivityUtc,
          attached: state.attached,
          reattachable: !state.attached,
          replayTruncated: state.outputTruncated,
        );
      }).toList(growable: false);

  @override
  Future<TerminalSessionBinding> attach(
    String sessionId, {
    int afterSequence = 0,
  }) async {
    final snapshot = service.items.singleWhere(
      (s) => s.sessionId == sessionId,
    );
    final label = snapshot.commandLine.startsWith('powershell')
        ? 'PowerShell'
        : 'CMD';
    return _LocalTerminalBinding(
      service.attach(sessionId, afterSequence: afterSequence),
      label,
    );
  }

  @override
  Future<void> terminate(String sessionId) =>
      service.terminateSession(sessionId);
}

final class _LocalTerminalBinding implements TerminalSessionBinding {
  _LocalTerminalBinding(this._host, this.label);

  final HostedTerminalAttachment _host;
  @override
  final String label;

  @override
  String get sessionId => _host.sessionId;
  @override
  Stream<TerminalViewOutputFrame> get output => _host.output.map(
        (frame) => TerminalViewOutputFrame(
          sequence: frame.sequence,
          bytes: frame.bytes,
        ),
      );

  @override
  Future<int?> get exitCode => _host.exitCode;

  @override
  Future<void> input(List<int> bytes) async => _host.write(bytes);

  @override
  Future<void> resize({required int columns, required int rows}) async =>
      _host.resize(columns: columns, rows: rows);

  @override
  Future<void> interrupt() async => _host.interrupt();

  @override
  Future<void> detach() => _host.detach();
}
