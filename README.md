# remvibe_terminal

Independent Dart + native Windows ConPTY terminal. **TERM-01A Windows x64 local runtime acceptance: PASS (2026-11-20; operator-provided evidence).**

- Real interactive PowerShell/CMD/ConPTY sessions (Windows 10 1809+).
- Raw output stream (`Uint8List`), UTF-8/ANSI/VT interpretation belongs to the caller.
- Input, resize, Ctrl+C, natural exit code, cancel/close and multiple sessions.
- Native Win32 job cleanup. No Flutter, RemVibe Networking, Fleet or Update Center dependency.
- Linux/macOS PTY and normal non-PTY process modes **not yet implemented**.

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

Future<void> run(String dllPath) async {
  final engine = RemVibeTerminal.windows(libraryPath: dllPath);
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

The DLL is currently an explicit deployment input (`libraryPath`); automatic asset packaging is deliberately deferred until a real consumer requires it.

## Acceptance gate

`native/tests/...` checks two real PowerShell sessions using CTest. `example/windows_terminal_smoke.dart` checks Dart FFI, `Get-Location`, `Get-Process`, same-session input, resize, two independent sessions, natural exit, cancellation, and process disappearance. **Windows x64 local acceptance (2026-11-20): PASS.** MSVC Release build, CTest 1/1, analyzer, Dart tests 2/2 and real PowerShell FFI smoke passed. Smoke confirmed `Get-Location`, `Get-Process`, resize, independent sessions, first close/second survives, natural exit 0, cancel and cleanup. This evidence is the operator's real Windows output, not GitHub CI.

See `docs/continuity/TERM_01_WINDOWS_CONPTY.md`.
