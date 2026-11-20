# TERM-01E — Dart Native Assets / Windows CLI distribution

Status: **Windows CLI technical verification PASS; product/release acceptance pending**. Operator confirmed automatic Native Assets and ordered multi-path/directory loading with real bundled PowerShell/ConPTY.

## Scope

When `remvibe_terminal` is added to a Dart CLI client dependency graph,
`dart build cli` must compile the Windows ConPTY DLL and bundle it beside
the CLI under `bundle/lib`, without manual copy or an executable-relative
library-path workaround. This is about packaging, **not a new terminal
engine or Update Center service integration**.

Frozen reference repository `nusretm/remvibe_update_center` at
`be22cf19bf8310fc84c669dd2e9cf766c8b9d43d` remains untouched.
No SCM service mutations, release, merge or deployment are permitted as
part of this checkpoint.

## Implementation contract

- Dart SDK floor: >=3.10.0, required for `dart build cli` and hooks.
- Hook dependencies: `hooks`, `code_assets`, `native_toolchain_c` in
  normal `dependencies` (not `dev_dependencies`).
- `hook/build.dart`: for **Windows x64 only**, uses `CBuilder.library`
  to compile the same `native/src/platform/windows/remvibe_terminal_windows.cpp`
  source, with the existing public include directory, C++17, MSVC exceptions,
  and `kernel32` link dependency; requests a dynamically bundled code asset.
  The native C++ source, native ABI and CMake setup are unchanged.
- Code asset ID: `package:remvibe_terminal/src/windows/windows_conpty.dart`;
  hook `assetName` and Dart `@Native(...assetId: ...)` bindings must match.
  All eight existing exported symbols are mapped.
- Default `RemVibeTerminal.currentPlatform()` and `.windows()` use
  `@Native` binding via the code asset. They no longer construct the DLL
  path from `Platform.resolvedExecutable`.
- Explicit `libraryPath:` continues to use `DynamicLibrary.open` and
  supports existing Flutter Debug and standalone headless tests.
- `DynamicLibrary.codeAsset` is deliberately not used because the
  required SDK support is newer than the Flutter runtime currently in use.
- Other OSes generate no Windows DLL. Linux/macOS PTY adapters are still
  unimplemented; this feature must not pretend to support those systems.

## Follow-up — multiple native DLL candidates

After the first successful real Windows Native Assets run, the operator
requested Networking-style multiple library lookup locations for different
installation layouts. The public `RemVibeTerminal.windows()` and
`currentPlatform()` factories now support:

- `libraryPath: String?` — backward-compatible optional first file path.
- `libraryPaths: List<String>` — ordered additional *exact file paths*.
- `searchDirectories: List<String>` — ordered folders expanded using
  `remvibe_terminal_windows.dll` as the filename.

They are tried in that sequence, with absolute-path deduplication.
A missing, unloadable or symbol-incompatible DLL is skipped in favor of the
next candidate. If a manually configured set is exhausted, the caller gets
`TerminalNativeLibraryLoadException` with all attempted paths and failures;
we do not silently switch to an unintended embedded DLL. If no manual
candidate is supplied, the original automatic Native Asset loading path
continues to operate.

The isolated CLI verifier now runs three real sessions after a single
`dart build cli` build: unchanged automatic Native Assets mode, manual
file candidates (including a deliberately invalid DLL), and multiple
directory candidates. Unit tests cover ordering, deduplication and explicit
failure reporting. The new path lookup passed its operator Windows verification: six focused Dart unit tests and real bundled ConPTY sessions.

## Proof and acceptance

From the Windows checkout `D:\Projects\remvibe_terminal` on this branch:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\tool\verify_native_assets_cli.ps1
```

The isolated consumer is staged inside ignored
`build/native_assets_cli_consumer`. Its only terminal dependency is a
relative path to this package. The script does the following:

1. `dart pub get` in the isolated consumer.
2. `dart build cli --output <release> --target bin/main.dart`.
3. Verifies the bundle's `bin/main.exe` and
   `lib/remvibe_terminal_windows.dll` both exist.
4. Executes the compiled CLI with **no libraryPath argument and no
   manually copied DLL**.
5. Requires an actual PowerShell PTY command to produce its marker and
   exit successfully; successful output includes
   `REMVIBE_TERMINAL_CLI_NATIVE_ASSET_PASS` and
   `TERM-01E WINDOWS CLI NATIVE ASSETS BUNDLE PASS`.

The initial operator Windows run already produced both
`REMVIBE_TERMINAL_CLI_NATIVE_ASSET_PASS` and
`TERM-01E WINDOWS CLI NATIVE ASSETS BUNDLE PASS`. It compiled the DLL
with MSVC, placed it under `bundle/lib` and ran actual PowerShell/ConPTY
from the generated executable. This confirms the original Native Assets
checkpoint's technical behavior, but **not** the new multi-path behavior.

The rerun must also show:
`REMVIBE_TERMINAL_MULTI_PATH_FALLBACK_PASS`,
`REMVIBE_TERMINAL_SEARCH_DIRECTORIES_PASS` and
`TERM-01E WINDOWS NATIVE LIBRARY MULTI-PATH PASS`.

If any assertion fails, keep the checkpoint in_progress and diagnose the
actual Windows output. A successful source commit or static review alone
is not operator acceptance.

Also run the existing Flutter example Debug and standalone native smoke
after packaging acceptance if a regression is suspected. No explicit
merge or cleanup until operator approval.

## Not part of TERM-01E

- No change to the portable Flutter widget or multi-session APIs.
- No real remote Console/Server/Client adapter, signing, promotion, or
  Windows SCM service installation/restart.
- No Linux/macOS native implementations.
- No standalone DLL release upload.

## Windows operator verification — 2026-11-21

On `feature/term-01e-library-search-paths`, the operator ran
`tool/verify_native_assets_cli.ps1`. Observed:

- DLL resolution Dart tests: **6/6 PASS**.
- `dart build cli`: **PASS**, generated `bundle/bin/main.exe`.
- `bundle/lib/remvibe_terminal_windows.dll` included automatically (no manual copy).
- `REMVIBE_TERMINAL_CLI_NATIVE_ASSET_PASS` — **PASS**.
- `REMVIBE_TERMINAL_MULTI_PATH_FALLBACK_PASS` — **PASS** (missing/bad/valid candidates).
- `REMVIBE_TERMINAL_SEARCH_DIRECTORIES_PASS` — **PASS**.
- `TERM-01E WINDOWS CLI NATIVE ASSETS BUNDLE PASS` — **PASS**.
- `TERM-01E WINDOWS NATIVE LIBRARY MULTI-PATH PASS` — **PASS**.

TERM-01E Windows CLI **technical verification** passed. This does not
grant product acceptance, release, merge or deployment permission.
TERM-01D Flutter multi-session widget interactive acceptance remains open.
