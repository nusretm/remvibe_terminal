# TERM-01A — Independent Windows ConPTY

Status: `in_progress` — Windows runtime evidence pending.
Date: 2026-11-20.
Local root: `D:\Projects\remvibe_terminal`.

## Frozen reference and migration

Reference repository: `nusretm/remvibe_update_center`, main SHA `be22cf19bf8310fc84c669dd2e9cf766c8b9d43d` (read only). Closure contract: `docs/continuity/UC_REFERENCE_FREEZE_2026_11_20.md`.

Reused local process engine: `native/include/remvibe_terminal_windows.h`, `native/src/platform/windows/remvibe_terminal_windows.cpp`, and `lib/src/fleet/terminal/windows_conpty.dart`. Process lifecycle/output-drain behavior informed by `lib/src/fleet/terminal/windows_remote_terminal_endpoint.dart` and Fleet recovery documentation.

Excluded: Fleet routing, `remote_terminal_protocol.dart`, `remote_terminal_modules.dart`, authorization/session ownership, Flutter, RemVibe Networking and SCM integration.

Focused new changes: `rvterm_process_id` to inspect cleanup; Win32 dimension bounds; avoid a zero-byte successful write loop; close the child on failed job assignment; use the native `std::thread` handle to cancel reader I/O rather than racing a separate OpenThread handle; fix partial thread-attribute-list initialization cleanup. Existing ConPTY construction, Win32 process creation, reader queue, Job Object, pipe handling and wait behavior are retained.

## Public API

`RemVibeTerminal.windows(libraryPath: ...)`, `.create(commandLine:, columns:, rows:, maximumBufferBytes:)`, `activeSessionCount`, `.close()`.

A `RemVibeTerminalSession` exposes `processId`, `output` (raw byte broadcast stream), `write`, `resize`, `interrupt`, `exitCode` (`Future<int?>`), `cancel`, `close`, `isClosed`, `failure`.

Close/cancel terminate a live child job and dispose native resources; natural exit reports its code after an output drain. `output` is a broadcast stream and must be subscribed early. `interrupt()` only writes ETX. A process without PTY is out of scope for this checkpoint.

## Validation commands

```powershell
Set-Location D:\Projects\remvibe_terminal
cmake -S . -B build\windows -G "Visual Studio 17 2022" -A x64 -DRVTERM_BUILD_TESTS=ON
cmake --build build\windows --config Release
ctest --test-dir build\windows -C Release --output-on-failure
dart pub get
dart analyze --fatal-infos
dart test
$dll = (Resolve-Path .\build\windows\Release\remvibe_terminal_windows.dll).Path
dart run example\windows_terminal_smoke.dart --dll "$dll"
```

Expected real outputs include `TERM-01A Get-Location PASS`, `TERM-01A Get-Process PASS`, `TERM-01A two independent terminals PASS`, `TERM-01A natural exit code=0 PASS`, `TERM-01A cancel and cleanup PASS`, `TERM-01A WINDOWS REAL CONPTY ACCEPTANCE PASS`. The test validates **computed** PowerShell markers, not merely echoed command text.

## Actual evidence (to fill only after execution)

- MSVC/CMake: NOT RUN here.
- CTest: NOT RUN here.
- Dart pub/analyze/test: NOT RUN here.
- Real PowerShell smoke: NOT RUN here.
- Child PID cleanup: NOT RUN here.
- Git commit/push/PR/merge: NOT DONE here.

## Deferred

PTY adapters for Linux/macOS, standard process mode, Flutter terminal rendering, remote transport, publishable DLL distribution and CI/release workflows.
