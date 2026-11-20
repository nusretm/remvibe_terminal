# remvibe_terminal — working rules

**Active checkpoint: TERM-01B Flutter Windows example [in_progress; product acceptance NOT granted].** Follow `docs/continuity/CURRENT_TARGET.md`.

- Product First, Functionality First, Windows First.
- Local target checkout: `D:\Projects\remvibe_terminal`.
- Root package owns independent native PTY/process lifecycle and public Dart stream/events. Keep Flutter and xterm2 out of root dependencies.
- Flutter demo is directly under `example/`; preserve `example/windows_terminal_smoke.dart`. Do not add a nested Flutter application directory.
- Frozen `nusretm/remvibe_update_center` reference: `be22cf19bf8310fc84c669dd2e9cf766c8b9d43d`; never change it or live SCM services, binaries or data.
- Windows x64 first. No speculative Linux/macOS, RPC, Fleet/Networking or unrelated security layers.
- Native tests and local smoke are technical evidence only. Require the actual Flutter terminal experience running in Windows Debug and explicit operator acceptance; do not mark accepted based on tests.
- Feature push does not authorize PR merge, release, deployment or cleanup.
