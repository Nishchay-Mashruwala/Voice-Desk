# Build the Windows installer locally, signed for updates like the release build.
#
#   powershell -ExecutionPolicy Bypass -File scripts\build-installer.ps1
#
# The updater key is read from %USERPROFILE%\.tauri\voicedesk-updater.key. If it
# has a password, set TAURI_SIGNING_PRIVATE_KEY_PASSWORD first (or you're asked).
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$key = Join-Path $HOME ".tauri\voicedesk-updater.key"
if (-not (Test-Path $key)) { throw "Updater key not found at $key" }
$env:TAURI_SIGNING_PRIVATE_KEY = Get-Content -Raw $key
if ($null -eq $env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD) {
  $secure = Read-Host "Updater key password (just Enter if it has none)" -AsSecureString
  $env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD = [System.Net.NetworkCredential]::new("", $secure).Password
}

npm run tauri build
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

$setup = Get-ChildItem "src-tauri\target\release\bundle\nsis\*-setup.exe" | Sort-Object LastWriteTime | Select-Object -Last 1
Write-Host ""
Write-Host "Installer: $($setup.FullName)" -ForegroundColor Green
Write-Host "Install it, then run scripts\try-as-friend.ps1 to see the first start as a friend would."
