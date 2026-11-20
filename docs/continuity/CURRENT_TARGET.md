# Current target — remvibe_terminal

**TERM-01B — Flutter Windows interactive example [in_progress; no product acceptance]**

Local checkout: `D:\Projects\remvibe_terminal`.

## Delivery

- Preserve existing native ConPTY behavior and Dart FFI public session methods.
- Replace the Windows-specific Dart engine field with a small internal backend
  interface, without implementing Linux/macOS prematurely.
- Windows library path defaults to the DLL beside the caller executable;
  Client bundle integration is a later consumer responsibility.
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
- First operator Windows Debug attempt: native DLL Debug build PASS;
  Flutter project creation/dependency resolution PASS; Flutter analyzer FAILED
  on duplicate `_` callback parameters and missing `flutter_lints` package.
- Both source issues are fixed in this branch; Flutter analyzer rerun, Debug
  executable build, interactive terminal use and operator review are pending.
- No Fleet/Networking integration, service mutation, release, merge or cleanup.

Next step: launch `tool/run_flutter_example_debug.ps1` from a Windows PowerShell,
fix any observed compile/runtime/interaction failures, then review the
working Flutter terminal before any acceptance decision.

## Active correction: selection and resize (2026-11-20)

- Operator ran the Flutter Windows Debug example successfully and observed a
  working interactive PowerShell view. This does not close the checkpoint.
- Long drag selection in xterm2 5.5.0 shifted its origin as the scrollback
  viewport advanced, limiting selection to roughly visible rows. A small
  example-only stable-buffer-anchor selection controller was implemented.
- The old direct `onResize -> native resize` call was replaced in the example
  with a latest-wins coordinator. During an active settling cycle the newest
  requested size is **retained**, not ignored, and is applied after settling.
- Settling is inferred from no output/cursor movement for 250 ms, bounded by
  1 s under sustained output. Input continues and output is never blocked.
  This is a heuristic, not an OS redraw-completion acknowledgement.
- Added deterministic timer tests for multiple pending resize requests,
  continuous output and no-op identical size.
- Feature source committed to GitHub; Flutter analyze/tests, Debug build and
  user observation of the corrected selection and resize are **pending**.
- Keep original ConPTY engine, native ABI and existing headless smoke unchanged.
- No acceptance, PR merge, deployment, SCM edits or legacy repo writes.

Next: run `tool/run_flutter_example_debug.ps1` on Windows, then drag-select
from hundreds of rows above the viewport down through the end of output.
Repeat fast window resize during idle prompt and long-running output.
