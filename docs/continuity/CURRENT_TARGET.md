# Current target — remvibe_terminal

**TERM-01B — Flutter Windows interactive example [in_progress; no product acceptance]**

Local checkout: `D:\Projects\remvibe_terminal`.

## Delivery

- Retain native ConPTY and public Dart FFI package unchanged.
- Preserve existing `example/windows_terminal_smoke.dart`.
- Make `example/` itself a Flutter Windows app using `xterm2` for rendering.
- Connect actual keyboard input, UTF-8/ANSI/VT output, terminal resize,
  PowerShell/CMD selection, Ctrl+C, exit and resource cleanup.
- Supply `tool/run_flutter_example_debug.ps1` to build native Debug DLL,
  generate Flutter Windows runner in the same example project and start Debug.

## Evidence/status

- Baseline `main`: `5d7359a025ad3b24346c95b290bea439789522d0`.
- Previous operator Windows headless tests: MSVC Release PASS, CTest 1/1 PASS,
  Dart analyzer PASS, Dart tests 2/2 PASS and real PowerShell smoke PASS.
- These are standalone technical checks, not actual product acceptance.
- **Flutter Debug build, interactive terminal use and visual/operator review are pending.**
- No Fleet/Networking integration, service mutation, release, merge or cleanup.

Next step: launch `tool/run_flutter_example_debug.ps1` from a Windows PowerShell,
fix any observed compile/runtime/interaction failures, then review the
working Flutter terminal before any acceptance decision.
