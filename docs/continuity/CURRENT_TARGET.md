# Current target — remvibe_terminal

**TERM-01D — Reusable Flutter widget + detached multi-session host [in_progress; no product acceptance]**

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
- Both initial analyzer source issues were corrected. Subsequent operator
  run: native Debug DLL built, 3 resize tests passed, Flutter Debug EXE built
  and started; operator confirmed long selection, resize and cursor placement
  behaved correctly. These observations are not product acceptance.
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
- Prior fixes were subsequently tried in the real Flutter Debug window;
  operator reports selection, resize and cursor placement working. New
  clipboard interactions still require an actual Windows Debug trial.
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


## Operator acceptance evidence vs new implementation

- Windows operator confirmed the prior TERM-01C terminal's long scrollback
  selection, resize, cursor position, right-click copy and confirmed paste
  behave as expected. In the last supplied Windows run, native Debug DLL
  build PASS, Flutter analyzer clean, seven Flutter tests PASS, and Windows
  Debug EXE build PASS. Output ending with "Lost connection to device" alone
  does not prove a crash; no cause was established.
- These are scoped observable behaviors and technical evidence, NOT full
  product acceptance.

## TERM-01D development

- Added a plain-Dart TerminalSessionPool under lib/src/session. This host
  registry owns actual native sessions independently of Flutter, with
  create/list/attach/detach/terminate, live sequence IDs, bounded replay
  (64 KiB default) and normal exit/cleanup.
- Maximum four local sessions by default. Automatically expire detached IDLE
  sessions after 10 minutes, detached UNKNOWN sessions after 30 minutes;
  RUNNING detached commands are exempt when authoritative application code
  marks activity. It is not inferred from raw output.
- Extracted the known working terminal UI into the portable five-file
  example/lib/terminal_widget/ directory. It accepts a
  TerminalSessionBinding/TerminalSessionProvider interface that a remote
  Update Center Console transport adapter can implement.
- The example local provider uses the new pool and exposes New, Sessions,
  Detach, Reattach and Terminate. Tab closure never calls destructive
  termination. Output is sequenced and reconnect replay is bounded; history
  truncation is signaled, not hidden.
- Retained xterm2 stable selection, copy/paste confirmation, UTF-8 paced input
  and latest-wins ConPTY resize. Remote async resize ACKs are serialized.
- Added host registry tests and async resize test; current Windows Debug
  launcher checks the host tests and existing Flutter tests.
- No actual authenticated Server/Client/Console remote adapter was built.
  Authorization, device ownership, broker session references and network
  reconnect routing stay in Update Center application services. Do not
  confuse local host registry with the existing remote broker.
- Source changes only on feature/term-01d-widget-session-pool. No merge,
  release, native SCM changes, legacy repo edits or acceptance.
- New code has NOT yet been built or exercised on operator Windows; local
  ConPTY / Flutter multi-session verification is the next gate.

## Next verification

Pull feature/term-01d-widget-session-pool and run
tool/run_flutter_example_debug.ps1. Use the GUI to open PowerShell and CMD,
detach/re-attach each, inspect the live Sessions list and retained output,
terminate only one, and verify the other survives. Exercise long selection,
copy/paste, window resize and command exit again. Only after this can the
Console transport adapter be added in the separate Update Center repo.
