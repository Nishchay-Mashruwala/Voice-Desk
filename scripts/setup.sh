#!/usr/bin/env bash
# Voice Desk setup for macOS and Linux.
#   bash scripts/setup.sh
# Installs anything missing, sets up the Python speech engine, downloads the AI
# models, builds Voice Desk, and adds a launcher. Safe to run again.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OS="$(uname -s)"
PY="$ROOT/.venv/bin/python"

step() { printf '\n\033[36m[%s/7] %s\033[0m\n' "$1" "$2"; }
ok() { printf '  \033[32mOK\033[0m  %s\n' "$1"; }
info() { printf '      %s\n' "$1"; }
fail() { printf '\n  \033[31mX\033[0m  %s\n' "$1"; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

echo "Voice Desk setup ($OS) in $ROOT"

# ---------------------------------------------------------------------------
step 1 "Build tools"
if [ "$OS" = "Darwin" ]; then
  xcode-select -p >/dev/null 2>&1 || { xcode-select --install; fail "Finish installing the Xcode command line tools, then run this again."; }
  has brew || fail "Homebrew is needed: https://brew.sh — install it, then run this again."
  has node || brew install node
else
  if has apt-get; then
    info "Installing system libraries (asks for your password)..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq build-essential curl wget file pkg-config libssl-dev libxdo-dev \
      libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev \
      libasound2-dev libpipewire-0.3-dev libclang-dev
  elif has dnf; then
    sudo dnf install -y webkit2gtk4.1-devel openssl-devel curl wget file libappindicator-gtk3-devel \
      librsvg2-devel alsa-lib-devel pipewire-devel clang-devel libxdo-devel gcc-c++
  else
    info "Unknown distro: install the Tauri prerequisites yourself (https://tauri.app/start/prerequisites/)."
  fi
  if ! has node; then
    if has apt-get; then
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs
    else
      fail "Please install Node.js 20+ and run this again."
    fi
  fi
fi
ok "Node.js $(node --version)"
if ! has cargo; then
  info "Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  export PATH="$HOME/.cargo/bin:$PATH"
fi
ok "$(cargo --version)"

# ---------------------------------------------------------------------------
step 2 "Task AI"
info "Nothing to install: Voice Desk downloads its task AI (llama.cpp + Qwen3) itself, from Settings -> Setup."

# ---------------------------------------------------------------------------
step 3 "Python speech engine"
if ! has uv; then
  info "Installing uv (Python manager)..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
[ -x "$PY" ] || uv venv --python 3.12 "$ROOT/.venv"
info "Installing speech packages (first time: a few minutes)..."
uv pip install --python "$PY" -r engine/requirements.txt -c engine/constraints.txt
if command -v nvidia-smi >/dev/null 2>&1; then
  echo "NVIDIA GPU found: adding GPU speed-up (~2 GB)..."
  uv pip install --python "$PY" -r engine/requirements-nvidia.txt -c engine/constraints.txt
fi
if [ "${VOICEDESK_INDIC:-0}" = "1" ]; then
  echo "Adding Hindi/Gujarati support (~0.7 GB)..."
  uv pip install --python "$PY" -r engine/requirements-indic.txt -c engine/constraints.txt --index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple --index-strategy unsafe-best-match
fi
ok "Speech engine ready"

# ---------------------------------------------------------------------------
step 4 "Speech models"
"$PY" engine/engine.py --prefetch

# ---------------------------------------------------------------------------
step 5 "Task AI model"
info "Downloaded by Voice Desk on first start (Settings -> Setup -> Download): Qwen3 4B, about 2.5 GB."

# ---------------------------------------------------------------------------
step 6 "Building Voice Desk"
npm install --no-audit --no-fund
info "Compiling (first time: 5-10 minutes)..."
npx tauri build --no-bundle  # an app, not an installer
EXE="$ROOT/src-tauri/target/release/voicedesk"
[ -x "$EXE" ] || fail "Build finished but $EXE is missing."
ok "Built: $EXE"

# ---------------------------------------------------------------------------
step 7 "Launcher"
if [ "$OS" = "Darwin" ]; then
  LAUNCHER="$HOME/Desktop/Voice Desk.command"
  printf '#!/bin/bash\nnohup "%s" >/dev/null 2>&1 &\n' "$EXE" > "$LAUNCHER"
  chmod +x "$LAUNCHER"
  ok "Double-click 'Voice Desk' on your Desktop to start"
  info "macOS will ask for Microphone, Accessibility (to type) and System Audio Recording permissions."
else
  mkdir -p "$HOME/.local/share/applications"
  cat > "$HOME/.local/share/applications/voice-desk.desktop" <<EOF
[Desktop Entry]
Name=Voice Desk
Comment=Dictation and meeting tasks
Exec="$EXE"
Icon=$ROOT/src-tauri/icons/128x128.png
Terminal=false
Type=Application
Categories=Utility;Office;
EOF
  ok "Voice Desk added to your applications menu"
  [ "${XDG_SESSION_TYPE:-}" = "wayland" ] && info "Note: on Wayland, global shortcuts and typing into other apps are limited; an X11 session works best."
fi

printf '\n\033[35mAll done!\033[0m First time: fill in Settings -> About you, and train your voice.\n'
