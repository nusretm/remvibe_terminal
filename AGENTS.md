# remvibe_terminal — working rules

**Active TERM-02A Linux PTY checkpoint (operator-authorized 2026-11-21):** Separate `feature/term-02a-linux-pty` branch adds real Linux openpty/supervised Bash PTY and Dart Native Assets. Linux C++ native smoke passed, including adversarial waitpid reaping. Operator Ubuntu third run: analyzer PASS; 29 tests PASS, one exitCode-null failure. Native supervisor fix committed; full Dart analyzer/tests/live smoke rerun PENDING. Linux Flutter real-shell GUI and operator acceptance remain PENDING. Latest Ubuntu: previous core Dart suite **30/30 PASS**; new ANSI-aware smoke regression test introduced 6 unescaped Bash prompt dollars and caused **9 Dart analyzer errors** (fifth run). Test-only syntax fix `de00b12` committed, analyzer/tests/smoke rerun pending. The previously accepted TERM-01G-B Windows branch and TERM-01G-C viewer remain protected. Read `docs/continuity/TERM_02A_LINUX_PTY.md`. No automatic main merge/release/cleanup.


**Completed checkpoint: TERM-01G-B local multi-handler/events [Windows native/analyzer PASS, 27/27 Dart tests PASS, live dual-PTY multi-handler smoke PASS, Flutter analyzer and 8/8 Flutter tests PASS, operator Windows GUI multi-session/detach/session selection PASS; scoped feature acceptance recorded].** TERM-01F technical Windows verification passed, but no blanket product acceptance. Read `docs/continuity/PROJECT_RESPONSIBILITIES.md` and `docs/continuity/CURRENT_TARGET.md` **before proposing or implementing work**.

- Product First, Functionality First, Windows First.
- Local target checkout: `D:\Projects\remvibe_terminal`.
- Root package owns independent native PTY/process lifecycle, public Dart stream/events, and a Flutter-free TerminalSessionService for local Client processes. Keep Flutter and xterm2 out of root dependencies.
- Flutter demo is directly under `example/`; preserve `example/windows_terminal_smoke.dart`. Do not add a nested Flutter application directory.
- Frozen `nusretm/remvibe_update_center` reference: `be22cf19bf8310fc84c669dd2e9cf766c8b9d43d`; never change it or live SCM services, binaries or data.
- Windows x64 first. No speculative Linux/macOS, RPC, Fleet/Networking or unrelated security layers.
- Native tests and local smoke are technical evidence only. Require the actual Flutter terminal experience running in Windows Debug and explicit operator acceptance; do not mark accepted based on tests.
- Feature push does not authorize PR merge, release, deployment or cleanup.

- Portable Console widget source lives in `example/lib/terminal_widget/`; the local example provider is NOT part of that portable widget contract.
- Session lifecycle: multiple independent PTYs, list/attach/detach, bounded output replay and automatic idle expiry. Detach never terminates. Explicit terminate, process exit or Client shutdown do.
- Detached activity policy: IDLE=10 min, UNKNOWN=30 min fail-safe, RUNNING exempt only when the authoritative Server/Client marks command activity. Output is not a trusted activity classifier.
- Session IDs are not credentials. The old Update Center Server owns device authorization, principal ownership, references, connection generation and Network routing.
- No actual Console networking adapter has been implemented. Operator verified local multiple terminals, detach and session selection in Windows Debug; this is scoped evidence, NOT blanket product acceptance.

- TERM-01E packages ConPTY via Dart Native Assets build hook on Windows x64:
  `hook/build.dart` + `@Native` asset ID. The existing C++ implementation,
  ABI, CMake and Flutter terminal widget must remain intact.
- Dart 3.10+ SDK; `hooks`, `code_assets`, `native_toolchain_c` are
  regular package dependencies. Compilers are expected on the Windows CI host.
- Default Windows FFI uses the bundled code asset; explicit `libraryPath`
  overrides the default for legacy manual smoke/Debug. Never fake a PASS by
  manually placing a DLL in the CLI build output.
- Do not accept the checkpoint without an actual `dart build cli`
  consumer bundle under `bundle/bin` and `bundle/lib` and real ConPTY
  PowerShell command execution from the compiled binary.
- Prior TERM-01D interactive multi-session detach/selection was reported PASS.
  Other behavior needs individual verification and explicit acceptance.
  Do not merge, deploy, clean up or touch frozen Update Center services
  without explicit operator approval.

- Operator Windows `dart build cli` native asset and ordered manual
  library path fallback both PASSED: 6/6 resolution unit tests, generated
  bundle/bin EXE + bundle/lib DLL, and real ConPTY/PowerShell execution
  with default Native Assets, corrupt/missing/valid file candidates, and
  search directories. Technical verification is complete; product/release
  acceptance is NOT granted.
- Native DLL search precedence: optional `libraryPath`, `libraryPaths`
  (exact ordered files), then `searchDirectories` expanded to the DLL name.
  Try later candidates after missing, invalid or unloadable files; report
  all failures if manual candidates are exhausted. No silent manual-to-asset
  fallback. With no candidates use the successful automatic code asset.
- Preserve public single-path API, native C++ ABI, build hooks and Flutter
  example. Do not introduce networking or deployment changes for this task.

- Rename is intentional: public hosting API `TerminalSessionService` owns
  local native sessions, not Flutter. Register exactly one shared service per
  Client isolate at startup; `TerminalSessionService()` accesses it only after
  explicit registration. Independent `withFactory` hosts are allowed for tests.
- `items` is immutable snapshot data, `itemsChanged` reports lifecycle
  changes, `newTerminal(...)` creates an independent PTY; an item is not a
  native handle and reattachment requires `attach(sessionId)`.
- xterm2.Terminal is owned by each Flutter widget State, NOT by the native
  session service. One active widget in the example means one xterm display
  for potentially many live native PTYs. Preserve remote adapter separation.
- TERM-01F operator Windows evidence: native Debug build, root analyzer clean,
  9 service Dart tests PASS, Flutter analyzer clean, 8 Flutter tests PASS,
  Debug EXE built/launched; local detach/session selection confirmed. Log ended
  with `Lost connection to device` (cause unverified). No release, merge,
  Console networking, SCM or deployment work authorized.

## Binding product responsibilities and scope gate (2026-11-21)

**TERM-01G-B source update:** `feature/term-01g-local-multi-handler`
contains the neutral handler/events, per-terminal independent watchers,
local handler implementation and tests. Windows technical verification and
operator GUI verification of existing multi-session creation, detach and
session selection PASSED for this checkpoint. `docs/continuity/TERM_01G_B_IMPLEMENTATION.md`
is the execution/verification checklist. The older TERM-01F-only statements
below remain historical and do not override the current source status.

**Source of truth:** `docs/continuity/PROJECT_RESPONSIBILITIES.md`.
**TERM-01G-A frozen contract (TERM-01G-B local Windows scope verified/accepted):** `docs/continuity/TERM_01G_MULTI_HANDLER_CONTRACT.md`.
This responsibility boundary applies to Codex, assistant and all contributors.

- `remvibe_terminal` is a **standalone terminal library**: local PTY/ConPTY
  execution, input/output/interrupt/resize/exit, native build/Native Assets,
  local multi-session ownership, terminal-specific handler contracts,
  typed lifecycle/output events and bounded output replay. Stay Windows-first.
- Root Dart package must remain usable without Flutter, xterm2, networking,
  Fleet, Update Center, any Server/Console, identity/authorization or RPC.
  A future terminal Flutter viewer should live in a **separate Flutter
  package**, not add Flutter to the core Dart package.
- TERM-01G-B feature branch implements the terminal-owned `TerminalHandler`,
  `TerminalHandlerLocal`, per-terminal `registerHandler`/`unregisterHandler`
  and typed state/output callbacks. It preserves exactly one controlling
  `HostedTerminalAttachment` per PTY while adding independent read-only
  subscriptions. The local Windows implementation has technical PASS and
  operator acceptance for the tested GUI actions. The neutral Flutter widget
  is NOT yet extracted; dual-pane GUI belongs to separately gated TERM-01G-C.
- `TerminalHandlerRemote`, Networking, Server/Client/Console communication,
  remote authorization/routing, multiple Console notification delivery,
  cross-device subscriptions and SCM belong **exclusively to consuming
  `remvibe_update_center` code**, not `remvibe_terminal`. Do not even add
  networking-specific types or optional dependencies to this package.
- The Console MAY use this package locally for its own PowerShell/CMD and
  supply a remote handler from Update Center to the SAME neutral widget.
  `selected` is per viewer/Console, NEVER global to Client's singleton.
  Each displayed pane has its own xterm display; terminal output is captured
  independently of widget selection.
- Keep terminal viewer registration distinct from controlling input and from
  destructive termination. Multiple read-only watchers of one local PTY
  should not clone the PTY or block its output when a watcher is slow.
- Terminal work state (busy/idle/unknown) and viewer attachment state are
  independent. Do not infer trustworthy command completion from output
  silence or apparent prompt text. Running detached processes must survive
  idle cleanup when activity is authoritative.
- **MUST NOT implement any NEW responsibility outside the documented
  scope without prior written plan AND explicit operator scope approval.**
  A proposed design, assistant suggestion, new branch or passing tests
  is not authorization. Proposal must name owner project, need, non-goals,
  dependencies, API, risks, validation and rollout. Implementation, merge,
  release and deployment require their own approval gates.
- No changes to frozen `nusretm/remvibe_update_center`, running services
  or their data without separate, explicit permission. No speculative
  Linux/macOS, remote transport, workflow engine, Installer or unrelated
  hardening in this checkpoint.

## Local checkout policy — mandatory (2026-11-21)

- **One project, one local checkout directory.** Work directly in `D:\Projects\remvibe_terminal` using normal Git feature branches. Do NOT create parallel Git worktrees, validation copies, per-task folders, or `*_verify` directories without explicit operator permission.
- A dirty `git status` is a reason to inspect the precise changed/untracked files, **not** a reason to generate a second checkout. Preserve local edits and Flutter-generated `example/windows/`, `example/.gitignore`, and `example/analysis_options.yaml` unless the operator explicitly authorizes cleanup.
- If branch switching is unsafe, stop and present a minimal safe same-directory strategy; do not create a worktree as an automatic fallback. Build/test output belongs in ignored build paths within the existing checkout.
- The previously created `D:\Projects\remvibe_terminal_term_01g_verify` was a policy deviation; it contains Windows verification artifacts. Remove it only after examining its status and verifying it is the intended disposable worktree. Do not delete the original checkout or any unreviewed local files.
