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
| Graphics | None needed — everything runs on the CPU | NVIDIA GPU with 4 GB+ (and a current driver). AMD/Intel graphics aren't used |
| Disk | 15 GB free during setup | 20 GB free |
| Other | Microphone; internet for the first setup only | Headphones in meetings (keeps your voice and theirs apart) |

What Voice Desk itself uses at its busiest (processing a meeting): about **3 GB of RAM**. With an NVIDIA GPU, it also uses **1.2 GB of GPU memory for speech** and **2.3 GB while finding tasks**. Smaller GPUs get smaller models automatically, and GPUs with under ~1 GB free fall back to the CPU. Measured on a 70-second meeting:

| Job | GPU (RTX 3050 4 GB) | CPU only (Ryzen 7 5800H) |
|---|---|---|
| Speech model loaded, idle | 0.7 GB RAM · 1.2 GB GPU | 0.35 GB RAM |
| Live dictation | 2.1 GB RAM · 1.1 GB GPU · ~1 core | 1.7 GB RAM · ~1 core |
| Transcribing a meeting | 12 s · 2.1 GB RAM · 1.2 GB GPU | 44 s · 2.2 GB RAM · 4.5 cores |
| Telling speakers apart | 90 s · 3.2 GB RAM (always on the CPU) | 89 s · 2.8 GB RAM · 3 cores |
| Finding tasks (Qwen3 4B) | 26 s · 1.3 GB RAM · 2.3 GB GPU | 47 s · 2.8 GB RAM · 3.6 cores |

Heavy work never uses more than half the CPU cores, so the computer stays usable. Disk: speech models 0.5–2 GB (depending on GPU), the Hindi/Gujarati model 2.4 GB (only if you pick those languages), the task AI 2.5 GB, Python packages 3.5 GB, and the build a few GB more.

## Install (for you and your friends)

**Windows:** double-click **`Setup Voice Desk (Windows).bat`** in this folder.
**macOS / Linux:** open a terminal in this folder and run `bash scripts/setup.sh`.

The script installs whatever is missing (Node.js, Rust, build tools, Ollama, Python via `uv`), downloads the AI models, builds Voice Desk, and adds a **Voice Desk** shortcut. The first run takes 15–30 minutes, mostly downloads; running it again skips finished steps.

Then open Voice Desk and go to **Settings**:
1. **About you:** enter your name.
2. **Your voice:** read a short passage (about 15 s) so only you can give commands.
3. *(Optional)* **Speaker detection:** tells meeting participants apart. Accept the terms on [the model page](https://huggingface.co/pyannote/speaker-diarization-community-1), then create a Hugging Face token with **Read** access and paste it in.

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
| Recordings (`listen-*.wav`, `meeting-*.wav`) | `…\com.rajvee.voicedesk\recordings\` | same folder `/recordings` | same folder `/recordings` |
| Your voice profile | `…\com.rajvee.voicedesk\voice_profile.npy` | same folder | same folder |
| Speech models (Whisper, voice ID, pyannote) | `%USERPROFILE%\.cache\huggingface\hub` | `~/.cache/huggingface/hub` | `~/.cache/huggingface/hub` |
| Task AI model (Qwen3) | `%USERPROFILE%\.ollama\models` | `~/.ollama/models` | `~/.ollama/models` or `/usr/share/ollama` |

**Settings → Storage & memory** has an **Open** button for each folder. Dictation recordings are deleted after 30 days by default (the text is kept).

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
│   llm.rs       Qwen3 4B via Ollama (auto-started)                  │
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
             diarize.py      pyannote, in a short-lived subprocess
```

**Tech stack.** Desktop shell: [Tauri 2](https://tauri.app) (Rust) with a React 19 + TypeScript 6 UI built by Vite 8. Backend crates: cpal (audio capture), rusqlite (SQLite), reqwest + tokio (Ollama), enigo/arboard (typing at the cursor), sysinfo, winreg (call detection). Speech engine: Python 3.12 with faster-whisper (CTranslate2), Silero VAD, onnxruntime (voice ID, IndicConformer), pyannote.audio 4 (speakers). Task AI: Qwen3 4B in Ollama. No server, no cloud: the UI talks to Rust over Tauri's IPC, Rust to the engine over JSON lines on stdin/stdout, and to Ollama on localhost.

**Accuracy.** With room on an NVIDIA GPU, the engine uses Whisper large-v3-turbo for English (medium when Hindi/Gujarati are on, large-v3 when translating); in testing, `small` misheard "Nishchay" as "next time" and turbo didn't. Your name, the assistant name and your vocabulary are passed to Whisper as hints.

**Memory.** Torch/pyannote only load in a subprocess that exits after each meeting. After 10 idle minutes (configurable), the speech engine shuts down and frees all its memory; it restarts when you next talk, and nothing you say while it starts is lost.

**Any computer.** Settings → Processor (Auto, a specific NVIDIA GPU, or CPU only) applies to speech, speaker detection and the task AI. Auto picks a Whisper model that fits the GPU's free memory (or the CPU), heavy work uses half the CPU cores, and the task AI only reserves the memory its transcript needs. To see what each job uses on a computer: `.venv/Scripts/python engine/bench_resources.py meeting-N-mic.wav meeting-N-system.wav [--device cpu]`.

## Development

```bash
npm install
npm run tauri dev                               # run with hot reload
cd src-tauri && cargo test                      # Rust unit tests
cargo test -- --ignored --nocapture             # LLM tests (needs Ollama)
.venv/Scripts/python engine/test_commands.py    # voice-command parser tests
.venv/Scripts/python engine/test_stream.py some.wav   # live streaming test
cargo test mic_users_live -- --ignored --nocapture    # call detection sees the mic in use (Windows)
.venv/Scripts/python engine/bench_resources.py MIC.wav SYSTEM.wav [--device cpu]   # RAM/GPU/CPU per job
```

## Roadmap

- [x] Dictation that types as you speak, with an overlay control bar
- [x] Voice commands with a custom assistant name, restricted to your voice
- [x] Meeting recording: you (mic) + others (speakers), speaker detection, task extraction
- [x] "Record tasks" by voice: meeting mode or self-notes mode, detected automatically
- [x] Playback with word-by-word highlighting, editable and reorderable tasks
- [x] One-command setup for Windows, macOS and Linux
- [ ] Packaging: bundle Python and models into real installers (`.msi`, `.dmg`, `.AppImage`)
- [x] Auto-detect meetings (Windows), playback for meeting recordings with word highlighting
- [ ] Meeting detection on macOS/Linux, calendar export
