# TERM-02A — Real Linux PTY backend (native Bash / Ubuntu)

Status (2026-11-21): **Real Linux PTY supervisor implemented; operator Ubuntu Dart analyzer and 30/30 tests PASS.** Actual multi-PTY live smoke launched Bash and observed output but first-output check timed out; ANSI-aware test correction committed, rerun PENDING. Real Ubuntu Flutter GUI and operator acceptance still PENDING.

## Intent and authorization

Operator explicitly requested real Linux PTY capability and live testing after
successful Windows real ConPTY and Ubuntu Flutter UI-mock TERM-01G-C acceptance.
This authorization covers **terminal-core native PTY mechanics only**, not
networking, Fleet, remote adapters, Update Center, SCM services, installer
features, speculative platforms or unrelated hardening.

Owner: `nusretm/remvibe_terminal`. The Flutter viewer remains separately
owned by `nusretm/remvibe_terminal_flutter` and receives only a
`TerminalHandler`, no platform-specific process logic.

Branches and checkout policy:
- Core branch: `feature/term-02a-linux-pty`, branched from accepted
  `feature/term-01g-local-multi-handler` at
  `aca8f283fb58be4ce399e851c0fab7f214869687`.
- Flutter integration: a **separate** feature branch based on the accepted
  Flutter viewer branch; do not change its Windows-accepted implementation.
- Only one local checkout per repo. No `*_verify` or extra Git worktree.
- No main merge, release, publication or cleanup without operator approval.

## Technical scope

- Native Linux backend uses openpty, a tiny native child supervisor and a real
  Bash/sh grandchild session/controlling terminal, PTY master read/write,
  resize, Ctrl+C, EOF and process-group teardown. The supervisor alone
  calls waitpid on the real PTY shell and delivers its natural exit status
  over a local SOCK_SEQPACKET socket. This avoids a race with the Dart VM's
  unrelated SIGCHLD/waitpid(-1) child reaper. The Dart process always sees
  the true shell PID (not the helper PID). This supervisor is internal to
  the native terminal engine, never a service or remote component.
- C ABI `native/include/remvibe_terminal_linux.h` and C++
  `native/src/platform/linux/remvibe_terminal_linux.cpp` are isolated from
  Windows ConPTY. Native calls are synchronous and serialized by the Dart
  owning isolate. PTY master and status socket are nonblocking in the parent;
  a tiny helper blocks only in its own process until the shell exits.
- `lib/src/linux/linux_pty.dart` implements the same `TerminalBackend` /
  `TerminalHandle` interface as Windows and supplies typed native errors.
  UTF-8 command lines are executed through POSIX `/bin/sh -c`; an interactive
  Bash session is requested by the application with
  `exec /bin/bash --noprofile --norc -i`. The `exec` preserves the real
  Bash PID as the reported PTY child PID.
- `RemVibeTerminal.currentPlatform()` routes Linux to
  `RemVibeTerminal.linux()`. Windows remains exactly the existing ConPTY path.
- `hook/build.dart` compiles the Linux native Code Asset and links libutil.
  Linux and Windows sources are never compiled or linked into each other's
  platform artifacts. Targeted Linux x64 and ARM64, with x64 Ubuntu first.
- Existing `TerminalSessionService`, bounded replay, detach/reattach,
  multi-handler observation and `TerminalHandlerLocal` stay shared and
  unchanged. Viewer unregistration never stops an OS process.
- No networking, auth, cross-device routing, RemoteHandler, SQLite, workflow
  engine or Linux service daemon implementation.
- Kernel PTY buffering is bounded; `maxBufferBytes` continues to bound
  the Dart session's process buffer/replay logic. Linux's native reader uses
  a nonblocking master fd, not a separate unbounded native ring.

## Evidence already obtained

A compiled C++ shared library using the Linux PTY ABI was tested directly on a
Linux host by calling the exported native functions. Native test passed:
- real forkpty Bash process created, output read;
- `stty size` reflected a native resize to **39 rows × 101 columns**;
- Bash `$$` matched the native-reported PID;
- natural `exit 7` returned exit code **7**;
- native session cleanup completed.
C++ also compiled with `g++ -std=c++17 -Wall -Wextra -Werror -fPIC`
and the explicit header/link option `-lutil`.

This is only **native C++ smoke evidence**. It is NOT yet evidence that the
new Dart `@Native` declarations, Dart hook, Flutter Linux application or
interactive Ubuntu GUI have passed. Source tests and a dedicated full Linux
smoke runner have been added but not executed on the operator's Ubuntu host.

## Operator Linux acceptance gate

1. Core `dart pub get`, `dart analyze --fatal-infos` and `dart test`
   succeed on the actual Ubuntu machine, including real Bash shell tests.
2. `dart run tool/term_02a_linux_live_smoke.dart` succeeds: two PTYs, two
   watchers of one PTY, independent second PTY, read/write, Ctrl+C,
   resize/stty, detached output replay, same-PID reattach, unregister
   isolation and natural exit code.
3. Flutter Linux feature integration uses the newly built Linux core asset,
   not the old UI-mock handler. Two real Bash PTYs launch in adjacent panes.
4. Mirror one real Bash session to two viewer panes; detach/reattach the
   controller without replacing shell PID. Validate real input/output,
   selection/copy, paste confirmation and resize on Ubuntu.
5. Windows regression: do not change accepted native ConPTY/Windows viewer
   behavior; Windows package checks and real Debug smoke are required before
   merge if Windows-relevant source changed.
6. Explicit operator acceptance separately required. No automatic main
   merge, release, install or cleanup.

## Backout

The existing accepted Windows and UI-mock branches remain untouched.
If Linux acceptance fails, fix the new feature branch only or abandon that
branch. Preserve operator local files and generated platform runners.

### Actual Ubuntu Dart gate — first operator run (2026-11-21)

- Operator's existing single Ubuntu checkout at `/home/remvibe-admin/development/projects/remvibe_terminal` was on `feature/term-02a-linux-pty`, HEAD `c25620720276af3a9a25baf23172d4dbf235478f`, **clean Git status**. No new worktree or clone was used.
- Initial terminal window closed after a shell block using `set -e`; this was not evidence of PTY crash. Running `bash tool/verify_linux.sh > /tmp/remvibe-term-02a-linux.log 2>&1` from an interactive shell without `set -e` correctly preserved the window and captured an exit code.
- `dart pub get`: **PASS** (root + example). `dart analyze --fatal-infos`: **PASS, No issues found**. `dart test`: **29 passed, 1 failed**. The one failing test, `Linux native PTY starts actual shell, emits output and exits`, did launch a **real Linux interactive shell** and successfully executed `echo RVTERM_LINUX_TEST_SUCCESS`; captured output was `echo RVTERM_LINUX_TEST_SUCCESS\n$ RVTERM_LINUX_TEST_SUCCESS\n$` (presentation normalized). Failure was only the test's overly strict exact `\r\nRVTERM_LINUX_TEST_SUCCESS\r\n` expectation, which excluded LF-only and prompt-prefixed output.
- Test adjusted in commit `4c88512d2b035593ae3eb10727c544d4e7aaa827` to recognize an actual **complete executed output line**, optionally preceded by a Bash prompt, with either LF or CRLF. The real multi-handler smoke also used overly strict Windows-style line boundaries; commit `1cd2c83230503ff56f66fc7f05b4243426ed0ad0` aligns its output checks and avoids counting echoed commands as executed output.
- **Both reruns PENDING**: Do not report `dart test` PASS or full native multi-handler smoke PASS until the operator executes the new HEAD. The Flutter Linux real Bash GUI gate is also still PENDING.
- No production/native backend code was modified by these two fixes; only Dart test/smoke assertions changed. Preserve accepted Windows ConPTY and Flutter viewer branches; no merge, deployment, publication, SCM or Update Center changes.


### Ubuntu verification retry — analyzer source regression and correction (2026-11-21)

- After the operator fast-forwarded from `c256207` to `44b055b`, the second
  `bash tool/verify_linux.sh` run exited **3 at Dart analyzer**, before tests.
  Output: **88 analyzer issues** in
  `test/linux_native_pty_test.dart` and
  `tool/term_02a_linux_live_smoke.dart`.
- Inspection found the previous repair had split regex string literals across
  Dart lines and duplicated fragments of both functions. These are **test
  source syntax errors**, not evidence of a Linux native PTY runtime failure.
- Rebuilt both entire test/smoke files from their intact
  `c25620720276af3a9a25baf23172d4dbf235478f` baseline, retaining only
  a small `_hasPrintedLine` helper. It accepts LF/CRLF and a prompt directly
  preceding the actual result line, but not echoed commands.
- Code repairs: `be9a6d49d5bfb295982b7b49130ddb6bfce89821` and
  `489082dd4b5b6408a7211219cc029b34a512b012`.
  Remote source reread confirmed no broken regex/standalone comma fragments.
- **RERUN STILL PENDING** on Ubuntu. Do not mark Dart analyzer, test suite,
  two-PTY smoke or Flutter GUI PASS based on these commits alone.
- Change scope remains restricted to tests, smoke checks and continuity;
  no native Linux/Windows PTY runtime code changed in this correction.

### Actual Ubuntu exit-code failure and native correction (2026-11-21)

- Operator's third Ubuntu run at 3f8efacc7920c0ba1c3517988e524272369b09e2:
  dependencies PASS, dart analyze --fatal-infos PASS, dart test **29 PASS /
  1 FAIL**. The real Linux PTY test opened a working shell and observed its
  command output, but after exit 9, Dart session.exitCode completed with null.
  The live two-PTY smoke was **not reached**.
- Root cause: the native backend originally called waitpid directly on a
  PTY child whose parent was the Dart VM. The Dart VM also has a generic
  SIGCHLD child reaper, which can reap a native FFI child first. The direct
  native waitpid then loses its exit status and Dart returns null after the
  native polling error.
- New design: openpty in Dart's native process; fork a tiny native helper
  which spawns the real shell in its own PTY session, retains exclusive child
  ownership, blocks in waitpid, and sends the child's exit status to the main
  process over a local SOCK_SEQPACKET socket. The Dart-visible PID remains
  the **actual Bash PID**, not the helper PID. Existing Dart FFI ABI,
  TerminalHandler service, Windows backend and Flutter UI are unchanged.
- Independent Linux g++ -Wall -Wextra -Werror shared-library build passed.
  Live native smoke opened **two real Bash PTYs**, validated different PIDs,
  Bash output and child $$, resizing via stty size, Ctrl+C and natural
  **exit 9 / exit 7**. A deliberate independent waitpid(-1) reaper thread
  consumed both supervisors' statuses while the native status channel still
  delivered the correct Bash codes. This proves the native process-parent
  isolation under an adversarial reaper; it is **not** a substitute for the
  operator's Ubuntu Dart Native Assets run.
- Native fix commit d670348a1043e2a41c7bb507ce012c4c19f166ac;
  test diagnostic commit 698bcf3310c184ba0bee4e3a2ccca75217a80147.
  Ubuntu root Dart analyzer, all Dart tests, dedicated multi-PTY smoke,
  Flutter Linux real Bash window and operator acceptance remain **PENDING**.
  No main merge, release, cleanup or consumer/SCM modifications.


### Fourth Ubuntu gate — complete Dart pass, smoke first-output mismatch (2026-11-21)

- Operator fast-forwarded clean single checkout to
  `7073e83a8379d590a58c7353b2b2e448366fa042`.
- `dart pub get`: **PASS**, `dart analyze --fatal-infos`: **PASS**,
  `dart test`: **30/30 PASS**. This proves that the new native supervisor
  delivers a non-null real shell exit code for the basic Dart test.
  The Dart build-hook output also mentioned
  `No Visual Studio installation found...` on Ubuntu, but it was
  non-fatal; it did not stop the successful test suite.
- `dart run tool/term_02a_linux_live_smoke.dart`: **FAIL** on the first
  `_Capture.waitFor(RVTERM_REAL_LINUX_A)` after 8 seconds.
  The diagnostic tail showed the *actual executed Bash output*:
  `bash-5.3$ printf "RVTERM_REAL_LINUX_A\\n"`,
  `RVTERM_REAL_LINUX_A`, then `bash-5.3$`.
  The stream successfully delivered actual PTY output; output matching
  failed, plausibly because nonprinting Bash VT sequences are present
  around the visible result. The failure is **not evidence of missing
  Bash output**, and later multi-handler/resize/reattach checks were
  not reached.
- Removed the brittle inline smoke matcher and added
  `tool/linux_pty_smoke_output.dart` with ANSI CSI/OSC stripping,
  CR/LF normalization, whole-result-line matching, and control-character
  diagnostics for any future timeout. The matcher does **not** accept
  echoed `printf`/`echo` input by itself as proof of execution.
- Added `test/linux_pty_smoke_output_test.dart` covering the exact Bash
  transcript shape, bracketed-paste ANSI controls, false positives and
  diagnostics. These newly committed tests and the full multi-handler
  smoke are **PENDING operator Ubuntu rerun**. Do not mark TERM-02A
  feature acceptance until all checks and live Ubuntu UI pass.
- Windows accepted ConPTY runtime and Flutter view remain untouched.
  No merge/release/cleanup, Update Center, Networking or SCM changes.

