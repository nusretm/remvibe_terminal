# TERM-01G-B — Local TerminalHandler and multi-subscriber implementation

Status (2026-11-21): **TERM-01G-B Windows local core technical gate PASS; operator GUI verification and scoped TERM-01G-B feature acceptance PASS.** Release/merge/deployment NOT authorized.
Branch: `feature/term-01g-local-multi-handler`.
Base: `feature/term-01f-session-service` at
`abb8886797cbce2102b86a378867b40777c16eb2`.
TERM-01G-A contract was frozen on this feature branch before implementation.

## Scope delivered in source

- New Flutter-free `TerminalEventSource`, `TerminalHandler`,
  `TerminalHandlerLocal`, `TerminalHandlerRegistration`,
  `TerminalStateEvent`, `TerminalStreamEvent`, and
  `TerminalCommandState` public exports.
- `TerminalSessionService.getTerminal(terminalId)` resolves the explicitly
  registered service; `service.findTerminal(id)` supports independent hosts.
  `TerminalSession` is a stable local session handle, not a PTY owner.
- One existing native output subscription per session remains intact.
  `HostedTerminalAttachment` retains its old single-controller contract.
  Per-session `registerHandler` / `unregisterHandler` are independent
  observations and do not create/attach/detach/kill a process.
- Bounded replay remains under `maximumReplayBytes`; each subscriber has
  a maximum 128 pending events and 128 KiB pending data. After-sequence
  replay is exclusive, queued synchronously before live events in the
  owning Dart isolate. Stream gaps report lost inclusive frame sequences
  due to replay truncation or subscriber backpressure. Stream event data
  is copied per subscriber and has per-terminal monotonic sequence IDs.
- Callback delivery is per-subscriber async; a failing or awaiting callback
  cannot directly hold up other subscribers or the native subscription.
  CPU-bound synchronous callbacks still block the shared Dart isolate;
  isolate offload is NOT introduced.
- State callbacks include historical creation marker and initial snapshot,
  controller attach/detach, authoritative command state changes,
  natural exit (known OS exit code only), explicit termination and expiry.
  Initial command state retains TERM-01F's existing idle category.
  Neither output activity nor prompt/silence marks command completion.
- Local handler can watch without a controller or wrap an existing matching
  `HostedTerminalAttachment` for input, resize, interrupt and detach.
  `TerminalHandlerRemote` does not exist in this repository.
- Added `tool/term_01g_windows_multi_handler_smoke.dart` for a genuine
  two-PowerShell-PTY test (two independent subscribers on first PTY,
  unregister isolation, output while controller detached, and reattach
  retaining the original PID). The Debug launcher requires this LIVE test
  before starting Flutter; the second operator run completed it successfully.
- Existing native C++/ConPTY ABI, build hooks, code assets, DLL resolution,
  Flutter viewer, example provider and installed services are unchanged.
  Windows Debug launcher now runs the **entire root `dart test`** suite.

## Unit tests: 27/27 PASS on second Windows verification

`test/terminal_multi_handler_test.dart` covers:

1. Two PTYs producing output; two independent watchers on one PTY.
2. One watcher unregistered without stopping the other watchers/PTYS.
3. Bounded replay plus explicitly reported missing sequence range.
4. Replay-before-live ordering, no registration race.
5. Slow asynchronous watcher queue overflow and fast watcher isolation.
6. Failing watcher callback isolation.
7. Read-only local watcher and separate active controller.
8. Created/snapshot, activity, detach and natural exit with actual code.
9. Distinct explicit termination and detached idle expiry causes.
10. Explicit registered lookup vs independent host lookup.

### Historical first attempt (superseded by successful second run)

The operator's first Windows run built the native Debug DLL (PASS),
resolved dependencies (PASS), and ran root `dart analyze --fatal-infos`
with no issues (PASS). Root `dart test` reported **26 passed, 1 failed**.
The sole reported failure was `test/remvibe_terminal_api_test.dart`:
it expected the earlier `ArgumentError` for a missing manual DLL, whereas
TERM-01E correctly returns `TerminalNativeLibraryLoadException` with
attempted paths and failure diagnostics. The test expectation was updated
in commit `1a7b7827116cebbe0f3055f90d9656eed9ab538f` WITHOUT changing
DLL runtime behavior. Its corrected assertion and the complete suite
had NOT been rerun at that time. The subsequent full suite is now 27/27 PASS.

The launcher stopped at root Dart tests; the live two-PTY smoke test,
Flutter analyzer/tests and Debug GUI were therefore **NOT RUN** in this
attempt. The user's initial `git status --porcelain` returned nonempty
before branch switch; the changes were not shown in the supplied output.
Check and protect local worktree contents before further pulling.
That first attempt was not successful. The second attempt later passed
Windows native and Dart/Flutter technical checks; subsequent operator
GUI confirmation is recorded below. The first attempt remains historical.

## Windows re-verification and GUI acceptance gate

For any further Windows rerun, use the existing isolated worktree
`D:\Projects\remvibe_terminal_term_01g_verify`; first check its
`git status --short` before updating. The commands below are the
ordinary clean-feature-branch equivalent, not an instruction to overwrite
any generated/untracked Windows runner files:

```powershell
git fetch origin feature/term-01g-local-multi-handler
git switch feature/term-01g-local-multi-handler
git pull --ff-only
dart pub get
dart analyze --fatal-infos
dart test
# Existing launcher builds native Debug DLL, executes the real TERM-01G
# dual-PTY smoke, then runs Flutter analyzer/tests and the Windows UI:
.\tool\run_flutter_example_debug.ps1
```

Then verify real Windows ConPTY, output from two independent terminals,
re-register after detach, two separate local handlers watching the same
PTY without a duplicate process, Ctrl+C, resize and actual UI behavior.
Current example remains ONE visible pane; parallel-pane GUI acceptance
belongs to separately approved TERM-01G-C, not to TERM-01G-B.

Do not infer TERM-01G-B test success from earlier TERM-01F Windows results.
An operator must supply actual analyzer/test/Windows evidence.
No `main` merge, PR acceptance, release, deployment, cleanup, frozen
Update Center change, SCM service manipulation, networking or remote adapter
has been authorized.

## Windows operator verification — second run (2026-11-21)

Executed in the isolated detached worktree
`D:\Projects\remvibe_terminal_term_01g_verify` at GitHub commit
`49f6e821142127692ed402ea01f8366b0fb6e8c6`.

**Technical PASS evidence (operator-provided console output):**

- CMake configure + MSVC Windows x64 Native Debug ConPTY DLL build: PASS.
- Root `dart pub get`: PASS; `dart analyze --fatal-infos`: "No issues found".
- Root `dart test`: **27/27 PASS**, including corrected typed
  missing-DLL exception assertion and TERM-01G-B unit tests.
- Real `tool/term_01g_windows_multi_handler_smoke.dart`:
  `TERM-01G REAL TWO PTYS / TWO VIEWERS ONE PTY PASS`;
  `TERM-01G REAL UNREGISTER ISOLATION PASS`;
  `TERM-01G REAL DETACHED OUTPUT PASS`;
  `TERM-01G REAL REATTACH SAME PID PASS`;
  `TERM-01G WINDOWS LIVE MULTI-HANDLER SMOKE PASS`.
- Flutter `pub get`: PASS; `flutter analyze`: "No issues found";
  Flutter tests: **8/8 PASS**.
- Flutter Windows Debug executable built and launched; VM Service address
  printed. This proves a successful build/start, **not GUI acceptance**.

**Clarified observation:** The operator reports that `Lost connection to
device` consistently appears when closing the Flutter main window directly
rather than stopping `flutter run` with `q`. The operator reports no issue
with this behavior. Treat the line in this run as expected debugger device
disconnection after window closure, **not** as a verified application crash.
The existing example has one visible terminal pane; side-by-side widget
acceptance remains TERM-01G-C.

**Worktree safety:** The original `D:\Projects\remvibe_terminal` had
untracked generated `example/.gitignore`,
`example/analysis_options.yaml`, and `example/windows/`. The operator
used an isolated detached worktree for this run. No cleanup/deletion is
authorized in either location.

TERM-01G-B local core and live dual-PTY **technical verification PASSED**;
operator subsequently confirmed live Windows GUI terminal creation,
detach and session-list selection work and accepted those tested behaviors.
The unimplemented TERM-01G-C two-pane UI is **not** accepted. Do not
merge, release, deploy, clean up, modify the frozen Update Center repository
or SCM services.

## Operator interactive Windows acceptance clarification — 2026-11-21

The operator explicitly confirmed in the real Flutter Windows Debug window:
multiple local terminal sessions created successfully, detach works, and
selecting sessions from the session list works. The operator considers all
these interactions functioning correctly. The console message `Lost
connection to device` is reproducibly observed when the main application
window is closed directly rather than quitting from the `flutter run`
console with `q`; this is not an observed functional failure.

Together with the already logged 27/27 root Dart tests, 8/8 Flutter tests,
and real Windows dual-PTY/two-watchers smoke PASS, this closes the
**TERM-01G-B local Windows functionality/interactive acceptance**. This
does NOT assert real GUI dual-pane or two simultaneously visible xterm
viewers (TERM-01G-C), remote implementation, release readiness, or broader
cross-platform acceptance. Preserve existing branch/worktrees and frozen
Update Center/SCM boundaries; no merge, deployment or cleanup permission.
