# TERM-02A — Real Linux PTY backend (native Bash / Ubuntu)

Status (2026-11-21): **SOURCE IMPLEMENTED on dedicated branch; native C++ direct Linux smoke PASS; Dart Native Assets, real Ubuntu Dart/Flutter and operator acceptance PENDING.**

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

- Native Linux backend owns a real forkpty PTY master + Bash/sh child process,
  controlling terminal, parent PID, input, output, window size, Ctrl+C through
  PTY line discipline, waitpid exit status, EOF and process-group teardown.
- C ABI `native/include/remvibe_terminal_linux.h` and C++
  `native/src/platform/linux/remvibe_terminal_linux.cpp` are isolated from
  Windows ConPTY. Native calls are synchronous and serialized by the Dart
  owning isolate. PTY master is nonblocking for bounded polling.
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
