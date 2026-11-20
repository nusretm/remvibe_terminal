# Standalone Windows ConPTY DLL + Flutter desktop Debug; no SCM changes.
param([string]$Generator = 'Visual Studio 17 2022')
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$example = Join-Path $repo 'example'
$build = Join-Path $repo 'build\windows'
$dll = Join-Path $build 'Debug\remvibe_terminal_windows.dll'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter SDK not found on PATH.'
}

Push-Location $repo
try {
    cmake -S . -B $build -G $Generator -A x64 -DRVTERM_BUILD_TESTS=ON
    if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed.' }
    cmake --build $build --config Debug --target remvibe_terminal_windows
    if ($LASTEXITCODE -ne 0) { throw 'Native Debug DLL build failed.' }
    if (-not (Test-Path $dll)) { throw "Native DLL missing: $dll" }
    # The Client-side TerminalSessionService is independent of Windows native FFI,
    # so its lifecycle tests can run before the Flutter UI starts.
    dart pub get
    if ($LASTEXITCODE -ne 0) { throw 'Root Dart pub get failed.' }
    dart analyze --fatal-infos
    if ($LASTEXITCODE -ne 0) { throw 'Root Dart analyze failed.' }
    dart test
    if ($LASTEXITCODE -ne 0) { throw 'Root terminal Dart tests failed.' }
    dart run tool/term_01g_windows_multi_handler_smoke.dart --dll $dll
    if ($LASTEXITCODE -ne 0) { throw 'TERM-01G real ConPTY multi-handler smoke failed.' }
} finally {
    Pop-Location
}

Push-Location $example
try {
    # Flutter generates its standard Windows runner directly in example/.
    # Does NOT create another nested sample application.
    if (-not (Test-Path '.\windows\CMakeLists.txt')) {
        flutter create --empty --platforms=windows --project-name remvibe_terminal_example --no-pub .
        if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows runner generation failed.' }
    }
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter pub get failed.' }
    # CLI smoke now uses stdout.writeln; analyzer infos should also fail again.
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analyze failed.' }
    flutter test test/terminal_resize_coordinator_test.dart test/terminal_clipboard_paste_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Resize coordinator tests failed.' }

    Write-Host '=== Starting Flutter Windows Debug and live ConPTY terminal ==='
    Write-Host "DLL: $dll"
    flutter run -d windows --debug "--dart-define=RVTERM_DLL_PATH=$dll"
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows Debug run failed.' }
} finally {
    Pop-Location
}
