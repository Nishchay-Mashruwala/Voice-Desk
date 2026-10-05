# Start the INSTALLED Voice Desk as if on a friend's new computer: nothing
# downloaded yet (no Python, speech models, task AI), so Settings -> Getting
# ready does the whole first-run download. Nothing of yours is touched: the
# downloads go to a separate test folder, removed with -Clean.
#
#   powershell -ExecutionPolicy Bypass -File scripts\try-as-friend.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\try-as-friend.ps1 -Clean
#
# Close every other Voice Desk first (including `npm run tauri dev`): a second
# copy would just bring the running one to the front. Your settings, history and
# meetings are shared with the test (they live in %APPDATA%, not redirected).
param([switch]$Clean)
$ErrorActionPreference = "Stop"

$test = Join-Path $env:TEMP "voicedesk-friend-test"
if ($Clean) {
  Remove-Item -Recurse -Force $test -ErrorAction SilentlyContinue
  Write-Host "Removed $test"
  exit 0
}

# The per-user installer puts the app under the real %LOCALAPPDATA% (the MSI
# under Program Files); the program is the .exe there that isn't the uninstaller.
$exe = @((Join-Path $env:LOCALAPPDATA "Voice Desk"), (Join-Path $env:ProgramFiles "Voice Desk")) |
  Where-Object { Test-Path $_ } |
  ForEach-Object { Get-ChildItem $_ -Filter *.exe | Where-Object { $_.Name -notmatch "^unins" } } |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $exe) { throw "Voice Desk isn't installed. Run scripts\build-installer.ps1 and install it first." }
if (Get-Process | Where-Object { $_.Path -and (Split-Path $_.Path -Leaf) -match "^(voicedesk|Voice Desk)\.exe$" }) {
  throw "Close Voice Desk first (tray icon -> Quit, and stop npm run tauri dev)."
}

# Voice Desk keeps its downloads in %LOCALAPPDATA%\VoiceDesk and speech models
# in the Hugging Face cache: both point into the empty test folder here.
New-Item -ItemType Directory -Force (Join-Path $test "Local"), (Join-Path $test "hf") | Out-Null
$env:LOCALAPPDATA = Join-Path $test "Local"
$env:HF_HOME = Join-Path $test "hf"
Write-Host "Starting $exe as a new computer (downloads go to $test)."
Write-Host "Open Settings -> Getting ready. When done: quit Voice Desk, then run this with -Clean."
Start-Process $exe
