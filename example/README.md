# Windows Flutter terminal example

`example/` **is the Flutter project**. There is no additional nested example
application. The existing `windows_terminal_smoke.dart` remains unchanged.

The UI uses `xterm2`, only as an example dependency. The real shell is created
by the independent `remvibe_terminal` package over Windows ConPTY.

## Debug run

In Windows PowerShell:

```powershell
Set-Location D:\Projects\remvibe_terminal
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run_flutter_example_debug.ps1
```

The script compiles the native **Debug DLL**, generates the standard Flutter
`example/windows` runner if missing, resolves Flutter dependencies, runs
Flutter analysis, and launches the real desktop terminal in Debug mode.
No services, Fleet, Update Center or networking are involved.

The DLL can also be selected through
`--dart-define=RVTERM_DLL_PATH=<absolute DLL path>`.
When launched from `example/`, the app also searches the root
`build/windows/{Debug,Release}` directory.

## What to try in the window

1. PowerShell starts automatically. Type `Get-Location`, then `Get-Process`.
2. Resize the window and type more commands. Inspect screen reflow.
3. Run `ping -t 127.0.0.1`, interrupt with Ctrl+C, then type another command.
4. Close and Start a shell. Switch to CMD and run `ver` and `dir`.
5. Type `exit` and verify that the displayed exit code matches reality.
6. Close the window and check that no child shell remains.

Actual interactive use, not source review or headless smoke, is the goal.
This is not an operator acceptance declaration.

## TERM-01B — scrollback selection and safe resizing

- Drag-select after scrolling hundreds of lines into history. As you hold the
  button near the bottom edge, the viewport should keep auto-scrolling while
  the original selection start remains fixed on the same buffer line.
- Check copying from a selection spanning more rows than the window displays.
- Resize repeatedly by dragging the window narrow/wide/narrow. Latest target
  size wins: an in-flight resize does **not** discard later requests.
- Try resize while a command continuously prints output; keep the output
  visible and check the cursor and prompt after the command stops.
- The resize coordinator uses 120 ms request debounce, 250 ms output/cursor
  quiet settling, and a maximum 1 s settling window so continuous output
  cannot block the last requested size forever. These values are experimental
  heuristics, **not** a ConPTY redraw-complete callback.
- The old headless smoke is unaffected. The Debug script runs a focused
  resize-queue test before launching the UI.

The selection correction uses public xterm2 controller APIs, with no fork or
patched dependency. The resize coordinator lives only in the Flutter example
until interactive results justify moving it into the platform-independent
terminal package. These mechanisms are not yet approved for product use.

## TERM-01C — Right-click clipboard workflow

- **Right-click with an active selection:** copy exactly the selected buffer
  text to the system clipboard, clear selection, and scroll the viewport until
  the live terminal cursor is visible. The native PTY remains unchanged.
- **Right-click without a selection:** read plain text from the clipboard and
  show an explicit confirmation dialog with a preview. **Cancel** sends
  nothing. **Paste** starts the sender.
- Keyboard paste (e.g. Ctrl+V) uses the same confirmation workflow through
  xterm2's `onPaste` callback.
- Pasting sends one Unicode scalar at a time, UTF-8 encoded for ConPTY, with
  a 3 ms delay between characters and 35 ms after line endings. CRLF, LF and
  CR are converted to exactly one terminal Enter (`\r`). A multiline paste
  can execute multiple commands; read the preview before confirming.
- Input from the keyboard is not interleaved during paste. Closing/restarting
  the session stops an in-progress sender. The Ctrl+C toolbar button also
  cancels remaining queued characters before interrupting the shell.
- This sender is **example-only**. Neither the Dart native package nor
  Networking/Fleet/SCM acquires a clipboard or UI dependency.

Try selecting hundreds of historical lines and right-clicking; paste that
selection into Notepad to compare text. With no selection, right-click and
check that cancellation sends nothing, then test both a single command and
a multiline PowerShell snippet. Finally cancel a long paste or restart
the shell mid-paste and verify no characters reach the replacement session.

`example/windows_terminal_smoke.dart` remains an independent Dart CLI; it
uses `stdout.writeln`, not Flutter-only `debugPrint`. The Debug launcher now
uses strict `flutter analyze` and runs the resize and clipboard sender tests.
No acceptance is implied until the operator tries the real UI.

## TERM-01D — detachable multi-session widget

The GUI now uses the reusable RemVibeTerminalWidget from
example/lib/terminal_widget/. The terminal view knows only the
TerminalSessionBinding API, not the native DLL or networking. The example
implements that contract in local_terminal_session_provider.dart, backed by
the new TerminalSessionPool in the root Dart package.

Use New to open PowerShell/CMD sessions (up to four), Detach to leave a shell
running, Sessions to list/reattach surviving sessions, and Terminate to
explicitly kill the chosen shell. The widget's disposal detaches only.
The pool automatically expires detached idle sessions after 10 minutes;
server-marked running commands can be exempt, and unknown activity has a
30-minute fail-safe. The example cannot infer command activity, so newly
created local sessions initially use idle semantics.

This is NOT an actual remote-console integration. Console should copy the
five files in the terminal_widget directory and implement its existing
authorized Fleet create/list/attach/input/resize/output/close/cancel protocol
behind TerminalSessionProvider. See
docs/continuity/TERM_01D_WIDGET_SESSION_POOL.md.

