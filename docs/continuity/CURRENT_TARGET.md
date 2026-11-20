# Current target — remvibe_terminal

**TERM-01A — Windows x64 standalone ConPTY [in_progress]**

Last source preparation: 2026-11-20. Local development root: `D:\Projects\remvibe_terminal`.

## Definition of done

- CMake builds a native ConPTY DLL on Windows x64.
- Dart `package:remvibe_terminal/remvibe_terminal.dart` creates real terminal sessions.
- Input, raw output stream, resize, interrupt, natural exit, cancel/close work.
- Two terminals run independently and process/job resources are released.
- Real PowerShell smoke and native CTest PASS on a Windows machine.

## Evidence status

- Frozen original sources reviewed at legacy main `be22cf19bf8310fc84c669dd2e9cf766c8b9d43d`.
- Independent source candidate constructed; Windows build, Dart analyze/test and live smoke **not executed here** (no Windows or Dart SDK).
- No repository commit, push, PR, merge, service or deployment action performed in this source-authoring environment.
- Do not mark accepted until real Windows test output is reviewed.

Next action: unpack files into target checkout without overwriting unreviewed local edits, run Windows native + Dart acceptance commands, inspect results, fix any real failures.
