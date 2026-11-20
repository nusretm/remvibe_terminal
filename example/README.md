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
