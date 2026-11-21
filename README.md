# remvibe_terminal

**Responsibility boundary:** this is a local terminal library, NOT a
networking/remote terminal or Update Center product. Read
[PROJECT_RESPONSIBILITIES](docs/continuity/PROJECT_RESPONSIBILITIES.md)
before proposing scope changes. New responsibilities require an explicit
written plan, correct package/repository owner, and operator approval
**before** implementation. CI results or design discussion do not authorize
scope expansion, merge, release or deployment.

**TERM-01G-B implemented and Windows-accepted:** transport-neutral
`TerminalHandler`/`TerminalHandlerLocal`, per-PTY independent subscriptions,
typed state/output events, bounded replay and detached session ownership.
The independent `remvibe_terminal_flutter` package has operator-accepted
Windows ConPTY and Ubuntu UI-mock viewer behavior. Consumer-specific
`TerminalHandlerRemote` belongs ONLY to `remvibe_update_center`.

Independent Dart native PTY terminal (Dart 3.10+ / Native Assets): **Windows ConPTY accepted**. **TERM-02A real Linux openpty/Bash backend and isolated native child supervisor implemented on `feature/term-02a-linux-pty`; direct Linux C++ smoke PASS, but final Ubuntu Dart/Flutter acceptance remains PENDING.** See [TERM-02A](docs/continuity/TERM_02A_LINUX_PTY.md).

- Real interactive PowerShell/CMD/ConPTY sessions (Windows 10 1809+).
- Raw output stream (`Uint8List`), UTF-8/ANSI/VT interpretation belongs to the caller.
- Input, resize, Ctrl+C, natural exit code, cancel/close and multiple sessions.
- Native Win32 job cleanup. No Flutter, RemVibe Networking, Fleet or Update Center dependency.
- Linux PTY source uses openpty, supervised real Bash/sh (to avoid Dart SIGCHLD child-reaping races), native resize, Ctrl+C, output and true exit status. Dart Native Assets/Ubuntu GUI acceptance is pending; macOS remains unimplemented.


## TERM-02A Linux (feature branch only, live Ubuntu verification pending)

On the **single existing core checkout**, use branch
`feature/term-02a-linux-pty` and run:

```bash
bash tool/verify_linux.sh
```

The gate includes `dart pub get`, analyzer, all Dart tests and a **real**
native Linux Bash PTY multi-handler smoke. `RemVibeTerminal.currentPlatform()`
selects Windows ConPTY or Linux forkpty automatically. No native backend
is available yet on macOS. The Flutter Linux real-shell integration is in
`remvibe_terminal_flutter` branch `feature/term-02b-flutter-linux-real-pty`.
Do not use the old Ubuntu UI-mock demo as proof of native Linux PTY.

## Build (Windows x64, MSVC and Dart SDK installed)

From the independent local repository at `D:\Projects\remvibe_terminal`:

```powershell
cmake -S . -B build\windows -G "Visual Studio 17 2022" -A x64 -DRVTERM_BUILD_TESTS=ON
cmake --build build\windows --config Release
ctest --test-dir build\windows -C Release --output-on-failure
dart pub get
dart analyze --fatal-infos
dart test
$library = (Resolve-Path .\build\windows\Release\remvibe_terminal_windows.dll).Path
dart run example\windows_terminal_smoke.dart --dll "$library"
```

If a different Visual Studio generator is installed, replace `Visual Studio 17 2022` accordingly. CMake builds only this package; no services are installed or modified.

## Dart API

```dart
import 'dart:convert';
import 'dart:io';
import 'package:remvibe_terminal/remvibe_terminal.dart';

Future<void> run() async {
  // In dart build cli, the DLL is loaded through its bundled code-asset ID.
  final engine = RemVibeTerminal.currentPlatform();
  final session = engine.create(
    commandLine: 'powershell.exe -NoLogo -NoProfile',
    columns: 100,
    rows: 30,
  );
  final output = session.output.listen((bytes) => stdout.add(bytes));
  try {
    session.write(utf8.encode('Get-Location\r'));
    session.write(utf8.encode('Get-Process -Id \$PID\r'));
    session.resize(columns: 120, rows: 40);
    session.write(utf8.encode('exit\r'));
    final code = await session.exitCode;
    stdout.writeln('Exit code: $code');
  } finally {
    await output.cancel();
    await session.close();
    await engine.close();
  }
}
```

`output` is a broadcast stream of **raw bytes**: subscribe immediately after `create` to avoid missing initial output. `exitCode` is `Future<int?>`: natural exit returns the process code; an explicit `cancel()`/`close()` returns `null`. `interrupt()` writes Ctrl+C without closing. `cancel()` force-stops the job and is equivalent to `close()` in TERM-01A. Both `close()` operations are idempotent.

Unexpected output-poll failures surface via stream errors and `session.failure`; `exitCode` returns `null` in that case. A consumer should handle stream `onError` and treat non-null `failure` as a failed session.

Native output is capped per session at `maximumBufferBytes` (default 256 KiB). Overflow stops that session. Input/output processing is local; this library deliberately has no transport, access-control or UI functionality. A terminal runs under the caller process account. Treat command execution as an application authorization decision, not as a capability granted by this package.

## Dart Native Assets packaging (TERM-01E)

Consumers use Dart 3.10+ and add remvibe_terminal to their pubspec. On
Windows x64, hook/build.dart compiles the same native C++ ConPTY source as
CMake using MSVC and registers its DLL as a bundled code asset. A caller uses
RemVibeTerminal.currentPlatform() or RemVibeTerminal.windows() without a
libraryPath. The compiled CLI bundle has this form:

    bundle/
      bin/
        my_client.exe
      lib/
        remvibe_terminal_windows.dll

There is no manual DLL copying and no dependency on the current working
directory or executable-adjacent paths. The hook uses @Native with the asset
ID package:remvibe_terminal/src/windows/windows_conpty.dart. The explicit
libraryPath override remains available for legacy native smoke/Debug tools.

### Native DLL resolution in different installation layouts

The public factories now accept an ordered set of DLL candidates, following
the flexible search-directory approach used by RemVibe Networking:

```dart
final engine = RemVibeTerminal.currentPlatform(
  libraryPath: r'C:\custom\remvibe_terminal_windows.dll',
  libraryPaths: [
    r'D:\portable\bin\remvibe_terminal_windows.dll',
    r'D:\portable\lib\remvibe_terminal_windows.dll',
  ],
  searchDirectories: [
    r'C:\Program Files\RemVibe\Client\lib',
    r'D:\development\remvibe_terminal\build\windows\Debug',
  ],
);
```

The lookup order is exactly: optional single `libraryPath`, each
`libraryPaths` file in order, and `remvibe_terminal_windows.dll` inside
each `searchDirectories` directory in order. Duplicates are ignored.
Missing files, unloadable DLLs and DLLs missing required exports allow
searching later candidates. When all manually supplied candidates fail,
`TerminalNativeLibraryLoadException` includes the full attempted path list
and per-path failures. There is no hidden fallback to a different DLL.

**Without any manual candidates, the automatic Native Asset path remains the
default**, as in the successful Windows CLI bundle test. No search path or
DLL copy is needed for normal `dart build cli` deployment.

DynamicLibrary.codeAsset is deliberately avoided because Dart/Flutter SDK
availability differs; @Native provides the cross-runner compatibility path.

Native build prerequisites: Windows x64, an installed Visual Studio MSVC C++
compiler/Windows SDK, and Dart 3.10+. Windows is currently the only PTY
platform implementation. The hook emits no native code asset on Linux/macOS
because those adapters do not exist. Dart CI can still analyze/test the
platform-independent session API.

To verify real automatic packaging on Windows:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\\tool\\verify_native_assets_cli.ps1

This test creates an isolated, ignored build/native_assets_cli_consumer
Dart project, adds remvibe_terminal as a path dependency, invokes dart build
cli, verifies the DLL is under bundle/lib, and runs real PowerShell/ConPTY
commands in three modes: automatic Native Assets, ordered explicit paths
(including a broken DLL), and multiple search directories.

**Operator Windows evidence:** the original Native Assets build and
ConPTY CLI command passed. The new multi-path tests remain unverified and
need a Windows rerun before TERM-01E is fully accepted.
No Update Center Client release or SCM service is changed by this script.



## Multiple sessions and reusable Console widget (TERM-01D)

The native/Dart package now exposes a Flutter-free TerminalSessionService:

- Create independent PTYs with optional Server-issued session IDs.
- List active sessions, detach without terminating, and attach again.
- Retain bounded sequenced output (64 KiB default), with truncation signaling.
- Limit to four concurrent sessions by default.
- Expire detached IDLE shells after 10 minutes; UNKNOWN after 30 minutes,
  while externally marked RUNNING commands are exempt. The Server must
  supply command-activity state for real remote sessions.
- Natural process exit, explicit terminate and Client shutdown close resources.

The Client initializes `TerminalSessionService.withEngine(engine: ...)`
once and calls `TerminalSessionService.register(service)`. Thereafter,
`TerminalSessionService().items` returns a fresh immutable session list,
`TerminalSessionService().newTerminal(commandLine: ...)` creates a PTY and
`itemsChanged` broadcasts lifecycle updates. Only one service is registered
per isolate, but tests can create independent `.withFactory` instances.
A pre-registration `TerminalSessionService()` access throws an explicit
`StateError`. The xterm display belongs to each Flutter widget, not to the
native session service. See
`docs/continuity/TERM_01F_SESSION_SERVICE.md` for lifecycle and remote limits.

The example/ directory includes an actual reusable Flutter widget under
example/lib/terminal_widget/. Its only integration contract is
TerminalSessionBinding/TerminalSessionProvider, which can be implemented by
the Update Center Console's existing remote transport. Neither the widget
nor Console requires the ConPTY DLL. Copy the five files in that folder,
**not** the example-only local provider.

The example GUI exercises multiple sessions through a local provider:
New, Sessions (re-attach), Detach, Terminate, plus the already validated
scrollback selection, right-click copy/paste, cursor handling and resize.
Real Windows verification of TERM-01D is still pending.

See docs/continuity/TERM_01D_WIDGET_SESSION_POOL.md. The transport adapter,
real Client/Server/Console routing and application authorization are **not**
implemented here. Existing session IDs are NOT authorization tokens.

## Interactive Flutter Windows Debug example

The example lives directly at `example/` (no nested Flutter project), and
keeps `example/windows_terminal_smoke.dart` for separate native smoke testing.
Flutter and xterm2 are **example dependencies only**.

Run this from an ordinary Windows PowerShell:

```powershell
Set-Location D:\Projects\remvibe_terminal
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run_flutter_example_debug.ps1
```

The script builds the native Debug DLL, generates the Flutter Windows runner
under `example/windows` if missing, analyzes the Flutter sample, and launches
the interactive Windows Debug application. See `example/README.md`.

**This feature has not yet been built or visually tried on Windows. No product
acceptance is claimed.**

## Platform boundary and native distribution

The Dart engine now depends on the internal `TerminalBackend` /
`TerminalHandle` contract rather than `WindowsConPtyLibrary` directly.
`RemVibeTerminal.currentPlatform()` selects the OS implementation; only the
Windows ConPTY adapter exists today, so Linux/macOS throw `UnsupportedError`
rather than pretending to work. Consumers use the same session API when
additional platform adapters are implemented.

Windows requires a native DLL at runtime because ConPTY uses native Win32 APIs.
For a future Windows Update Center Client deployment, include
`remvibe_terminal_windows.dll` **next to the Client executable** in its
application bundle, not inside source files and not as a separate OS install.
Then `RemVibeTerminal.currentPlatform()` loads it automatically from that
directory. During Flutter Debug or local smoke you may override the location
with `libraryPath:`. The Client's actual packaging/copy automation is **not
implemented in this repository yet**; merely adding the Dart dependency does
not embed a DLL into the Client binary. Linux/macOS will eventually need their
own native PTY implementations and native artifacts, not a Windows DLL.

## Standalone smoke evidence

`native/tests/...` checks two real PowerShell sessions using CTest. `example/windows_terminal_smoke.dart` checks Dart FFI, `Get-Location`, `Get-Process`, same-session input, resize, two independent sessions, natural exit, cancellation, and process disappearance. **The operator ran MSVC Release, native CTest 1/1, Dart tests 2/2, analyzer and real headless PowerShell smoke successfully on Windows.** These technical results do not constitute product acceptance. The Flutter example still requires an actual Debug build and interactive use.

See `docs/continuity/TERM_01_WINDOWS_CONPTY.md`.

## Local independent subscribers (TERM-01G-B feature branch)

The package exports a transport-free `TerminalHandler` interface and a
`TerminalHandlerLocal` over the existing locally hosted PTY. Observation
never claims keyboard control or creates another OS process.

```dart
// Assuming TerminalSessionService was explicitly registered at startup.
final controllingAttachment = TerminalSessionService().newTerminal(
  commandLine: 'powershell.exe -NoLogo -NoProfile',
);
final terminal = TerminalSessionService.getTerminal(
  controllingAttachment.sessionId,
)!;
final viewer = TerminalHandlerLocal(terminal: terminal); // Read-only.
final controller = TerminalHandlerLocal(
  terminal: terminal,
  controller: controllingAttachment,
);
final registration = viewer.registerHandler(
  onTerminalState: (source, state) {
    // Typed created/attached/detached/activity/exit/expiry events.
  },
  onTerminalStream: (source, frame) {
    if (frame.isGap) {
      // Missing inclusive sequence range: inspect gapFrom/ToSequence.
    } else {
      // Ordered PTY bytes: frame.bytes / frame.sequence.
    }
  },
);

await controller.input([65]);
await viewer.unregisterHandler(registration); // Does not kill the PTY.
await controller.detach(); // Releases keyboard control only.
```

For actual dual-PTY verification on Windows, run
`tool/run_flutter_example_debug.ps1`; it builds ConPTY Debug, runs the
root Dart tests and the live TERM-01G multi-handler smoke before Flutter.
These checks have not yet been executed for this branch.

The native output reader continues while no viewer is selected. State
`busy/idle/unknown` is independent of controller attachment and is not
deduced from output silence. Local implementation and tests are committed
on `feature/term-01g-local-multi-handler`, but Windows validation and
operator acceptance are still required. `TerminalHandlerRemote` and
cross-device delivery are not implemented here.
