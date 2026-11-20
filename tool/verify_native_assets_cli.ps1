# Tests the real Dart CLI bundle, WITHOUT manually compiling/copying a DLL.
# This script touches only this repository's ignored build/ directory.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$consumer = Join-Path $repo 'build\native_assets_cli_consumer'
$source = Join-Path $repo 'tool\native_assets_cli_smoke.dart'
$consumerBin = Join-Path $consumer 'bin'
$bundleRoot = Join-Path $consumer 'release'
$bundle = Join-Path $bundleRoot 'bundle'
$exe = Join-Path $bundle 'bin\main.exe'
$dll = Join-Path $bundle 'lib\remvibe_terminal_windows.dll'

if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
    throw 'This real ConPTY build requires Windows.'
}
if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
    throw 'Dart SDK is not available on PATH.'
}

Write-Host '=== Verify ordered DLL path resolution (Dart unit tests) ==='
Push-Location $repo
try {
    dart pub get
    if ($LASTEXITCODE -ne 0) { throw 'Root Dart pub get failed.' }
    dart test test/terminal_native_library_paths_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Terminal DLL candidate tests failed.' }
} finally {
    Pop-Location
}

New-Item -ItemType Directory -Force -Path $consumerBin | Out-Null
$manifest = @'
name: remvibe_terminal_asset_consumer
description: Isolated native-asset packaging smoke for remvibe_terminal.
publish_to: none
environment:
  sdk: '>=3.10.0 <4.0.0'
dependencies:
  remvibe_terminal:
    path: ../..
'@
Set-Content -LiteralPath (Join-Path $consumer 'pubspec.yaml') -Value $manifest -Encoding UTF8
Copy-Item -LiteralPath $source -Destination (Join-Path $consumerBin 'main.dart') -Force

Push-Location $consumer
try {
    Write-Host '=== Resolve isolated native asset consumer ==='
    dart pub get
    if ($LASTEXITCODE -ne 0) { throw 'Isolated consumer pub get failed.' }

    Write-Host '=== Build native asset CLI bundle (no manual DLL copy) ==='
    dart build cli --output $bundleRoot --target bin/main.dart
    if ($LASTEXITCODE -ne 0) { throw 'dart build cli failed.' }

    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        throw "Built CLI executable not found: $exe"
    }
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) {
        throw "Native asset not bundled under lib/: $dll"
    }

    Write-Host "Built EXE: $exe"
    Write-Host "Bundled DLL: $dll"
    Write-Host '=== Execute bundled ConPTY terminal ==='
    & $exe
    if ($LASTEXITCODE -ne 0) {
        throw "Bundled native-asset consumer failed with exit $LASTEXITCODE."
    }
    Write-Host '=== Verify ordered libraryPath + libraryPaths fallback ==='
    & $exe --library-paths
    if ($LASTEXITCODE -ne 0) {
        throw "Manual multi-path native DLL fallback failed with exit $LASTEXITCODE."
    }

    Write-Host '=== Verify multiple searchDirectories ==='
    & $exe --search-directories
    if ($LASTEXITCODE -ne 0) {
        throw "Native DLL search directory fallback failed with exit $LASTEXITCODE."
    }

    Write-Host 'TERM-01E WINDOWS CLI NATIVE ASSETS BUNDLE PASS'
    Write-Host 'TERM-01E WINDOWS NATIVE LIBRARY MULTI-PATH PASS'
} finally {
    Pop-Location
}
