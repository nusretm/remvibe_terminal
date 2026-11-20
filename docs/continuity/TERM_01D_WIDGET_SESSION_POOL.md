# Reusable Flutter terminal widget and host session pool

Status: source implementation in progress, Windows interactive verification pending.

## Copy into Update Center Console

Copy **all five Dart files** from example/lib/terminal_widget/:

- remvibe_terminal_widget.dart
- terminal_session_api.dart
- stable_scrollback_terminal_view.dart
- terminal_resize_coordinator.dart
- terminal_clipboard_paste.dart

Add xterm2 to the Console Flutter dependencies. Do NOT copy
example/lib/local_terminal_session_provider.dart: that file is only the
local Windows demonstration adapter, not the Console's remote transport.
Do not add a ConPTY DLL to the Console because it only renders and routes
terminal messages.

The widget's public construction API:

    RemVibeTerminalWidget(
      key: ValueKey(attachmentIdentity),
      session: attachedSessionBinding,
      initialColumns: 100,
      initialRows: 30,
    )

The binding and provider interfaces are defined in terminal_session_api.dart:

- TerminalSessionProvider.create(profile, columns, rows)
- TerminalSessionProvider.listSessions()
- TerminalSessionProvider.attach(sessionId, afterSequence)
- TerminalSessionProvider.terminate(sessionId)
- TerminalSessionBinding.sessionId / label
- TerminalSessionBinding.output (ordered frames with sequence and raw bytes)
- TerminalSessionBinding.exitCode
- TerminalSessionBinding.input / resize / interrupt / detach

**Detach does not terminate the process.** Closing a tab or disposing the
widget detaches the current view. Explicit terminate is a separate provider
operation. Give each new attachment a different widget key.

The widget retains the verified example selection anchor, right-click
copy/scroll-to-cursor, confirmed Unicode character-by-character paste, and
latest-wins resize. Resize supports async transport acknowledgment: the last
pending size is sent only after the previous request returns and settles.
A missing ConPTY redraw-complete callback is still handled heuristically.

## Mapping to the earlier Fleet remote-terminal contract

The archived implementation already has these typed operations:

| Widget/provider API | Server/Client remote-terminal action |
| --- | --- |
| create | create |
| listSessions | listSessions, device-scoped and authorized |
| attach | attach using full RemoteTerminalSessionRef |
| binding.input | input with monotonically increasing control sequence |
| binding.resize | resize and wait for routed ACK |
| binding.output | output notifications, preserve their sequence and bytes |
| binding.detach | server-side close = non-destructive detach |
| provider.terminate | cancel = destructive termination |
| binding.interrupt | Ctrl+C input, **not** the destructive cancel command |
| binding.exitCode | exit notification |

Do not infer authorization from a session ID alone. The Console adapter must
keep the Server-issued terminalSessionId + serverInstanceId +
sessionGeneration reference, owner principal, deviceUuid, authenticated
connection and request/sequence tracking under existing Update Center
Server/Client/Console services. These concerns are deliberately absent from
the portable widget. The old repository stays frozen.

**This branch does not provide a real Networking adapter or remote
integration.** It defines the API that adapter must implement, and tests the
local in-process path. Routing and bounded output/ACK behavior remain the
responsibility of the Update Center application.

## TerminalSessionPool (native host, no Flutter)

lib/src/session/terminal_session_pool.dart owns local ConPTY processes for a
single Client lifetime. It has a local factory with an existing
RemVibeTerminal engine and a testable process factory.

- 4 concurrent sessions by default.
- Detached IDLE sessions expire after 10 minutes; detached UNKNOWN command
  activity expires after 30 minutes; detached RUNNING commands are exempt.
  These values mirror the earlier Fleet policy. The host exposes
  setCommandActivity(sessionId, state) for the authoritative application.
  Attach, detach, input, resize and command activity transitions refresh
  the timestamp. Output alone never extends activity.
- listSessions returns only live sessions, with identity, timestamps,
  attached/detached status, and output sequence/overflow metadata.
- attach creates one viewer stream with bounded retained output replay.
  Call attach(..., afterSequence: n) to suppress duplicates when a viewer
  has already seen sequence n. At most one viewer per PTY.
- 64 KiB maximum retained raw output by default. A history-overflow flag
  means replay may be incomplete and cannot reconstruct a perfect terminal
  screen after a long disconnect. A later product checkpoint may need a
  full screen snapshot or a larger protocol-specific replay strategy.
- Natural exit, explicit termination, expiry and service shutdown all
  release the native process and remove it from discovery.
- In-memory only. Client process restart destroys its sessions.

The prior Fleet Server session service distinguished idle/running/unknown
command activity and permitted detached running commands to survive.
The new pool preserves those policy categories but cannot automatically
infer whether a shell is running a command, so its initial state is IDLE.
The authoritative application/Server must update the host through
setCommandActivity; output alone cannot reliably establish command activity.
This pool is **not** a replacement for the Server's authorization, ownership,
capability, device reconnect or expiry logic.

## Real Windows Debug verification

Run from D:/Projects/remvibe_terminal:

    git fetch origin feature/term-01d-widget-session-pool
    git switch --track origin/feature/term-01d-widget-session-pool
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run_flutter_example_debug.ps1

Before launching the interactive Flutter window, the script checks:

- Native Windows ConPTY Debug DLL build
- Root Dart analyze and host session pool tests
- Flutter analyzer and existing resize/clipboard test suite

In the GUI:

1. Create PowerShell and CMD sessions (up to 4).
2. Detach a session without killing the process, select it from Sessions
   and type another command. Check the retained output.
3. Open a second session, detach/reattach them in either order and verify
   they do not share PIDs or commands.
4. Long scrollback selection and right-click copy; right-click with no
   selection to paste with explicit confirmation.
5. Resize rapidly, including during continuous output, and check cursor.
6. Terminate one session and confirm the other remains alive.
7. For idle expiry, use a short configured timeout in a test, or verify the
   default 10-minute detached expiry. The expired session must disappear.
8. Exit a shell naturally; it must disappear from discovery.

All the above are pending **real** Windows verification of the new widget
and session registry. Technical tests cannot by themselves constitute
product acceptance.
