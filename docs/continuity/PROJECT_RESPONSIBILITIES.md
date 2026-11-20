# remvibe_terminal — Product Responsibility Boundary

Status: **binding project scope and change-control policy**, recorded 2026-11-21.
Applies to future design, implementation, code review, CI and Codex tasks in
`nusretm/remvibe_terminal`. Read alongside `AGENTS.md`,
`docs/continuity/CURRENT_TARGET.md` and the current checkpoint.

## Mission: one independent terminal capability

`remvibe_terminal` exists to provide a **reusable local terminal engine and
terminal-facing contracts** to any Dart consumer, including a local terminal
in an Update Center Console. It must remain useful **without** Update Center,
RemVibe Networking, Fleet, a Server, a Console, or Flutter.

Do not turn this package into an application framework, remote terminal
product, device management service or networking implementation. Prefer a
small, dependable, working terminal API over unrelated generalization.

## Owned responsibilities — allowed within agreed terminal scope

1. **Local PTY and process lifecycle.** Platform-specific terminal process
   creation, input, interrupt (Ctrl+C), resize, stdout/stderr or PTY byte
   output, exit/failure, native cleanup and shutdown. Windows ConPTY first.
   Any other OS requires a separately approved checkpoint.
2. **Local multi-session management.** `TerminalSessionService`, one
   explicitly registered owner per Dart isolate; session identity,
   lookup/discovery, create, attach/detach, terminate, natural exit, bounded
   replay and idle expiry. `items` is immutable snapshot data and
   `itemsChanged` already reports lifecycle snapshots.
3. **Terminal-specific lifecycle and output events.** Typed
   `onTerminalState` and `onTerminalStream` / equivalent stream APIs,
   terminal identity, ordering, replay/truncation indicators, lifecycle
   reasons, and independent subscribers. A terminal's output is captured
   **regardless of whether any viewer is selected**.
4. **Terminal-specific handler contracts.** Public, UI-independent
   `TerminalHandler` contract and local implementation
   (`TerminalHandlerLocal`), with per-terminal
   `registerHandler`/`unregisterHandler` semantics. Independent output
   handlers can observe one PTY concurrently; unsubscribing never kills it.
   Input/control ownership remains separate from observation.
5. **Terminal state and policy.** Independent axes for session lifecycle/
   viewer attachment and command activity (`busy`/`idle`/`unknown`).
   Detached idle timeout starts from a trustworthy transition to idle;
   running must not be classified from mere output activity or silence.
   Preserve a fail-safe for unknown activity. Never fabricate command
   completion or exit codes.
6. **Native build and distribution mechanics for this library.** Windows
   ConPTY FFI/CMake, Dart Native Assets build hooks and ordered DLL lookup,
   deterministic tests and independent terminal examples.
7. **Terminal-oriented integration surfaces.** Small transport-agnostic
   types/interfaces allowing another project to connect to a terminal
   handler. They may describe terminal I/O, state, sequence, reattachment,
   resize and errors, but MUST NOT import or implement external transports,
   identities, authentication, RPC or Fleet abstractions.

## Separate UI responsibility — not in the core Dart package

A reusable Flutter terminal viewer may be maintained in an **independent
Flutter package** (proposed `remvibe_terminal_flutter`, packaging pending
checkpoint acceptance) depending on the core terminal contract and xterm2.

- `RemVibeTerminalWidget(handler: ...)` should work with either a local
  handler or a consumer-provided remote implementation.
- Widget owns terminal rendering, keyboard input, selection, scrollback,
  clipboard confirmation, resizing, focus and per-view `selected` state.
- Each displayed terminal viewport has **its own** xterm model. Multiple
  simultaneous panes and multiple viewers of the same PTY are supported
  by independent handler subscriptions, not by reusing one global xterm.
- A viewer changing selection does NOT change another Console's selection
  or affect other subscriptions. Selection is **per viewer/Console**,
  not a global property of the Client's `TerminalSessionService`.
- The core package does **not** import Flutter or xterm2; the current
  example widget is proof-of-concept code, not yet an extracted published
  Flutter library.

A **local Console terminal** is allowed as a consumer of the core package.
The Console application decides whether its handler is local or remote;
the UI widget should not need to distinguish them.

## Explicitly OUT OF SCOPE for remvibe_terminal

These belong to a consuming application or separate repository, and MUST
NOT be quietly added to the terminal core or its Flutter viewer:

- `TerminalHandlerRemote` concrete implementation, network protocols,
  sockets/RPC, RemVibe Networking Direct/Relay, session routing or relay.
  **`TerminalHandlerRemote` belongs in `remvibe_update_center`** and
  implements the shared `TerminalHandler` contract from this package.
- Server/Client/Console application orchestration, remote session ownership,
  user/device identities, token/authorization/capability checks, operator
  permissions, device inventory, Fleet broker state and remote handover.
- Cross-device terminal output delivery, per-network-viewer queues and
  acknowledgments, remote replay persistence, multi-Console notifications,
  notification preferences/push delivery and Server reconciliation.
- Windows SCM service hosting, service installation, persistence across a
  Client process restart, application installation/updating/signing,
  release distribution, background job/workflow engine, telemetry and
  unrelated app features.
- Application UI beyond the terminal viewer, or a transport implementation
  embedded inside a generic widget.
- Speculative platform support, security hardening, backward-compatibility
  shims or architecture for hypothetical external products.

This is a **responsibility boundary**, not a ban on future proposals.
A task that crosses the boundary is **blocked by default** until separately
planned and explicitly approved; it must then be implemented in the correct
owner project or accepted as an intentional scope expansion.

## Change-control rule — mandatory before any new responsibility

**NO responsibility outside the list above may be planned as already approved,
implemented, merged or accepted merely because it looks useful.**

Before expanding this project's responsibilities, the operator must
explicitly approve a written proposal that identifies:

1. **Why:** the user-facing terminal requirement and why the existing
   abstractions cannot serve it.
2. **Owner:** which repository/package owns the behavior, and why it cannot
   remain in the consumer.
3. **Boundaries:** dependencies, public API, behavior, data ownership and
   explicit non-goals, including Client/Server/Console responsibilities.
4. **Impact:** compatibility, native/Flutter/Windows consequences, risk to
   current working features and required migrations, if any.
5. **Verification:** concrete unit/integration/real Windows interaction
   checks, failure paths and rollback strategy.
6. **Approval:** operator's explicit scope acceptance **before writing
   functional code**, plus separate technical/product acceptance after
   verification.

Discussion, exploratory designs, suggestions, CI success, a new feature
branch or an assistant recommendation are **not** operator approval.
Approval to design is not approval to implement; implementation is not
approval to merge/release/deploy. If a requirement is not assigned and
accepted, write a proposal, **do not silently implement it**.

For already agreed terminal-scoped changes, work in a feature branch with
small checkpoints, tests and continuity updates. Do not touch the frozen
`nusretm/remvibe_update_center` repository or running SCM services without
explicit authorization. No automatic main merge, release, deployment or
cleanup.

## Approved direction vs implemented behavior (2026-11-21)

**Current TERM-01G-B status update:** On
`feature/term-01g-local-multi-handler`, the neutral TerminalHandler and
TerminalHandlerLocal, typed events and multiple subscriptions are now
implemented in source with new unit tests. Windows execution, Dart/Flutter
analyzers, live PTY/GUI verification and operator product acceptance are
PENDING. See `TERM_01G_B_IMPLEMENTATION.md`. The historical TERM-01F
baseline below remains accurate for the earlier source revision.

**Implemented in current TERM-01F source:** local `TerminalSessionService`,
`newTerminal`, `items`, `itemsChanged`, independent local PTYs, one
attachment per terminal, bounded output replay and native Windows build.
These are not evidence of a multi-viewer handler implementation.

**Original future design at TERM-01F baseline (now partially implemented on TERM-01G-B feature branch):**

- One `TerminalHandler` contract usable by native/local and by an
  externally implemented remote adapter.
- Per-terminal `registerHandler` / `unregisterHandler` supporting
  multiple independent viewers without duplicating native processes.
- Typed state and raw-output events: `onTerminalState` and
  `onTerminalStream`; per-session ordering, replay and gap reporting.
- `TerminalSessionService.getTerminal(terminalId)` / terminal handle
  lookup is a proposed convenience API, not yet shipped.
- Per-Console and per-view selected terminal; not one shared selection in
  the Client singleton.
- Same widget accepts a local or consumer-provided remote handler; two
  side-by-side terminals and two viewers of one terminal are acceptance
  scenarios.
- Genuine command busy/idle detection must be demonstrated before
  generating job-complete notifications. Existing `idle/running/unknown`
  activity categories do not prove automatic detection.

**Consuming-project follow-up, NOT AUTHORIZED FOR IMPLEMENTATION HERE:**
Concrete `TerminalHandlerRemote`, multiple remote Console delivery,
Server/Client protocol changes and notifications belong to
`remvibe_update_center` and require a separate unfreeze/approval.

## Reference verification status

- TERM-01E Windows Native Assets and ordered DLL candidates: user technical
  verification **PASS**.
- TERM-01F operator Windows Debug: root `dart analyze --fatal-infos`
  clean, **9 Dart tests PASS**, Flutter analyzer clean, **8 Flutter tests
  PASS**, Windows Debug EXE built/launched; user previously confirmed
  multiple terminal detach and session selection. That observation is
  narrower than full acceptance of all TERM-01F/01G behavior.
- Debug log ended with `Lost connection to device`, with no confirmed
  cause. Do not label it a verified crash or a clean application shutdown.
- TERM-01G multi-handler/event implementation and separate Flutter
  package are still **pending**, with no Windows acceptance.
