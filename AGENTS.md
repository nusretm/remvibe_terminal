# remvibe_terminal — working rules

**TERM-01A Windows ConPTY [in_progress — product acceptance NOT granted].** Follow `docs/continuity/CURRENT_TARGET.md`.

- Product First, Functionality First, Windows First.
- Target local checkout: `D:\Projects\remvibe_terminal`.
- This repository owns only native PTY/process lifecycle and public Dart callbacks/events. No Flutter UI, Fleet, Networking, RPC, auth, Server routing, installer/updater, GitHub or code signing.
- Frozen `nusretm/remvibe_update_center` reference: commit `be22cf19bf8310fc84c669dd2e9cf766c8b9d43d`, `docs/continuity/UC_REFERENCE_FREEZE_2026_11_20.md`. NEVER change old repo, services, configs, existing binaries or data.
- Windows native first. Linux/macOS implement later, without speculative abstractions.
- Preserve working ConPTY implementation. Make only specific correctness fixes.
- Windows smoke is diagnostic evidence only. Tests, local example and native build do not by themselves establish product acceptance; acceptance requires the actual RemVibe product's user-visible terminal feature working end-to-end and explicit operator approval.
- Record observed build/smoke evidence truthfully in `TERM_01_WINDOWS_CONPTY.md` and `CURRENT_TARGET.md`.
- Keep feature branch changes reviewable. Push, PR, merge, cleanup and deployment require separate operator permission. Do not modify existing SCM services.

- TERM-01A isolated test evidence (not acceptance): MSVC Release build PASS; native CTest 1/1; `dart analyze --fatal-infos` PASS; `dart test` 2/2; real Dart FFI → ConPTY → PowerShell smoke PASS (`Get-Location`, `Get-Process`, resize, two independent sessions, close-first/second-survives, natural exit 0, cancel and child cleanup). Baseline `main`: `5d7359a025ad3b24346c95b290bea439789522d0`. No CI acceptance implied.
- Other OS adapters, native asset packaging, remote integration and CI are not accepted by TERM-01A; real product integration is still outstanding; do not mark this checkpoint accepted or closed.
