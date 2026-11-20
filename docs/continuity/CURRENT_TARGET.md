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

## Operator observation and TERM-01C (2026-11-20)

- Operator reports the corrected long scrollback selection, resize and cursor
  placement work well in the real Flutter Windows Debug window.
- Latest Debug run: MSVC native Debug DLL PASS; `flutter analyze
  --no-fatal-infos` produced 9 informational CLI `print` lints;
  resize coordinator tests 3/3 PASS; Flutter Windows Debug EXE built and
  started. The terminal connection subsequently ended (`Lost connection to
  device`), with no verified cause in the supplied output.
- Operator requested: right-click with an active selection copies to clipboard,
  clears selection and scrolls to actual cursor; right-click without a
  selection requests confirmation and performs sequential per-character paste
  to preserve multiline PowerShell/CMD behavior.
- Implementation is isolated to `example/lib/`: existing xterm2
  pinned-selection/resize logic retained, callback-based clipboard workflow
  added, and multi-line sender provides UTF-8 character-by-character PTY
  writes with normalized CRLF/LF/CR into one Enter.
- The independent Dart CLI smoke now writes to `stdout.writeln`, avoiding
  Flutter-only `debugPrint`, and Debug launcher restores strict
  `flutter analyze` with focused paste-sender tests.
- Code is pushed to the independent `feature/term-01c-right-click-clipboard`
  branch. No merge, release, SCM modification, legacy edits or product
  acceptance.
- Actual Windows Debug build and user verification of the right-click
  workflow are **pending**. Preserve TERM-01B as `in_progress`.

Next: operator pulls the TERM-01C feature branch, runs the Debug launcher,
and checks long-selection right-click copy/scroll, cancelled paste, Unicode
multiline paste, and paste/session interruption.
