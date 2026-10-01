<#
  Voice Desk setup for Windows 10/11.
  Double-click "Setup Voice Desk (Windows).bat" in the project folder, or run:
    powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1

  Installs anything missing (Node.js, Rust, C++ build tools, Ollama, uv), sets up
  the Python speech engine, downloads the AI models, builds Voice Desk, and
  puts a "Voice Desk" shortcut on your Desktop and in the Start menu.
  Safe to run again: finished steps are skipped.
#>
param(
  [switch]$NoShortcut,
  [switch]$SkipBuild,
  [switch]$KeepOllamaAutostart
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Venv = Join-Path $Root ".venv"
$Py = Join-Path $Venv "Scripts\python.exe"

function Step($n, $text) { Write-Host "`n[$n/7] $text" -ForegroundColor Cyan }
function Ok($text) { Write-Host "  OK  $text" -ForegroundColor Green }
function Info($text) { Write-Host "      $text" -ForegroundColor DarkGray }
function Fail($text) { Write-Host "`n  X  $text" -ForegroundColor Red; Read-Host "Press Enter to close"; exit 1 }

function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
              [Environment]::GetEnvironmentVariable("Path", "User") + ";" +
              (Join-Path $env:USERPROFILE ".cargo\bin")
}
function Has($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Winget-Install($id, $name, $extra = @()) {
  if (-not (Has "winget")) { Fail "$name is missing and winget isn't available. Install $name manually, then run this again." }
  Info "Installing $name (a window may ask for permission)..."
  winget install --id $id -e --accept-source-agreements --accept-package-agreements @extra
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { Fail "Could not install $name." }  # -1978335189 = already installed
  Refresh-Path
}

Write-Host "Voice Desk setup" -ForegroundColor Magenta
Write-Host "Folder: $Root"

# ---------------------------------------------------------------------------
Step 1 "Build tools"
Refresh-Path
if (Has "node") { Ok "Node.js $(node --version)" } else { Winget-Install "OpenJS.NodeJS.LTS" "Node.js" }
if (-not (Has "cargo")) {
  if (-not (Has "rustup")) { Winget-Install "Rustlang.Rustup" "Rust" }
  rustup default stable | Out-Null
  Refresh-Path
}
if (Has "cargo") { Ok "Rust $(cargo --version)" } else { Fail "Rust didn't install correctly. Restart your PC and run setup again." }

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$hasMsvc = (Test-Path $vswhere) -and (& $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
if ($hasMsvc) { Ok "C++ build tools" } else {
  Winget-Install "Microsoft.VisualStudio.2022.BuildTools" "C++ build tools (large download)" @(
    "--override", "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended")
}

# ---------------------------------------------------------------------------
Step 2 "Ollama (runs the task AI)"
$ollama = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"
if ((Has "ollama") -or (Test-Path $ollama)) { Ok "Ollama installed" } else { Winget-Install "Ollama.Ollama" "Ollama" }
if (-not (Has "ollama") -and (Test-Path $ollama)) { $env:Path += ";" + (Split-Path $ollama) }
# Voice Desk starts Ollama when it opens and stops it when it closes, so Ollama
# doesn't need to launch at login. (Re-enable: move the shortcut back.)
$startupLink = Join-Path ([Environment]::GetFolderPath("Startup")) "Ollama.lnk"
if ((Test-Path $startupLink) -and -not $KeepOllamaAutostart) {
  $backup = Join-Path $env:LOCALAPPDATA "Programs\Ollama\Ollama-startup.lnk.disabled"
  Move-Item $startupLink $backup -Force
  Info "Ollama no longer starts at login; Voice Desk starts it when needed (backup: $backup)."
}

# ---------------------------------------------------------------------------
Step 3 "Python speech engine"
$engineOk = $false
if (Test-Path $Py) {
  & $Py -c "import faster_whisper, onnxruntime" 2>$null
  $engineOk = ($LASTEXITCODE -eq 0)
}
if (-not $engineOk) {
  if (-not (Has "uv")) { Winget-Install "astral-sh.uv" "uv (Python manager)" }
  if (-not (Test-Path $Py)) {
    Info "Creating Python 3.12 environment..."
    uv venv --python 3.12 $Venv
    if ($LASTEXITCODE -ne 0) { Fail "Could not create the Python environment." }
  }
}
Info "Installing speech packages (first time: a few minutes)..."
if (Has "uv") { uv pip install --python $Py -r engine\requirements.txt } else { & $Py -m pip install -q -r engine\requirements.txt }
if ($LASTEXITCODE -ne 0) { Fail "Installing the speech packages failed." }
Ok "Speech engine ready"

# ---------------------------------------------------------------------------
Step 4 "Speech models"
& $Py engine\engine.py --prefetch
if ($LASTEXITCODE -ne 0) { Fail "Downloading speech models failed. Check your internet connection." }

# ---------------------------------------------------------------------------
Step 5 "Task AI model (Qwen3 4B, about 2.5 GB)"
$ollamaCmd = if (Has "ollama") { "ollama" } else { $ollama }
try { Invoke-RestMethod http://127.0.0.1:11434/api/tags -TimeoutSec 3 | Out-Null } catch {
  Info "Starting Ollama..."
  Start-Process $ollamaCmd -ArgumentList "serve" -WindowStyle Hidden
  Start-Sleep 5
}
& $ollamaCmd pull qwen3:4b
if ($LASTEXITCODE -ne 0) { Fail "Downloading the task AI model failed." }
Ok "Task AI ready"

# ---------------------------------------------------------------------------
Step 6 "Building Voice Desk"
if ($SkipBuild) { Info "Skipped (-SkipBuild)" } else {
  npm install --no-audit --no-fund
  if ($LASTEXITCODE -ne 0) { Fail "npm install failed." }
  Info "Compiling (first time: 5-10 minutes)..."
  npx tauri build --no-bundle  # an app, not an installer
  if ($LASTEXITCODE -ne 0) { Fail "Build failed. Scroll up for the error." }
}
$Exe = Join-Path $Root "src-tauri\target\release\voicedesk.exe"
if (Test-Path $Exe) { Ok "Built: $Exe" } elseif (-not $SkipBuild) { Fail "Build finished but $Exe is missing." }

# ---------------------------------------------------------------------------
Step 7 "Shortcuts"
if ($NoShortcut -or -not (Test-Path $Exe)) { Info "Skipped" } else {
  $shell = New-Object -ComObject WScript.Shell
  foreach ($dir in @([Environment]::GetFolderPath("Desktop"), [Environment]::GetFolderPath("Programs"))) {
    $lnk = $shell.CreateShortcut((Join-Path $dir "Voice Desk.lnk"))
    $lnk.TargetPath = $Exe
    $lnk.WorkingDirectory = Split-Path $Exe
    $lnk.IconLocation = "$Exe,0"
    $lnk.Description = "Voice Desk - dictation and meeting tasks"
    $lnk.Save()
  }
  Ok "Desktop and Start menu shortcuts created"
}

Write-Host "`nAll done! Open Voice Desk from your Desktop." -ForegroundColor Magenta
Write-Host "First time: fill in Settings -> About you, and train your voice."
if (-not $env:VOICEDESK_NO_PAUSE) { Read-Host "Press Enter to close" }
