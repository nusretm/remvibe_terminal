# TERM-01F — TerminalSessionService API and xterm lifetime

Status at original implementation: **in_progress**; Windows verification
was then pending. Current evidence and architecture overrides follow. TERM-01D interactive
detach/reattach and session selection were reported PASS on the previous
branch, and TERM-01E Native Assets + DLL search CLI verification passed.

> **Updated 2026-11-21:** TERM-01F operator Windows technical verification
> now PASS (root 9 tests, Flutter 8 tests, both analyzers clean, Debug
> executable built/started). Multi-session detach and session selection
> were observed working. This is NOT blanket product acceptance.
> The earlier "pending" text below is historical. See
> [CURRENT_TARGET](CURRENT_TARGET.md) for the active TERM-01G direction
> and [PROJECT_RESPONSIBILITIES](PROJECT_RESPONSIBILITIES.md) for the
> binding terminal-only scope and required operator approval gate.
>
> The existing local example has exactly one active widget attachment
> per PTY. A Console may host its own LOCAL `TerminalSessionService`
> to run local terminal operations, while Update Center's separate
> `TerminalHandlerRemote` remains an application responsibility.
> This supersedes the narrower earlier statement that a Console
> should never instantiate a local terminal service.

## Decision: process-scoped singleton, explicit registration

`TerminalSessionPool` is renamed to `TerminalSessionService` in the Dart
package (source: `lib/src/session/terminal_session_service.dart`).

A Client process should have **one owning service per Dart isolate**, with a
native `RemVibeTerminal` engine created once during startup:

```dart
final engine = RemVibeTerminal.currentPlatform();
final service = TerminalSessionService.register(
  TerminalSessionService.withEngine(
    engine: engine,
    maximumSessions: 4,
  ),
);

// All callers in THIS Dart isolate receive the same service:
final same = TerminalSessionService();
assert(identical(service, same));

final terminal = same.newTerminal(
  commandLine: 'powershell.exe -NoLogo -NoProfile',
  columns: 100,
  rows: 30,
);

final current = TerminalSessionService().items;
final sessionId = current.first.sessionId;
await terminal.detach(); // Preserves real PTY.
final attachedAgain = TerminalSessionService().attach(sessionId);

// Destructive operations are explicit:
await attachedAgain.detach();
await service.terminateSession(sessionId);
await service.close();
await engine.close();
```

`TerminalSessionService()` is **only an accessor to a registered singleton**,
never a hidden engine constructor. Calling it before registration throws a
`StateError`. Attempting to register another live service also throws.
Closing the registered service releases the registration. This prevents
accidental second native PTY owners and makes startup/shutdown explicit.

For unit tests and intentionally independent scoped hosts use
`TerminalSessionService.withFactory(processFactory: ...)` without
registering. The example registers its local service during initialization.
A registered instance is isolated to one Dart isolate/process — it cannot
be shared by the Windows Client service, Server and Flutter Console as a
cross-process Dart object.

## Public session API

- `TerminalSessionService().items` is an immutable, **fresh snapshot** of
  `HostedTerminalInfo` (ID, PID, command line, activity, attached state,
  timestamps, replay truncation/sequence); it is **not** a mutable collection
  of PTY handles.
- `itemsChanged` broadcasts fresh snapshots on create/attach/detach,
  command activity changes and removal/expiry. It does not broadcast each
  output frame; the attached session's own output stream supplies that data.
  Consumers should first read `items` then listen to `itemsChanged`.
- `newTerminal(commandLine:, columns:, rows:, sessionId: ...)` opens an
  independent OS process and returns its `HostedTerminalAttachment`.
- `attach(sessionId, afterSequence: 0)` re-attaches to a **detached** still
  running session; `detach()` closes only the viewer, not the process.
- `terminateSession(sessionId)` ends the actual process; idle expiry and
  natural process exit also remove it from `items`.
- Existing limits are unchanged: four concurrent sessions, bounded 64 KiB
  output replay, detached IDLE=10 minutes, UNKNOWN=30 minutes and
  explicitly marked RUNNING commands exempt from detached timeout.

A saved `HostedTerminalInfo` snapshot does not auto-update. Read `items`
again or use `itemsChanged` for changes. Its session ID is sufficient for
the **local host service** to re-attach; remote access still requires the
existing Fleet broker's authenticated session reference and authorization.

## xterm: PTY process is NOT the Flutter terminal display

The native `TerminalSessionService` never imports Flutter or xterm2.
Each `RemVibeTerminalWidget` creates its own `xterm2.Terminal` in widget
state. The current example displays only **one active widget**, so it
normally has one xterm display model while several PowerShell/CMD native
processes continue in the background. Switching or detaching disposes the
old widget; reattachment creates another xterm model and replays the
bounded session output history.

A multi-pane Console could display multiple widgets simultaneously, each
with a **separate** xterm model. Never share one xterm model between
independent terminal sessions: cursor, parser state, selection and
scrollback would interfere.

The service currently retains limited **raw PTY output frames**; it does
not persist xterm parser state, cursor and entire scrollback per session.
Replaying 64 KiB of raw output cannot guarantee lossless restoration after
long/high-output detach (particularly mid-ANSI sequences). A separate
screen snapshot/reflow design would be needed if a future Console feature
requires exact seamless visual restoration across detach/reattach.

## Integration boundaries

- Windows Client service owns `TerminalSessionService` and ConPTY.
- Update Center Server continues to authorize users, devices and remote
  terminal sessions and implements the previously established remote
  create/list/attach/detach/terminate/routed I/O contract.
- Flutter Console gets `TerminalSessionProvider` / `TerminalSessionBinding`
  through a remote adapter; it should NOT instantiate the local native
  singleton or load ConPTY.
- No networking, live SCM service, native C++ or Update Center code changed.

## Technical verification gate

Run `tool/run_flutter_example_debug.ps1` from the new branch. The script
now runs `test/terminal_session_service_test.dart`, including fresh tests
for process-scoped singleton registration, immutable items and lifecycle
notifications. Windows analyzer, Flutter test and real multi-session UI
results after the rename are still **pending**.

Do not merge or perform cleanup without operator approval.

## TERM-01G design boundary (subsequent decision, not in TERM-01F code)

- Add terminal-owned `TerminalHandler` interface and local implementation;
  a consumer's `TerminalHandlerRemote` must NOT be implemented or imported
  in this package. A remote handler belongs solely to Update Center.
- Add multiple independently registered per-terminal handlers and typed
  `onTerminalState`/`onTerminalStream` callbacks while keeping process
  creation, state, raw output reading and lifecycle inside the core.
- The Flutter viewer will accept a `TerminalHandler`; it should move to a
  separate Flutter package so this root Dart package remains Flutter-free.
- Selection is per viewer/Console, not a property of the registered Client
  singleton. A local Console terminal is a valid consumer of the package.
- No implementation of this new architecture exists in TERM-01F; do not
  claim `TerminalHandlerLocal` or multiple watchers have shipped yet.
- A documented scope expansion requires prior explicit operator approval;
  the full mandatory boundary is in `PROJECT_RESPONSIBILITIES.md`.
