import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm2/xterm.dart';

import 'stable_scrollback_terminal_view.dart';
import 'terminal_clipboard_paste.dart';
import 'terminal_resize_coordinator.dart';
import 'terminal_session_api.dart';

/// Reusable Flutter terminal for local or remote sessions.
///
/// Copy this folder into the Update Center Console and implement
/// TerminalSessionBinding using its existing authorized Server/Client route.
/// This widget has no DLL, process, device discovery or networking dependency.
///
/// Disposal DETACHES the view, rather than terminating the shell. A parent
/// invokes TerminalSessionProvider.terminate for explicit destruction.
/// Give every new attached binding a distinct widget key.
class RemVibeTerminalWidget extends StatefulWidget {
  const RemVibeTerminalWidget({
    super.key,
    required this.session,
    this.initialColumns = 80,
    this.initialRows = 24,
    this.autofocus = true,
    this.showToolbar = true,
    this.onError,
    this.onExit,
  });

  final TerminalSessionBinding session;
  final int initialColumns;
  final int initialRows;
  final bool autofocus;
  final bool showToolbar;
  final void Function(Object error)? onError;
  final void Function(int? exitCode)? onExit;

  @override
  State<RemVibeTerminalWidget> createState() => _RemVibeTerminalWidgetState();
}

class _RemVibeTerminalWidgetState extends State<RemVibeTerminalWidget> {
  late final Terminal _terminal = Terminal(
    maxLines: 5000,
    windowsPtyMode: true,
    onOutput: _onTerminalInput,
    onResize: (columns, rows, pixelWidth, pixelHeight) {
      _resize.request(columns: columns, rows: rows);
    },
  );

  late final TerminalResizeCoordinator _resize = TerminalResizeCoordinator(
    initialSize: (
      columns: widget.initialColumns,
      rows: widget.initialRows,
    ),
    applyResize: (size) => widget.session.resize(
      columns: size.columns,
      rows: size.rows,
    ),
    onError: (error, trace) => _reportError(error),
  );

  StreamSubscription<String>? _output;
  Future<void> _inputQueue = Future<void>.value();
  bool _pasting = false;
  bool _cancelPaste = false;
  bool _detached = false;
  String _status = 'Attached';
  int? _lastSequence;
  bool _outputGap = false;

  @override
  void initState() {
    super.initState();
    _subscribeOutput();
    unawaited(_observeExit(widget.session));
  }

  @override
  void didUpdateWidget(covariant RemVibeTerminalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      identical(oldWidget.session, widget.session),
      'Use a new widget key for each terminal attachment.',
    );
  }

  void _subscribeOutput() {
    _output = widget.session.output
        .map((frame) {
          final previous = _lastSequence;
          if (previous != null && frame.sequence <= previous) {
            return <int>[];
          }
          if (previous != null && frame.sequence != previous + 1) {
            _outputGap = true;
            _setStatus('Output sequence gap: reconnect may be required');
          }
          _lastSequence = frame.sequence;
          return frame.bytes;
        })
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen(
          (data) {
            if (!mounted || _detached || data.isEmpty) return;
            _terminal.write(data);
            _resize.reportOutput(
              cursorColumn: _terminal.buffer.cursorX,
              cursorRow: _terminal.buffer.cursorY,
            );
          },
          onError: (Object error, StackTrace trace) => _reportError(error),
        );
  }

  Future<void> _observeExit(TerminalSessionBinding session) async {
    try {
      final code = await session.exitCode;
      if (!mounted || !identical(widget.session, session)) return;
      _setStatus(code == null ? 'Session closed' : 'Exited: $code');
      widget.onExit?.call(code);
    } catch (error) {
      _reportError(error);
    }
  }

  void _setStatus(String value) {
    if (mounted) setState(() => _status = value);
  }

  void _reportError(Object error) {
    if (!mounted || _detached) return;
    _setStatus('Terminal error: $error');
    widget.onError?.call(error);
  }

  void _onTerminalInput(String text) {
    if (_detached || _pasting || text.isEmpty) return;
    final session = widget.session;
    final bytes = utf8.encode(text);
    // Keep async remote input operations in their original keyboard order.
    _inputQueue = _inputQueue.then((_) async {
      if (!mounted || _detached || _pasting) return;
      await session.input(bytes);
    }).catchError((Object error, StackTrace trace) {
      _reportError(error);
    });
  }

  Future<void> _interrupt() async {
    _cancelPaste = true;
    try {
      await widget.session.interrupt();
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> _requestClipboardPaste() async {
    if (_pasting || _detached || !mounted) return;
    _cancelPaste = false;
    setState(() => _pasting = true);
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || _detached) return;
      final text = clip?.text ?? '';
      if (text.isEmpty) {
        _setStatus('Clipboard is empty');
        return;
      }

      final lines = RegExp(r'\r\n|\n|\r').allMatches(text).length + 1;
      final preview = text.length > 420
          ? '${text.substring(0, 420)}…'
          : text;
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Paste into terminal?'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${text.runes.length} characters, $lines line(s). '
                  'Newlines may execute commands.',
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      preview,
                      style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Paste'),
            ),
          ],
        ),
      );

      if (approved != true || !mounted || _detached || _cancelPaste) return;
      await _inputQueue;
      if (!mounted || _detached || _cancelPaste) return;

      _setStatus('Pasting characters...');
      final session = widget.session;
      final count = await sendTerminalClipboardText(
        text: text,
        isSessionCurrent: () => mounted && !_detached && !_cancelPaste,
        send: (character) => session.input(utf8.encode(character)),
      );
      if (mounted && !_detached) {
        _setStatus('Pasted $count characters');
      }
    } catch (error) {
      if (mounted && !_detached) _reportError(error);
    } finally {
      if (mounted) setState(() => _pasting = false);
    }
  }

  @override
  void dispose() {
    _detached = true;
    _cancelPaste = true;
    _resize.dispose();
    final output = _output;
    if (output != null) unawaited(output.cancel());
    unawaited(widget.session.detach());
    _terminal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showToolbar)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.session.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Ctrl+C (interrupt)',
                  onPressed: _interrupt,
                  icon: const Icon(Icons.keyboard_control_key),
                ),
              ],
            ),
          ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ColoredBox(
              color: const Color(0xFF0C1016),
              child: StableScrollbackTerminalView(
                _terminal,
                autofocus: widget.autofocus,
                onPasteRequested: _requestClipboardPaste,
                onInteractionError: _reportError,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: Text(
            _outputGap ? '$_status • incomplete output history' : _status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
