# remvibe_terminal — working rules

**Active checkpoint: TERM-01A Windows ConPTY [in_progress].** Follow `docs/continuity/CURRENT_TARGET.md`.

- Product First, Functionality First, Windows First.
- Target local checkout: `D:\Projects\remvibe_terminal`.
- This repository owns only native PTY/process lifecycle and public Dart callbacks/events. No Flutter UI, Fleet, Networking, RPC, auth, Server routing, installer/updater, GitHub or code signing.
- Frozen `nusretm/remvibe_update_center` reference: commit `be22cf19bf8310fc84c669dd2e9cf766c8b9d43d`, `docs/continuity/UC_REFERENCE_FREEZE_2026_11_20.md`. NEVER change old repo, services, configs, existing binaries or data.
- Windows native first. Linux/macOS implement later, without speculative abstractions.
- Preserve working ConPTY implementation. Make only specific correctness fixes.
- Real Windows smoke is required for acceptance; passing static tests alone is insufficient.
- Record observed build/smoke evidence truthfully in `TERM_01_WINDOWS_CONPTY.md` and `CURRENT_TARGET.md`.
- Keep feature branch changes reviewable. Push, PR, merge, cleanup and deployment require separate operator permission. Do not modify existing SCM services.
