import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remvibe_terminal/remvibe_terminal.dart';
import 'package:xterm2/xterm.dart';

import 'stable_scrollback_terminal_view.dart';
import 'terminal_clipboard_paste.dart';
import 'terminal_resize_coordinator.dart';

void main() => runApp(const RemVibeTerminalExample());

class RemVibeTerminalExample extends StatelessWidget {
  const RemVibeTerminalExample({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RemVibe Terminal Example',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const TerminalScreen(),
      );
}

enum _Shell {
  powershell('PowerShell', 'powershell.exe -NoLogo -NoProfile'),
  cmd('CMD', 'cmd.exe');

  const _Shell(this.label, this.commandLine);
  final String label;
  final String commandLine;
}

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final Terminal _terminal = Terminal(
    maxLines: 5000,
    windowsPtyMode: true,
    onOutput: _onInput,
    onResize: (columns, rows, pixelWidth, pixelHeight) =>
        _resize(columns, rows),
  );
  RemVibeTerminal? _engine;
  RemVibeTerminalSession? _session;
  StreamSubscription<String>? _outputSubscription;
  TerminalResizeCoordinator? _resizeCoordinator;
  _Shell _shell = _Shell.powershell;
  bool _busy = false;
  bool _pasteWorkflowActive = false;
  bool _cancelPaste = false;
  String _status = 'Starting...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_changeSession());
    });
  }

  String _dllPath() {
    const configured = String.fromEnvironment('RVTERM_DLL_PATH');
    final environment = Platform.environment['REMVIBE_TERMINAL_FFI_LIB'];
    final candidates = <String>[
      if (configured.isNotEmpty) configured,
      if (environment != null && environment.isNotEmpty) environment,
      '../build/windows/Debug/remvibe_terminal_windows.dll',
      '../build/windows/Release/remvibe_terminal_windows.dll',
      'build/windows/Debug/remvibe_terminal_windows.dll',
      'build/windows/Release/remvibe_terminal_windows.dll',
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) return file.absolute.path;
    }
    throw FileSystemException(
      'ConPTY DLL not found. Run tool/run_flutter_example_debug.ps1 '
      'or provide --dart-define=RVTERM_DLL_PATH=<full DLL path>.',
    );
  }

  Future<void> _changeSession({bool start = true}) async {
    if (_busy) return;
    // In-flight paste loops must stop before the child process is replaced.
    _cancelPaste = true;
    setState(() => _busy = true);
    final oldSession = _session;
    final oldSubscription = _outputSubscription;
    _resizeCoordinator?.dispose();
    _resizeCoordinator = null;
    _session = null;
    _outputSubscription = null;
    try {
      await oldSubscription?.cancel();
      await oldSession?.close();
      if (!start) {
        if (mounted) setState(() => _status = 'Stopped');
        return;
      }
      if (!Platform.isWindows) {
        throw UnsupportedError('This example requires Windows x64.');
      }
      _engine ??= RemVibeTerminal.windows(libraryPath: _dllPath());

      final columns = _terminal.viewWidth.clamp(1, 32767).toInt();
      final rows = _terminal.viewHeight.clamp(1, 32767).toInt();
      final session = _engine!.create(
        commandLine: _shell.commandLine,
        columns: columns,
        rows: rows,
      );
      if (!mounted) {
        await session.close();
        return;
      }
      _session = session;
      _resizeCoordinator = TerminalResizeCoordinator(
        initialSize: (columns: columns, rows: rows),
        applyResize: (size) {
          if (!session.isClosed) {
            session.resize(columns: size.columns, rows: size.rows);
          }
        },
        onError: (error, stackTrace) {
          if (mounted && identical(_session, session)) {
            setState(() => _status = 'Resize error: $error');
          }
        },
      );
      _terminal.write('\x1b[2J\x1b[H');
      // Decode native PTY frames incrementally and preserve ANSI/VT sequences.
      _outputSubscription = session.output
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen(
            (text) {
              if (!identical(_session, session)) return;
              _terminal.write(text);
              _resizeCoordinator?.reportOutput(
                cursorColumn: _terminal.buffer.cursorX,
                cursorRow: _terminal.buffer.cursorY,
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              if (mounted && identical(_session, session)) {
                setState(() => _status = 'Output error: $error');
              }
            },
          );
      unawaited(_watchExit(session));
      if (mounted) {
        setState(() => _status = '${_shell.label} running · PID ${session.processId}');
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'Start error: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _watchExit(RemVibeTerminalSession session) async {
    final code = await session.exitCode;
    if (!mounted || !identical(_session, session)) return;
    _resizeCoordinator?.dispose();
    _resizeCoordinator = null;
    setState(() {
      _session = null;
      _status = code == null ? 'Terminal closed' : 'Process exited · code $code';
    });
  }

  Future<void> _confirmClipboardPaste() async {
    if (_pasteWorkflowActive || _busy) return;
    final session = _session;
    if (session == null || session.isClosed) {
      if (mounted) setState(() => _status = 'Open a terminal before pasting.');
      return;
    }

    _cancelPaste = false;
    setState(() => _pasteWorkflowActive = true);
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || !identical(_session, session) || session.isClosed) return;
      final text = clipboard?.text ?? '';
      if (text.isEmpty) {
        setState(() => _status = 'Clipboard contains no text.');
        return;
      }

      final lines = RegExp(r'\r\n|\r|\n').allMatches(text).length + 1;
      final preview = text.length > 420
          ? '${text.substring(0, 420)}…'
          : text;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Paste into terminal?'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${text.runes.length} characters, $lines line(s). '
                    'Pasted line breaks will act as Enter and may execute commands.'),
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
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Paste'),
            ),
          ],
        ),
      );
      if (confirmed != true ||
          !mounted ||
          !identical(_session, session) ||
          session.isClosed) {
        return;
      }

      setState(() => _status = 'Pasting characters one at a time…');
      final sent = await sendTerminalClipboardText(
        text: text,
        isSessionCurrent: () => mounted &&
            !_cancelPaste &&
            identical(_session, session) &&
            !session.isClosed,
        send: (character) => session.write(utf8.encode(character)),
      );
      if (mounted && identical(_session, session)) {
        setState(() => _status = 'Pasted $sent characters.');
      }
    } catch (error) {
      if (mounted && identical(_session, session)) {
        setState(() => _status = 'Paste error or cancelled: $error');
      }
    } finally {
      if (mounted) setState(() => _pasteWorkflowActive = false);
    }
  }

  void _onInput(String text) {
    final session = _session;
    if (session == null || session.isClosed || text.isEmpty ||
        _pasteWorkflowActive) {
      // Do not interleave keyboard input with a confirmed multiline paste.
      return;
    }
    try {
      session.write(utf8.encode(text));
    } catch (error) {
      if (mounted) setState(() => _status = 'Input error: $error');
    }
  }

  void _resize(int columns, int rows) {
    final session = _session;
    if (session == null || session.isClosed) return;
    // Latest requested size is retained while the prior resize is settling.
    _resizeCoordinator?.request(columns: columns, rows: rows);
  }

  void _interrupt() {
    _cancelPaste = true;
    final session = _session;
    if (session == null || session.isClosed) return;
    try {
      session.interrupt();
    } catch (error) {
      if (mounted) setState(() => _status = 'Interrupt error: $error');
    }
  }

  @override
  void dispose() {
    _cancelPaste = true;
    _resizeCoordinator?.dispose();
    _resizeCoordinator = null;
    final subscription = _outputSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    final engine = _engine;
    if (engine != null) unawaited(engine.close());
    _terminal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _session != null && !_session!.isClosed;
    return Scaffold(
      backgroundColor: const Color(0xFF111720),
      appBar: AppBar(
        title: const Text('RemVibe Terminal · Windows'),
        backgroundColor: const Color(0xFF192330),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                DropdownButton<_Shell>(
                  value: _shell,
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _shell = value);
                          unawaited(_changeSession());
                        },
                  items: [
                    for (final shell in _Shell.values)
                      DropdownMenuItem(
                        value: shell,
                        child: Text(shell.label),
                      ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => unawaited(_changeSession()),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(running ? 'Restart' : 'Start'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || !running ? null : _interrupt,
                  icon: const Icon(Icons.keyboard_control_key),
                  label: const Text('Ctrl+C'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || !running
                      ? null
                      : () => unawaited(_changeSession(start: false)),
                  icon: const Icon(Icons.stop),
                  label: const Text('Close'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              _status,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _status.contains('error')
                    ? Colors.orangeAccent
                    : Colors.white70,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ColoredBox(
                  color: const Color(0xFF0C1016),
                  child: StableScrollbackTerminalView(
                    _terminal,
                    autofocus: true,
                    onPasteRequested: _confirmClipboardPaste,
                    onInteractionError: (error) {
                      if (mounted) {
                        setState(() => _status = 'Clipboard error: $error');
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
