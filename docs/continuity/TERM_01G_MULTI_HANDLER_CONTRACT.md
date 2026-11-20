# TERM-01G — Multi-subscriber TerminalHandler contract (DESIGN ONLY)

Status: **architecture direction agreed 2026-11-21; no functional
implementation, Windows acceptance, merge or product release**.

This note is subordinate to the mandatory scope rules in
`PROJECT_RESPONSIBILITIES.md`. It MUST NOT be interpreted as permission
to implement remote transport or expand this package's product scope.

## Goal

A terminal is an independently running OS PTY. One or more local viewers
may receive its **same sequenced output**, without opening additional PTYs.
A terminal's output must keep being collected when no viewer is selected.
The consumer decides how to display or transport this data.

Use the same terminal-facing Dart contract in local console apps and in a
consumer-provided remote handler. A Flutter viewer should render terminal
output without knowing which kind of handler it received.

## Owners

| Component | Correct owner | Scope |
| --- | --- | --- |
| `TerminalSessionService` | `remvibe_terminal` | Local PTYs, session lifecycle, identity, bounded output, activity categories |
| `TerminalSession` / terminal handle | `remvibe_terminal` | Per-terminal registration, unregistration, terminal-specific state/output |
| `TerminalHandler` contract | `remvibe_terminal` | Transport-agnostic terminal I/O and event subscription |
| `TerminalHandlerLocal` | `remvibe_terminal` | Implements handler contract over locally hosted session |
| `TerminalHandlerRemote` | `remvibe_update_center` | Implements same contract using existing remote routing; NEVER part of this package |
| Reusable `RemVibeTerminalWidget` | separate Flutter terminal-view package (future, acceptance required) | xterm rendering, input/resize/selection/clipboard; NO networking |
| Server/Client/Console transport, auth, remote watch, notifications | `remvibe_update_center` | Routed multi-Console delivery and permissions, separately planned/unfrozen |

No `remvibe_terminal` source should import Update Center, Networking,
Fleet, remote access/account roles, Flutter, xterm2 or server RPC libraries.
Terminal-specific generic models do not need consumer-specific wire formats.

## Proposed API shape (illustrative, NOT yet shipped)

```dart
// Client/local process: after explicit service registration
final terminal = TerminalSessionService.getTerminal(terminalId);
if (terminal != null) {
  final token = terminal.registerHandler(
    onTerminalState: (terminal, event) {
      // Local terminal event. A consumer may translate/send it elsewhere.
    },
    onTerminalStream: (terminal, event) {
      // Raw bytes + per-terminal sequence + replay/gap metadata.
    },
  );

  // Unsubscribe the one viewer without terminating the PTY.
  terminal.unregisterHandler(token);
}

// Future UI (separate Flutter package):
RemVibeTerminalWidget(handler: localHandler);
RemVibeTerminalWidget(handler: remoteHandler); // Consumer-supplied class
```

The method names are design decisions; exact public parameter/return
types, async semantics and handler identity must be finalized in a
small, reviewed API checkpoint. Do not silently claim current
`HostedTerminalAttachment` already supports multiple subscribers.

## Required behavioral rules

1. **One producer per PTY.** Native output is consumed once per hosted
   terminal, then distributed to independent subscribers. Registering a
   handler cannot create a new terminal OS process.
2. **Independent watchers.** Two handlers may watch a single terminal,
   plus independent handlers on other terminals. Unregistering or closing
   one watcher does not detach/control/terminate other watchers or the PTY.
3. **Control is separate.** Attaching for keyboard input/control is not
   equivalent to registering for read-only output; only the authorized
   controller may input/resize/interrupt. Local mechanics are generic;
   remote authorization remains an Update Center duty.
4. **Ordering and replay.** Events carry terminal ID and monotonic
   per-terminal output sequence. `afterSequence`/replay may be provided
   when registering. Replay must precede live frames without gaps caused
   by subscription races; truncated history must be surfaced explicitly.
   Existing bounded replay is preserved unless a separately accepted
   checkpoint changes it.
5. **Failure isolation.** A failing, disconnected or slow handler must not
   block native output collection or the other handlers. Use bounded
   queues/cancellation and report backpressure/gaps; no unbounded memory
   growth. Network-specific delivery is the consumer's responsibility.
6. **State vs output.** Typed `onTerminalState` covers terminal lifecycle
   and independent command state; `onTerminalStream` covers ordered raw
   byte output. Existing `itemsChanged` snapshots remain a separate
   discovery/UI-list mechanism.
7. **Separate state axes.** Per-view selection, per-view attachment/control
   and terminal command activity must not be collapsed into one enum.
   `selected` is local to the Console/pane; it is never global to the
   Client's registered service.
8. **Busy/idle correctness.** The existing activity buckets
   `idle/running/unknown` are present, but automatic per-command detection
   is not. Do not emit completion notifications or reset 10-minute expiry
   on output silence. Running must be established authoritatively; unknown
   retains its fail-safe.
9. **Viewer rendering.** One xterm model per visible pane, including if
   two panes watch the same PTY. A widget gets a `TerminalHandler`, owns
   its own subscriptions, and releases just those subscriptions when
   disposed. It does not own the terminal process.
10. **No remote implementation here.** Multi-Console subscription mapping,
    transport buffering, authentication, notifications and controller
    handover are explicitly deferred to a separately accepted consumer
    checkpoint in Update Center.

## Checkpoint and acceptance sequence

- **TERM-01G-A — contract approval:** Freeze typed event models,
  handler registration lifetime, state axes and backpressure/replay rules,
  with explicit operator sign-off before implementing.
- **TERM-01G-B — local implementation:** Implement only terminal-owned
  handler/events/subscribers on feature branch. Maintain Native Assets,
  public local PTY lifecycle and existing idle cleanup. Add tests for
  2 viewers / 1 PTY, 2 PTYs / 2 viewers, race-free replay, sequence gaps,
  unregister, failure isolation, termination and idle expiry.
- **TERM-01G-C — viewer extraction (separately approved):** Move existing
  xterm widget from example to distinct Flutter package with only
  terminal-core contract and Flutter/xterm2 dependencies. Test side-by-side
  local panes and duplicate view of one session.
- **TERM-01G-D — real Windows operator check:** Root `dart analyze
  --fatal-infos`, all Dart tests, Flutter analyzer/tests, ConPTY live
  keyboard/output/resize, detach/re-register and dual-pane rendering.
  Require explicit operator acceptance before merging/releasing.

**Out-of-scope follow-up:** `TerminalHandlerRemote`, routed watcher
multiplexing, Server state propagation, remote command completion
notifications and cross-device takeover require a NEW, separately approved
Update Center plan. The Update Center repository and running SCM services
remain frozen under the current instructions.

## Evidence already available — do not overclaim

The TERM-01F Windows Debug script ran: native Debug build PASS,
root analyzer clean, 9 Dart tests PASS, Flutter analyzer clean,
8 Flutter tests PASS, and Windows executable built/started. The
operator confirmed existing multi-session detach/selection functionality.
Those results do NOT verify multiple handlers or simultaneous xterm panes.
Last Flutter runner said `Lost connection to device` without established
cause; this is not by itself evidence of a crash.
