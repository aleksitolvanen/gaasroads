# Exports the Web build headless, stages it, and pushes it to itch.io
# (needlefi.itch.io/gaasroads) with butler. One-time setup: butler login.
#
#   .\release-web.ps1              # export + push
#   .\release-web.ps1 -SkipExport  # push whatever is in Builds/ already
#
# Godot binary comes from $env:GODOT or the default below.
param(
    [string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "D:\dl\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe" }),
    [string]$Channel = "needlefi/gaasroads:html",
    [switch]$SkipExport
)
$ErrorActionPreference = "Stop"

$butler = "$env:LOCALAPPDATA\Programs\butler\butler.exe"
if (-not (Test-Path $butler)) { $butler = "butler" }

if (-not $SkipExport) {
    & $Godot --headless --path . --export-release "Web" "Builds/GaasRoads.html"
    if ($LASTEXITCODE -ne 0) { throw "Godot export failed ($LASTEXITCODE)" }
}
if (-not (Test-Path "Builds/GaasRoads.html")) { throw "No web build in Builds/" }

# Stage: index.html + the runtime files, nothing else (no editor sidecars)
$stage = "Builds/web-release"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item "Builds/GaasRoads.html" "$stage/index.html"
Get-ChildItem "Builds" -File |
    Where-Object { $_.Name -like "GaasRoads.*" -and $_.Name -ne "GaasRoads.html" -and $_.Extension -ne ".import" } |
    Copy-Item -Destination $stage

$version = git rev-parse --short HEAD
& $butler push $stage $Channel --userversion $version
if ($LASTEXITCODE -ne 0) { throw "butler push failed ($LASTEXITCODE)" }
Write-Host "Pushed $version to $Channel"
