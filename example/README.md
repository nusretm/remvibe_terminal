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
