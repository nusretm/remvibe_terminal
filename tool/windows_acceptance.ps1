# No admin rights, services, registry, installation, or network-related changes.
# Run in an ordinary Windows PowerShell from D:\Projects\remvibe_terminal.
param([string]$Generator = 'Visual Studio 17 2022')
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Invoke-Checked([string]$Stage, [scriptblock]$Action) {
    Write-Host "=== $Stage ==="
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "$Stage failed with exit code $LASTEXITCODE" }
}

Invoke-Checked 'CMake configure' { cmake -S . -B build/windows -G $Generator -A x64 -DRVTERM_BUILD_TESTS=ON }
Invoke-Checked 'MSVC Release build' { cmake --build build/windows --config Release }
Invoke-Checked 'Native CTest' { ctest --test-dir build/windows -C Release --output-on-failure }
Invoke-Checked 'Dart dependencies' { dart pub get }
Invoke-Checked 'Dart analyzer' { dart analyze --fatal-infos }
Invoke-Checked 'Dart tests' { dart test }
$dll = (Resolve-Path 'build/windows/Release/remvibe_terminal_windows.dll').Path
Invoke-Checked 'Real Windows PowerShell ConPTY FFI smoke' {
    dart run example/windows_terminal_smoke.dart --dll $dll
}
Write-Host 'TERM-01A Windows local acceptance checks completed; review each output before recording PASS.'
