# TERM-01G-B — Local TerminalHandler and multi-subscriber implementation

Status (2026-11-21): **CODE PUSHED FOR REVIEW; NOT TESTED ON WINDOWS; NOT ACCEPTED.**
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
- Existing native C++/ConPTY ABI, build hooks, code assets, DLL resolution,
  Flutter viewer, example provider and installed services are unchanged.
  Windows Debug launcher now runs the **entire root `dart test`** suite.

## Unit test cases committed (execution pending)

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

The above are **test sources only**, not PASS evidence. Windows native,
Dart, Flutter and live GUI verification remain pending.

## Required Windows operator gate

In `D:\Projects\remvibe_terminal`, after fetching the feature branch
and verifying that the checkout is clean:

```powershell
git fetch origin feature/term-01g-local-multi-handler
git switch feature/term-01g-local-multi-handler
git pull --ff-only
dart pub get
dart analyze --fatal-infos
dart test
# Existing launcher also builds native Debug DLL and runs Flutter tests/UI:
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
