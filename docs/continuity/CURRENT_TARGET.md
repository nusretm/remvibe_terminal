# Current target — remvibe_terminal

**TERM-01A — Windows x64 ConPTY [in_progress — no product acceptance]**

Local development root: `D:\Projects\remvibe_terminal`.

## Implemented and isolated-tested Windows scope

- MSVC Release x64 builds the native ConPTY DLL.
- Dart public API creates real PowerShell PTY sessions with raw output, input, resize, interrupt API, natural exit, cancel/close.
- Two sessions operate independently and close/cleanup does not leak child processes.
- Real native CTest, Dart analysis/tests and Dart → FFI → ConPTY → PowerShell smoke PASS.

## Operator-provided standalone test evidence (2026-11-20; not acceptance)

- Initial source commit pushed to `main`: `5d7359a025ad3b24346c95b290bea439789522d0`.
- `main` remote HEAD matched and local checkout was clean immediately after push (`## main...origin/main`).
- MSVC compiler 19.44.35211.0, Windows SDK 10.0.26100.0, VS 2022 Release build: PASS.
- Native CTest: 1/1 PASS.
- `dart pub get`: PASS; `dart analyze --fatal-infos`: no issues; `dart test`: 2/2 PASS.
- `tool/windows_acceptance.ps1`: `Get-Location PASS`, `Get-Process PASS`, `resize PASS`, `two independent terminals PASS`, `close-first/second-survives PASS`, `natural exit code=0 PASS`, `cancel and cleanup PASS`, and `TERM-01A WINDOWS REAL CONPTY ACCEPTANCE PASS`.
- These are actual local Windows operator console results, **not** GitHub CI or independent host verification.

## Boundaries and next step

- TERM-01A remains in_progress. Passing the standalone ConPTY smoke does not mean the real RemVibe product is working. Before any acceptance, integrate and use the terminal through the actual Server/Client/Console flow, verify observable user functionality, and obtain explicit operator approval. Do not infer Linux/macOS, standard non-PTY process, native asset packaging or release acceptance.
- This documentation update is separate from the initial source code commit; it does not modify SCM services or the frozen legacy repository.
- Next work must target real product use, not more smoke-only acceptance paperwork. The concrete integration scope should be established from actual consumer entrypoints.

Read-only legacy reference: `nusretm/remvibe_update_center` at `be22cf19bf8310fc84c669dd2e9cf766c8b9d43d`.
