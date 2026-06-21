# release.ps1 — 一键构建 + 打包
$ErrorActionPreference = "Stop"

Write-Host "[1/3] Building engine..." -ForegroundColor Cyan
Push-Location $PSScriptRoot
xmake build engine
if ($LASTEXITCODE -ne 0) { throw "Engine build failed" }

Write-Host "[2/3] Building Flutter release..." -ForegroundColor Cyan
Push-Location spectrum_ui
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "Flutter build failed" }

$exe = "build/windows/x64/runner/Release/spectrum_ui.exe"
$dll = "build/windows/x64/runner/Release/spectrum_engine.dll"
$data = "build/windows/x64/runner/Release/data"

if (!(Test-Path $exe)) { throw "EXE not found" }

Write-Host "[3/3] Packaging..." -ForegroundColor Cyan
$out = "../spectrum_visualizer_windows.zip"
Compress-Archive -Path $exe, $dll, $data -DestinationPath $out -Force
Pop-Location
Pop-Location

Write-Host "Done: $out" -ForegroundColor Green
