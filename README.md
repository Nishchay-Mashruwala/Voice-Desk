# Voice Desk

A private, local desktop app for Windows, macOS and Linux that:

1. **Types what you say, wherever your cursor is.** Press your shortcut and talk; each phrase appears as soon as you pause.
2. **Finds the tasks assigned to you** in meetings, or turns what you say into a to-do list.

Everything runs on your computer. No audio or text leaves it.

## What you need

| | Minimum | Recommended |
|---|---|---|
| System | Windows 10/11 (64-bit), macOS 14.2+ (14.6+ to record the other side of calls), or Linux with PipeWire | Windows 10/11 — meeting auto-detection is Windows-only for now |
| Processor | 4-core 64-bit CPU (x86-64 or Apple Silicon) | 6–8 cores |
| Memory | 8 GB RAM | 16 GB RAM |
| Graphics | None needed — everything runs on the CPU | NVIDIA GPU with 4 GB+ (and a current driver). AMD/Intel graphics are used by the task AI only (Vulkan) |
| Disk | 4 GB free | 8 GB free (for the NVIDIA speed-up or Hindi/Gujarati) |
| Other | Microphone; internet for the first setup only | Headphones in meetings (keeps your voice and theirs apart) |

What Voice Desk itself uses at its busiest (processing a meeting): about **3 GB of RAM**. With an NVIDIA GPU, it also uses **1.2 GB of GPU memory for speech** and **2.3 GB while finding tasks**. Smaller GPUs get smaller models automatically, and GPUs with under ~1 GB free fall back to the CPU. Measured on a 70-second meeting:

| Job | GPU (RTX 3050 4 GB) | CPU only (Ryzen 7 5800H) |
|---|---|---|
| Speech model loaded, idle | 0.7 GB RAM · 1.2 GB GPU | 0.35 GB RAM |
| Live dictation | 2.1 GB RAM · 1.1 GB GPU · ~1 core | 1.7 GB RAM · ~1 core |
| Transcribing a meeting | 12 s · 2.1 GB RAM · 1.2 GB GPU | 44 s · 2.2 GB RAM · 4.5 cores |
| Telling speakers apart | ~11 s · ~0.1 GB RAM (always on the CPU) | ~11 s · ~0.1 GB RAM |
| Finding tasks (Qwen3 4B) | 26 s · 1.3 GB RAM · 2.3 GB GPU | 47 s · 2.8 GB RAM · 3.6 cores |

Heavy work never uses more than half the CPU cores, so the computer stays usable. Disk: the speech engine and the speech model for your computer ~0.9 GB (+~2.8 GB for the optional NVIDIA speed-up), the task AI 1.1 GB (Qwen3 1.7B) or 2.5 GB (Qwen3 4B), and Hindi/Gujarati support only if you pick those languages. Recordings are kept as FLAC (lossless, about half the size of WAV). **Settings → Storage** lists every downloaded model and deletes the ones you don't use.

## Install (for you and your friends)

**Friends:** download the installer for your computer from [GitHub Releases](https://github.com/Nishchay-Mashruwala/Voice-Desk/releases/latest) (~20 MB). Windows may show "Windows protected your PC" because the app isn't code-signed: click **More info → Run anyway**. On a Mac the app isn't signed either: the first time, **right-click Voice Desk → Open** (then **Open** again) so Gatekeeper lets it start. On first start, **Settings → Getting ready** shows what this computer needs and how big it is, downloads it (resumable), and from then on everything works offline. Updates install from inside the app.

**Building from source:** on Windows double-click **`Setup Voice Desk (Windows).bat`**; on macOS / Linux run `bash scripts/setup.sh`. The script installs whatever is missing (Node.js, Rust, build tools, Python via `uv`), builds Voice Desk, and adds a **Voice Desk** shortcut; running it again skips finished steps.

Then open Voice Desk and go to **Settings**:
1. **About you:** enter your name.
2. **Your voice:** read a short passage (about 15 s) so only you can give commands.
3. *(Only for Hindi/Gujarati)* accept the terms on [the model page](https://huggingface.co/ai4bharat/indic-conformer-600m-multilingual), create a Hugging Face token with **Read** access, and paste it under **Speech recognition** (it's kept in the system keychain). Add Hindi/Gujarati under **Getting ready** (from source: run the setup with `-Indic` on Windows or `VOICEDESK_INDIC=1` on macOS/Linux). Not available on Intel Macs (no current PyTorch for them).

Speaker detection (telling meeting participants apart) works out of the box.

## Using it

| | |
|---|---|
| Start/stop listening | Your shortcut (default `Ctrl+Shift+Space`), the tray icon, or the mic button. In Settings, choose single press, double press, long press (hold N seconds), or push-to-talk. |
| Floating bar | Appears while listening: Pause/Resume, Record tasks, Stop. While a meeting is recorded it turns red with a timer and Stop. Drag it anywhere; it remembers where you put it. It never takes the cursor from your app. |
| Voice commands | Say the assistant name first (default **Jarvis**). The phrases can be changed in Settings. |
| History | Every listening session is recorded. Press play and the words light up as they're spoken; click a word to jump there. Words that became tasks are underlined. **👥** turns a recording into a meeting (speakers detected, tasks found). |
| Copy last dictation | Right-click the tray icon, or right-click Voice Desk's taskbar button (Windows). |
| Meetings | When Zoom, Teams, WhatsApp, Discord, Slack, Skype, Webex or a browser call (Google Meet…) starts, the floating bar offers **Transcribe Meeting**; ✕ hides it for that call (Windows). While it's offered, your shortcut (or the mic button) starts the meeting recording too, and stops it later. Videos and music never count as calls. Playback highlights each word; **Move to Listen history** turns a meeting back into a normal recording, keeping its tasks. |
| Tasks | Click a task's source to hear where it was said (5 s before, or right at it — Settings → Task AI). Copy a task with its copy button. |
| Deleting | Recordings, meetings and tasks ask first, then can be undone for 5 seconds. |

Default commands (never typed):

| Say | Does |
|---|---|
| Jarvis, pause | Stop typing, keep listening for commands |
| Jarvis, resume | Start typing again |
| Jarvis, record tasks | Everything said becomes tasks. On a call, it finds what others ask of you; alone, it turns your words into to-dos. |
| Jarvis, tasks recorded | Create the tasks, keep listening |
| Jarvis, stop | Stop listening |

## Where your data is stored

| What | Windows | macOS | Linux |
|---|---|---|---|
| Database (history, meetings, tasks, settings) | `%APPDATA%\com.rajvee.voicedesk\voicedesk.db` | `~/Library/Application Support/com.rajvee.voicedesk/` | `~/.local/share/com.rajvee.voicedesk/` |
| Recordings (`listen-*.flac`, `meeting-*.flac`; `.wav` while recording) | `…\com.rajvee.voicedesk\recordings\` | same folder `/recordings` | same folder `/recordings` |
| Your voice profile | `…\com.rajvee.voicedesk\voice_profile.npy` | same folder | same folder |
| Speech models (Whisper, voice ID, Hindi/Gujarati) | `%USERPROFILE%\.cache\huggingface\hub` | `~/.cache/huggingface/hub` | `~/.cache/huggingface/hub` |
| Speaker-detection and task AI models (Qwen3 GGUF) | `%LOCALAPPDATA%\VoiceDesk\models` | `~/Library/Caches/VoiceDesk/models` | `~/.cache/voicedesk/models` |
| Task AI program (llama.cpp) and the engine's Python | `%LOCALAPPDATA%\VoiceDesk\llama`, `…\runtime` | `~/Library/Caches/VoiceDesk/llama`, `…/runtime` | `~/.cache/voicedesk/llama`, `…/runtime` |

**Settings → Storage & memory** has an **Open** button for each folder. Recordings — dictation and meetings — are deleted after 30 days by default (transcripts, summaries and tasks are kept).

## How it works

```
┌──────────────────────────── Tauri app ─────────────────────────────┐
│ React UI (src/)  ·  floating control bar (src/views/Overlay.tsx)   │
│ Rust backend (src-tauri/src/)                                      │
│   session.rs   live listening: mic → engine → type at cursor,      │
│                voice commands, task recording                      │
│   audio.rs     mic + system-audio capture, 16 kHz resampling       │
│   pipeline.rs  meeting/task-recording → transcript → tasks         │
│   meeting_detect.rs  which call app has the mic (Windows)          │
│   hardware.rs  GPUs, RAM, cores; memory in use                     │
│   llm.rs       Qwen3 via llama-server (started only when needed)   │
│   db.rs        SQLite                                              │
│   engine.rs    runs the Python engine ────────┐                    │
└───────────────────────────────────────────────┼────────────────────┘
                                                │ JSON lines
           engine/engine.py ◄───────────────────┘
             faster-whisper  sized to the GPU's free memory, or the CPU
             indic.py        Hindi/Gujarati in their own script (IndicConformer)
             Silero VAD      cuts speech into phrases at pauses
             commands.py     "Jarvis, pause" parsing (fuzzy)
             voiceprint.py   is it your voice? (26 MB ONNX, no torch)
             speakers.py     who spoke when (sherpa-onnx, 46 MB of ONNX models)
```

**Tech stack.** Desktop shell: [Tauri 2](https://tauri.app) (Rust) with a React 19 + TypeScript 6 UI built by Vite 8. Backend crates: cpal (audio capture), rusqlite (SQLite), reqwest + tokio (downloads, task AI), enigo/arboard (typing at the cursor), sysinfo, winreg (call detection), keyring (token storage), tauri-plugin-updater. Speech engine: Python 3.12 with faster-whisper (CTranslate2), Silero VAD, onnxruntime (voice ID, speakers, IndicConformer). Task AI: Qwen3 1.7B or 4B (GGUF) in llama.cpp's `llama-server` (CPU or Vulkan). No cloud: the UI talks to Rust over Tauri's IPC, Rust to the engine over JSON lines on stdin/stdout, and to `llama-server` on localhost.

**Accuracy.** With room on an NVIDIA GPU, the engine uses Whisper large-v3-turbo for English (medium when Hindi/Gujarati are on, large-v3 when translating); in testing, `small` misheard "Nishchay" as "next time" and turbo didn't. Your name, the assistant name and your vocabulary are passed to Whisper as hints. The task AI is **Qwen3 4B** on computers with 6 GB+ of RAM, because accuracy matters more than size: in tests Qwen3 1.7B missed tasks that 4B found. 1.7B is still selectable in **Settings → Task AI** (and is used below 6 GB).

**English inside Hindi/Gujarati.** With English and Gujarati (or Hindi) both chosen, Gujarati is written in Gujarati script and English said in between, words or whole sentences, in English: "હા એનું background તો Scottish છે". IndicConformer writes each chunk, Whisper reads the same audio as English once, and `engine/mixed.py` combines them word by word by time and sound, using a bundled English word list (SCOWL) to tell English from Gujarati written in Latin letters.

**Memory.** Speaker detection uses small ONNX models (~0.1 GB of RAM; 11 s for a 70 s call on a CPU). PyTorch is only installed and loaded for Hindi/Gujarati. After 10 idle minutes (configurable), the speech engine shuts down and frees all its memory; it restarts when you next talk, and nothing you say while it starts is lost.

**Any computer.** Settings → Processor (Auto, a specific NVIDIA GPU, or CPU only) applies to speech, speaker detection and the task AI. Auto picks a Whisper model that fits the GPU's free memory (or the CPU), heavy work uses half the CPU cores, and the task AI only reserves the memory its transcript needs. To see what each job uses on a computer: `.venv/Scripts/python engine/bench_resources.py meeting-N-mic.wav meeting-N-system.wav [--device cpu]`.

## Development

```bash
npm install
npm run tauri dev                               # run with hot reload
cd src-tauri && cargo test                      # Rust unit tests
cargo test -- --ignored --nocapture             # task AI tests (model downloaded; VOICEDESK_LLM=qwen3-1.7b|qwen3-4b)
.venv/Scripts/python engine/test_commands.py    # voice-command parser tests
.venv/Scripts/python engine/test_speakers.py    # speaker detection and echo removal tests
.venv/Scripts/python engine/test_mixed.py       # English inside Gujarati (combining the two models)
.venv/Scripts/python engine/test_stream.py some.wav   # live streaming test
cargo test mic_users_live -- --ignored --nocapture    # call detection sees the mic in use (Windows)
.venv/Scripts/python engine/bench_resources.py MIC.wav SYSTEM.wav [--device cpu]   # RAM/GPU/CPU per job
```

## Releases

Installers are built by GitHub Actions ([.github/workflows/build.yml](.github/workflows/build.yml)) for Windows, macOS and Linux.

1. Once: add two repository secrets (GitHub → Settings → Secrets and variables → Actions): `TAURI_SIGNING_PRIVATE_KEY` with the contents of `~/.tauri/voicedesk-updater.key`, and `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` with its password (empty if none). Keep the key safe: installed copies only accept updates signed with it (its public half is in `tauri.conf.json`).
2. Raise the version in all three files: `src-tauri/tauri.conf.json`, `package.json` and `src-tauri/Cargo.toml`. They must match the tag (`v0.2.0` → `0.2.0`), or the build stops.
3. Commit **everything** first (the build only sees what's in git), and check: `python scripts/check-release.py v0.2.0` — it fails on mismatched versions or a Rust/engine file that isn't committed. CI runs the same check, plus `cargo test` and the engine tests, before building.
4. Push a tag: `git tag v0.2.0 && git push origin v0.2.0`. (Run the workflow by hand — Actions → build → Run workflow — to get test installers as downloadable artifacts, without a release.)
5. The workflow creates a **draft** release. Check it, then **Publish** — installed copies see updates only from the latest published release (`latest.json`).

**Python packages are pinned.** The first start installs the engine's packages with `pip install -r engine/requirements.txt -c engine/constraints.txt` (the setup scripts do the same), so friends installing on different days get the same tested versions. To update them: install `requirements.txt` (and the NVIDIA / Hindi-Gujarati packs) without `-c` in a fresh Python 3.12 venv, copy `pip freeze` into `engine/constraints.txt`, check the new versions have Python 3.12 wheels for Windows, macOS (Apple Silicon and Intel) and Linux, then test before tagging — the steps are at the top of that file.

## Roadmap

- [x] Dictation that types as you speak, with an overlay control bar
- [x] Voice commands with a custom assistant name, restricted to your voice
- [x] Meeting recording: you (mic) + others (speakers), speaker detection, task extraction
- [x] "Record tasks" by voice: meeting mode or self-notes mode, detected automatically
- [x] Playback with word-by-word highlighting, editable and reorderable tasks
- [x] One-command setup for Windows, macOS and Linux
- [x] Small installers on GitHub Releases; first start downloads what the computer needs; auto-update
- [x] Rename speakers and remember their voices, edit transcript lines, full-text search
- [x] Auto-detect meetings (Windows), playback for meeting recordings with word highlighting
- [ ] Meeting detection on macOS/Linux, calendar export
