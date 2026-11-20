# remvibe_terminal — working rules

**Active checkpoint: TERM-01D reusable terminal widget and multi-session registry [in_progress; product acceptance NOT granted].** Follow `docs/continuity/CURRENT_TARGET.md`.

- Product First, Functionality First, Windows First.
- Local target checkout: `D:\Projects\remvibe_terminal`.
- Root package owns independent native PTY/process lifecycle, public Dart stream/events, and a Flutter-free TerminalSessionPool for local Client processes. Keep Flutter and xterm2 out of root dependencies.
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
