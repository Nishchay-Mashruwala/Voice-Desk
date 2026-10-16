# Builds vd_llm.dll for the PC tests that run the real task model
# (VOICEDESK_LLM_LIB). Needs Visual Studio's C++ build tools and the Android
# SDK's CMake 4.1.2 (it brings Ninja). Output: out\windows\vd_llm.dll.
#
#   .\build_windows.ps1                       # downloads llama.cpp b11320
#   .\build_windows.ps1 -LlamaSource <an unpacked llama.cpp b11320 folder>
#   .\build_windows.ps1 -Tools                # also vd_llm_bench.exe, vd_llm_grammar.exe
# The Android SDK is found from ANDROID_HOME (or ANDROID_SDK_ROOT), else where
# Android Studio puts it (%LOCALAPPDATA%\Android\Sdk).
param([string]$LlamaSource = '', [switch]$Tools)
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$sdk = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) |
  Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sdk) { throw 'Android SDK not found: set ANDROID_HOME' }
$sdkCmake = Join-Path $sdk 'cmake\4.1.2\bin'
if (-not (Test-Path $sdkCmake)) { throw "CMake 4.1.2 not found in $sdk (install it with the SDK Manager)" }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio C++ build tools not found' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'

$build = Join-Path $here 'out\windows-build'
$out = Join-Path $here 'out\windows'
$flags = "-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_MAKE_PROGRAM=`"$sdkCmake\ninja.exe`""
if ($LlamaSource) { $flags += " -DVD_LLAMA_SOURCE=`"$LlamaSource`"" }
if ($Tools) { $flags += ' -DVD_LLM_TOOLS=ON' }

# vcvars64 looks for vswhere on PATH; cmd's stderr isn't an error here.
$env:PATH = "$(Split-Path $vswhere);$env:PATH"
$ErrorActionPreference = 'Continue'
$cmd = "call `"$vcvars`" >nul && `"$sdkCmake\cmake.exe`" -S `"$here`" -B `"$build`" $flags && `"$sdkCmake\cmake.exe`" --build `"$build`""
cmd /c $cmd
if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force $out | Out-Null
Get-ChildItem $build -Recurse -Include vd_llm.dll, vd_llm_bench.exe, vd_llm_grammar.exe |
  Copy-Item -Destination $out
Get-ChildItem $out
