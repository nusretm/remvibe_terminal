# Current target — remvibe_terminal

**Active: TERM-01G-B — local handler/multi-subscriber CODE COMMITTED; Windows tests and product acceptance PENDING.**

**Binding scope and change-control:** `docs/continuity/PROJECT_RESPONSIBILITIES.md`.
**TERM-01G design and separate acceptance gate:** `docs/continuity/TERM_01G_MULTI_HANDLER_CONTRACT.md`.
`remvibe_terminal` owns only independent local terminal capability, its
session/handler contracts and terminal-specific native build. It does NOT
own `TerminalHandlerRemote`, Networking, Fleet, Server/Client/Console
routing, permissions, cross-device delivery, notifications, SCM services
or app installation/update logic. These belong to consuming projects.
**Do not implement an out-of-scope responsibility without a written plan
and explicit operator acceptance of the proposed scope and correct owner.**
Design discussion is not implementation permission; verification is not
merge/release/deploy permission.

### Current source and verification (as of 2026-11-21)

**Current feature branch:** `feature/term-01g-local-multi-handler`, branched
from approved TERM-01F head `abb8886797cbce2102b86a378867b40777c16eb2`.
TERM-01G-A's API and backpressure contract is frozen in
`TERM_01G_MULTI_HANDLER_CONTRACT.md`; TERM-01G-B's new source, test
coverage and unverified Windows gate are recorded in
`TERM_01G_B_IMPLEMENTATION.md`. New implementation exists on this
feature branch but has NOT been run under Windows, analyzed with Dart,
or operator accepted. TERM-01G-C viewer extraction remains separate.

**Historical note:** The original TERM-01F implementation/status statements
below describe the base branch. They must not be mistaken for the
current TERM-01G-B source status.

- Working feature branch: `feature/term-01f-session-service`. No main
  merge/PR acceptance/release. Earlier sections below are chronological,
  not necessarily the newest API or status; this summary takes precedence
  for current decisions.
- `TerminalSessionPool` was renamed to `TerminalSessionService`; explicit
  singleton registration, `TerminalSessionService().items`,
  `newTerminal(...)`, `itemsChanged` and original single attachment per
  native session are implemented.
- Windows operator run after rename: native Debug DLL built, root
  `dart analyze --fatal-infos` clean, **9 root Dart tests passed**,
  `flutter analyze` clean, **8 Flutter tests passed**, Windows Debug
  executable built and launched. Operator confirmed local multi-session
  detach and terminal selection in prior interactive run; this does
  not constitute complete TERM-01F/01G product acceptance.
- Last launcher output ended with `Lost connection to device`; cause
  remains unverified. Do not infer a crash from that line alone.
- TERM-01E Native Assets CLI auto-bundling and ordered manual DLL search
  paths passed actual Windows verification.
- TERM-01G is **not yet implemented**: independent
  `terminal.registerHandler/unregisterHandler` subscriptions,
  `onTerminalState`/`onTerminalStream` event contracts, multiple watchers
  of a single live PTY, `TerminalHandler`/`TerminalHandlerLocal` public
  abstractions and neutral `RemVibeTerminalWidget(handler: ...)`.
- Current example has one visible xterm widget at a time. The target is
  to verify two side-by-side native terminals, then two simultaneous
  viewers of one PTY. xterm state is per widget/pane; output capture is
  per terminal and must continue while no view is selected.
- `selected` belongs to each Console/viewer, not the global Client
  `TerminalSessionService`. Console may use the terminal package to
  create local terminals; an Update Center-supplied remote handler can
  use the same viewer, but the concrete remote implementation must
  live only in Update Center.
- Multi-Console remote watch, authorization, event transport and user
  notifications are NOT authorized for implementation in this repository.
- A terminal's command state `busy/idle/unknown` is independent from
  connection/viewer state. No automatic trustworthy command completion
  detection yet; output silence cannot imply idle. The existing
  detached IDLE=10m/UNKNOWN=30m/RUNNING-exempt rule remains as-is
  pending a separately verified activity classifier.

### Next checkpoint plan (no implementation authorized by this note)

1. Freeze TERM-01G `TerminalHandler` / local handler,
   per-terminal registration and typed event contract in docs.
2. Preserve old session lifecycle and native ABI; implement only after
   explicit checkpoint go-ahead. Local multiple handlers should
   receive sequenced/replayable output without reproducing processes
   or blocking one another.
3. Extract `RemVibeTerminalWidget` into a standalone Flutter package
   only in an accepted packaging checkpoint; no Flutter import in core.
4. Verify analyzer, all prior tests, real Windows ConPTY and dual-pane
   interaction, then seek operator product acceptance.
5. If/when Update Center is unfrozen by the operator, plan and approve
   `TerminalHandlerRemote` and remote multi-Console delivery separately
   in that consumer repo.

---

**TERM-01F — TerminalSessionService singleton and items API [in_progress; no product acceptance]**

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

## TERM-01E — Automatic Windows ConPTY DLL packaging (2026-11-20)

- Operator requested SQLite-style `dart build cli` distribution where
  the Windows terminal DLL is automatically built and included under
  `bundle/lib`, without custom Client scripts copying DLLs.
- Separate branch `feature/term-01e-native-assets-cli` extends the
  still-unmerged TERM-01D branch; no merge or deployment.
- Added `hook/build.dart` using the Dart 3.10+ hooks/code_assets/
  native_toolchain_c APIs. The same existing C++ ConPTY source is compiled
  as a Windows x64 dynamically bundled code asset.
- `RemVibeTerminal.windows()` and `currentPlatform()` default to eight
  `@Native` bindings addressed by the hook's shared asset ID.
  Explicit `libraryPath` override remains intact for current Flutter Debug
  and real ConPTY standalone smoke workflows.
- Added a standalone CLI consumer smoke and PowerShell verifier:
  `tool/verify_native_assets_cli.ps1`. It invokes `dart build cli`, checks
  `bundle/bin/main.exe` and `bundle/lib/remvibe_terminal_windows.dll`,
  then runs the compiled EXE and a real PowerShell/ConPTY marker without any
  explicit DLL path.
- SDK requirement updated to Dart >=3.10.0. Windows MSVC/SDK required
  for building the native code on the CI or developer machine.
- Native ABI/CMake/native C++ source unchanged; portable widget, session pool,
  earlier selection/resize/clipboard behavior not modified.
- Operator Windows run verified the real Native Assets hook and CLI bundle:
  `bundle/bin/main.exe` and `bundle/lib/remvibe_terminal_windows.dll` were
  generated automatically, and the executable produced
  `REMVIBE_TERMINAL_CLI_NATIVE_ASSET_PASS` and
  `TERM-01E WINDOWS CLI NATIVE ASSETS BUNDLE PASS`. No manual DLL copy.
  Full checkpoint acceptance remains open for the multi-path enhancement.
- Previous TERM-01D portable widget/multi-session acceptance is still pending
  and must not be conflated with this packaging checkpoint.
- Do not touch the frozen Update Center repository, live SCM services,
  installed Client/Server or Console.

Next step: run `tool/verify_native_assets_cli.ps1` from the
`feature/term-01e-native-assets-cli` checkout on Windows. Inspect its
output, resolve any actual compiler/bundling/runtime failures, and obtain
operator acceptance before merging or integrating into Update Center.

## TERM-01E additional native DLL search paths (2026-11-21)

- Operator requested RemVibe Networking-style flexible DLL resolution for
  different installation layouts, without losing the proven Native Assets
  packaging path.
- Branch `feature/term-01e-library-search-paths` extends the unmerged
  `feature/term-01e-native-assets-cli` work; main remains unchanged.
- Added `libraryPaths: List<String>` and `searchDirectories: List<String>`
  parameters to `RemVibeTerminal.windows()` and `currentPlatform()`.
  Existing singular `libraryPath:` remains supported and is tried first.
- Resolution order: singular exact path, ordered exact list, then the
  DLL filename under each specified search directory. Duplicate paths are
  skipped. Missing, unloadable and missing-export DLLs are skipped in favor
  of later candidates; exhausted candidate lists throw a typed
  `TerminalNativeLibraryLoadException` with path-by-path failures.
- No manually supplied paths -> original `@Native` bundled code-asset route;
  this keeps the successful `dart build cli` consumer untouched.
  Explicit/manual search never silently falls back to an unrequested asset.
- Added six focused unit tests for ordering, deduplication, immutability,
  invalid inputs and Windows typed failure. Extended the isolated CLI
  verifier: default Native Assets, multiple candidate paths including a
  corrupt DLL, and multiple search directories. The native symbol mappings
  and C++ engine are unchanged.
- Operator executed six native DLL resolution tests on Windows: 6/6 PASS.
  CLI bundle rebuilt successfully (DLL included in bundle/lib without
  manual copy) and compiled EXE launched real PowerShell/ConPTY in three
  modes: auto Native Assets, ordered paths including a corrupt DLL, and
  multiple search directories. All three runtime PASS markers were observed.
  This closes TERM-01E CLI technical verification, NOT product approval.
- No updates to frozen Update Center repository, installed SCM services,
  Console remote adapter, CI runner or any real deployment.

Next: on Windows, fetch and switch to
`feature/term-01e-library-search-paths`, then run
`tool/verify_native_assets_cli.ps1`. Require the original Native Asset
PASS plus both multi-path and search-directory PASS markers before asking
for acceptance. No PR/merge/cleanup without operator approval.

## TERM-01E latest operator result — Windows CLI PASS (2026-11-21)

- Source branch: `feature/term-01e-library-search-paths`.
- `tool/verify_native_assets_cli.ps1`: completed without error.
- Dart DLL-path tests: **6/6 PASS**.
- `dart build cli`: **PASS**, generated `bundle/bin/main.exe`.
- Native asset: `bundle/lib/remvibe_terminal_windows.dll` generated.
- Actual compiled EXE + PowerShell/ConPTY:
  - `REMVIBE_TERMINAL_CLI_NATIVE_ASSET_PASS`
  - `REMVIBE_TERMINAL_MULTI_PATH_FALLBACK_PASS`
  - `REMVIBE_TERMINAL_SEARCH_DIRECTORIES_PASS`
  - `TERM-01E WINDOWS CLI NATIVE ASSETS BUNDLE PASS`
  - `TERM-01E WINDOWS NATIVE LIBRARY MULTI-PATH PASS`
- TERM-01E Windows CLI **technical verification PASS**.
  No operator product/release acceptance, PR/merge or deployment authorized.
- The prior TERM-01D Flutter multi-session widget and detach/reattach
  functionality remain unverified in the live Windows example; that
  interactive checkpoint is the next practical acceptance target.
- Frozen Update Center repo and running SCM services unchanged.

## TERM-01D latest operator interactive evidence (2026-11-21)

- Operator Windows Debug run: native DLL Debug build PASS, root Dart analyzer
  clean, seven root Dart tests PASS, Flutter analyzer clean, eight Flutter
  tests PASS and Windows Debug EXE built/launched.
- Operator explicitly confirmed **multiple terminal detach and session
  selection work** in the real Flutter UI. These are accepted observed
  behaviors, not blanket product acceptance for all TERM-01D features.
- Output ended with `Lost connection to device`, but its cause was not
  established; do not treat it alone as proof of a crash.
- TERM-01E automated native bundling and DLL multi-path verification remain
  technically PASS. No further native packaging work required for this
  checkpoint.

## TERM-01F — TerminalSessionService API (2026-11-21)

- Operator requested renaming `TerminalSessionPool` to
  `TerminalSessionService`, exposing `items` and `newTerminal(...)`,
  and evaluating a process-level singleton.
- New code on `feature/term-01f-session-service`, based on the latest
  `feature/term-01e-library-search-paths`. No main merge.
- Renamed source to `lib/src/session/terminal_session_service.dart` and
  test to `test/terminal_session_service_test.dart`; removed old files,
  updated public export, example local provider and Debug script.
- New `TerminalSessionService()` is a **registered singleton accessor**
  inside one Dart isolate, not an implicit constructor. The Client creates
  `.withEngine(engine:...)` then calls `register(service)`. Accessing
  before registration or trying to register a second live instance throws.
  Tests can build independent `.withFactory` instances without registration.
- `items` returns immutable up-to-date `HostedTerminalInfo` snapshots,
  `itemsChanged` streams lifecycle/activity updates; neither exposes
  native session ownership or networking to the UI.
- `newTerminal(...)` creates a native PTY; `attach(sessionId)` reuses an
  existing detached session; `detach()` preserves it; terminate is explicit.
  Existing output replay (bounded), idle/running/unknown policy and limits
  remain unchanged.
- Each Flutter widget owns a separate xterm2 Terminal state. Existing example
  displays only one current widget at a time; multiple native processes may
  run detached. Recreating a widget replays bounded raw output; full screen
  restoration across long detach is NOT guaranteed.
- No changes to C++ ABI, Native Assets hook, Update Center, Server/Client
  SCM runtime or real Console remote adapter.
- Added service singleton/immutable snapshots/itemsChanged tests. **No real
  Windows analyzer, tests or Flutter interaction run yet for this refactor.**

Next: run `tool/run_flutter_example_debug.ps1` from
`feature/term-01f-session-service`; require root analyzer, nine Dart
service tests, Flutter analyzer/tests and the real interactive multi-session
detach/attach selection check. Do not merge or clean up until explicit
operator acceptance.
