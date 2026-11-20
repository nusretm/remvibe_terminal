# remvibe_terminal

Independent Dart + native Windows ConPTY terminal. **Standalone Windows ConPTY smoke: PASS; interactive Flutter example (TERM-01B) is in progress, not product-accepted.**

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

## Standalone smoke evidence

`native/tests/...` checks two real PowerShell sessions using CTest. `example/windows_terminal_smoke.dart` checks Dart FFI, `Get-Location`, `Get-Process`, same-session input, resize, two independent sessions, natural exit, cancellation, and process disappearance. **The operator ran MSVC Release, native CTest 1/1, Dart tests 2/2, analyzer and real headless PowerShell smoke successfully on Windows.** These technical results do not constitute product acceptance. The Flutter example still requires an actual Debug build and interactive use.

See `docs/continuity/TERM_01_WINDOWS_CONPTY.md`.
