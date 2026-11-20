import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:remvibe_terminal/remvibe_terminal.dart';

import 'local_terminal_session_provider.dart';
import 'terminal_widget/remvibe_terminal_widget.dart';
import 'terminal_widget/terminal_session_api.dart';

void main() => runApp(const RemVibeTerminalExample());

class RemVibeTerminalExample extends StatelessWidget {
  const RemVibeTerminalExample({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RemVibe Terminal Example',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const TerminalDemoScreen(),
      );
}

class TerminalDemoScreen extends StatefulWidget {
  const TerminalDemoScreen({super.key});

  @override
  State<TerminalDemoScreen> createState() => _TerminalDemoScreenState();
}

class _TerminalDemoScreenState extends State<TerminalDemoScreen> {
  RemVibeTerminal? _engine;
  TerminalSessionPool? _pool;
  LocalTerminalSessionProvider? _provider;
  TerminalSessionBinding? _active;
  List<TerminalSessionDescriptor> _sessions = [];
  Timer? _refreshTimer;
  bool _busy = false;
  int _attachmentSerial = 0;
  String _profile = 'PowerShell';
  String _notice = 'Starting local session host...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initialize());
    });
  }

  String _dllPath() {
    const explicit = String.fromEnvironment('RVTERM_DLL_PATH');
    final inherited = Platform.environment['REMVIBE_TERMINAL_FFI_LIB'];
    final options = <String>[
      if (explicit.isNotEmpty) explicit,
      if (inherited != null && inherited.isNotEmpty) inherited,
      '../build/windows/Debug/remvibe_terminal_windows.dll',
      '../build/windows/Release/remvibe_terminal_windows.dll',
      'build/windows/Debug/remvibe_terminal_windows.dll',
      'build/windows/Release/remvibe_terminal_windows.dll',
    ];
    for (final option in options) {
      if (File(option).existsSync()) return File(option).absolute.path;
    }
    throw FileSystemException(
      'ConPTY DLL not found. Run tool/run_flutter_example_debug.ps1.',
    );
  }

  Future<void> _initialize() async {
    if (!Platform.isWindows) {
      setState(() => _notice = 'Windows x64 only');
      return;
    }
    try {
      final engine = RemVibeTerminal.windows(libraryPath: _dllPath());
      final pool = TerminalSessionPool.withEngine(
        engine: engine,
        maximumSessions: 4,
        maximumReplayBytes: 64 * 1024,
        detachedIdleTimeout: const Duration(minutes: 10),
      );
      if (!mounted) {
        await pool.close();
        await engine.close();
        return;
      }
      _engine = engine;
      _pool = pool;
      _provider = LocalTerminalSessionProvider(pool);
      _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        unawaited(_refresh());
      });
      await _run(_createTerminal);
    } catch (error) {
      if (mounted) setState(() => _notice = 'Startup error: $error');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _provider == null) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _notice = 'Operation failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createTerminal() async {
    final provider = _provider!;
    await _detachActive();
    final binding = await provider.create(
      profile: _profile,
      columns: 100,
      rows: 30,
    );
    if (!mounted) {
      await binding.detach();
      return;
    }
    setState(() {
      _active = binding;
      _attachmentSerial++;
      _notice = 'Created: ${binding.sessionId}';
    });
    await _refresh();
  }

  Future<void> _attachTerminal(String sessionId) async {
    final current = _active;
    if (current != null && current.sessionId == sessionId) return;
    final provider = _provider!;
    await _detachActive();
    final binding = await provider.attach(sessionId);
    if (!mounted) {
      await binding.detach();
      return;
    }
    setState(() {
      _active = binding;
      _attachmentSerial++;
      _notice = 'Reattached: ${binding.sessionId}';
    });
    await _refresh();
  }

  Future<void> _detachActive() async {
    final binding = _active;
    if (binding == null) return;
    if (mounted) setState(() => _active = null);
    await binding.detach();
    await _refresh();
  }

  Future<void> _terminateActive() async {
    final binding = _active;
    if (binding == null) return;
    final id = binding.sessionId;
    if (mounted) setState(() => _active = null);
    await _provider!.terminate(id);
    if (mounted) setState(() => _notice = 'Terminated: $id');
    await _refresh();
  }

  Future<void> _refresh() async {
    final provider = _provider;
    if (provider == null || !mounted) return;
    final list = await provider.listSessions();
    if (!mounted) return;
    final active = _active;
    setState(() {
      _sessions = list;
      if (active != null && !list.any((s) => s.sessionId == active.sessionId)) {
        _active = null;
        _notice = 'Terminal process exited or expired.';
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    final binding = _active;
    if (binding != null) unawaited(binding.detach());
    final pool = _pool;
    final engine = _engine;
    if (pool != null) {
      unawaited(_closeResources(pool, engine));
    } else if (engine != null) {
      unawaited(engine.close());
    }
    super.dispose();
  }

  Future<void> _closeResources(
    TerminalSessionPool pool,
    RemVibeTerminal? engine,
  ) async {
    await pool.close();
    await engine?.close();
  }

  @override
  Widget build(BuildContext context) {
    final binding = _active;
    return Scaffold(
      backgroundColor: const Color(0xFF111720),
      appBar: AppBar(
        title: const Text('RemVibe Terminal · Multiple Sessions'),
        backgroundColor: const Color(0xFF192330),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                DropdownButton<String>(
                  value: _profile,
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _profile = value);
                          }
                        },
                  items: const [
                    DropdownMenuItem(
                      value: 'PowerShell',
                      child: Text('PowerShell'),
                    ),
                    DropdownMenuItem(value: 'CMD', child: Text('CMD')),
                  ],
                ),
                FilledButton.icon(
                  onPressed: _busy || _provider == null
                      ? null
                      : () => unawaited(_run(_createTerminal)),
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                ),
                PopupMenuButton<String>(
                  enabled: !_busy && _sessions.isNotEmpty,
                  tooltip: 'Attach an existing terminal',
                  onSelected: (id) =>
                      unawaited(_run(() => _attachTerminal(id))),
                  itemBuilder: (_) => [
                    for (final entry in _sessions)
                      PopupMenuItem(
                        value: entry.sessionId,
                        enabled: entry.reattachable ||
                            binding?.sessionId == entry.sessionId,
                        child: Text(
                          '${entry.label} • ${entry.sessionId.substring(0, 8)}'
                          ' • ${entry.attached ? 'attached' : 'detached'}',
                        ),
                      ),
                  ],
                  child: const Chip(
                    avatar: Icon(Icons.list_alt),
                    label: Text('Sessions'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: binding == null || _busy
                      ? null
                      : () => unawaited(_run(_detachActive)),
                  icon: const Icon(Icons.link_off),
                  label: const Text('Detach'),
                ),
                OutlinedButton.icon(
                  onPressed: binding == null || _busy
                      ? null
                      : () => unawaited(_run(_terminateActive)),
                  icon: const Icon(Icons.close),
                  label: const Text('Terminate'),
                ),
                Text('Live sessions: ${_sessions.length}'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Text(
              _notice,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: binding == null
                ? const Center(
                    child: Text(
                      'No terminal attached. Create a terminal or choose an '
                      'existing session from Sessions.',
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: RemVibeTerminalWidget(
                      key: ValueKey(_attachmentSerial),
                      session: binding,
                      initialColumns: 100,
                      initialRows: 30,
                      onExit: (_) => unawaited(_refresh()),
                      onError: (error) {
                        if (mounted) {
                          setState(() => _notice = 'Terminal error: $error');
                        }
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
