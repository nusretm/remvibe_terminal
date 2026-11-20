# remvibe_terminal — working rules

**Active checkpoint: TERM-01F TerminalSessionService rename + singleton/session API [in_progress; product acceptance NOT granted].** Follow `docs/continuity/CURRENT_TARGET.md`.

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
- No actual Console networking adapter has been implemented yet. Widget source/API and the local multi-session example require real Windows verification before any acceptance.

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
- TERM-01D widget/session-pool tests and interactive acceptance remain
  separate open gates. Do not merge, deploy, clean up or touch frozen
  Update Center services without explicit operator approval.

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
- TERM-01F Windows analyze/tests/interactive verification remain pending;
  no release, merge, Console networking, SCM or deployment work authorized.
