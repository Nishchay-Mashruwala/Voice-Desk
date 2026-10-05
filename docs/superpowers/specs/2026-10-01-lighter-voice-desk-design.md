# Lighter Voice Desk: meetings, storage, sharing — design

Date: 2026-10-01 · Status: draft for review

## Goal

Make Voice Desk correct in calls, light on CPU/RAM/GPU **and disk**, and easy to
give to friends whose computers are weaker than the RTX 3050 laptop it was built on.

Constraints from the owner:

- Low CPU, RAM, GPU — and now low disk / app size.
- Friends get a ~20 MB installer; the first launch downloads only what that PC
  needs, then everything works offline.
- Recordings compressed with **FLAC** (lossless).
- No code signing for now (SmartScreen shows "More info → Run anyway" once).
- Windows first; macOS/Linux must keep working where they do today.

## Where the space goes today (measured on the owner's PC)

| Part | Size | Needed? |
|---|---|---|
| Ollama program | 2.8 GB | No — `llama-server` (llama.cpp) does the same in ~30–60 MB |
| Qwen3 4B task model | 2.4 GB | A model is needed (see decision D2) |
| Python environment | 3.5 GB | Core is ~0.2 GB (ctranslate2 60 MB, onnxruntime 46 MB, numpy 35 MB, tokenizers, av, hub) |
| ↳ NVIDIA CUDA libraries | 2.0 GB | Only to run Whisper on an NVIDIA GPU |
| ↳ torch 546 MB, transformers 120 MB, scipy 116 MB, sympy 77 MB, pandas 69 MB, sklearn 45 MB, matplotlib 33 MB… | ~1.1 GB | Pulled in by pyannote; torch + transformers also by Hindi/Gujarati |
| Speech models (Hugging Face cache) | 8.9 GB | 6 Whisper sizes cached; one or two are used |
| Recordings | 84 MB | WAV; never deleted for meetings |

Resource baseline (70 s meeting, from `engine/bench_resources.py`): speaker
detection 2.8–3.2 GB RAM and ~90 s on CPU — the heaviest job.

## Phases

Each phase is self-contained, ends with tests + a measurement (CPU, RAM, GPU,
disk) compared to the baseline, and is committed separately.

### Phase 1 — Groundwork (no behaviour change)

- **Split `src-tauri/src/lib.rs`** (~1,000 lines): `meetings.rs` (start/stop/
  list/convert/audio commands, `begin_meeting`/`end_meeting`, call offer),
  `tasks.rs`, `hotkey.rs`, `settings_cmd.rs`. `lib.rs` keeps `AppState`, setup,
  `run()`.
- **Split `engine/engine.py`** (~1,200 lines): `transcriber.py` (Whisper model
  choice, devices, transcription), `stream.py` (live dictation),
  `meeting.py` (meeting pipeline, speakers), `engine.py` (protocol, dispatch,
  watchdogs).
- **Rename `whisper_device` → `device`**: Rust field with
  `#[serde(alias = "whisper_device")]` so saved settings load; frontend type;
  engine already receives `device`.
- **Hide model choices the PC can't run**: the Accuracy list is built from
  `hardware_info` — GPU models only when an NVIDIA GPU has the free memory
  (`GPU_NEED_GB`), CPU gets small/base; an unavailable saved choice shows as
  "Auto".

### Phase 2 — Lighter speaker detection (removes PyTorch from the base install)

Replace pyannote (torch, subprocess, Hugging Face token) with an ONNX pipeline
in the engine process:

1. **Segmentation**: pyannote *segmentation-3.0* exported to ONNX (~6 MB, MIT,
   ungated copy published with sherpa-onnx) over 10 s windows → which of up to
   3 local speakers talks in each frame.
2. **Embeddings**: the WeSpeaker ResNet34 ONNX model already used for voice ID
   (26 MB), one embedding per (window, local speaker) with enough speech.
3. **Clustering**: agglomerative clustering on cosine distance (numpy), with a
   tuned threshold, or the known number of speakers.
4. **Stitching**: frames → global speaker timeline → the same `turns` list the
   rest of the pipeline already uses.

Validation: on meetings 24 and 25, compare speakers and turns with today's
pyannote output and re-run the "words on the wrong speaker" check
(today 0% / 2%). Accept only if speaker counts match and wrong words stay
≤ 3%; otherwise tune.

Removed from the base install: `pyannote.audio`, `diarize.py`, and with them
torch/scipy/pandas/sympy/sklearn/matplotlib/lightning. The Hugging Face token
is no longer needed for speakers (still for the gated Hindi/Gujarati model).

Expected: RAM for speaker detection ~3 GB → ~0.3 GB; time on CPU well under
the meeting's length (to be measured).

### Phase 3 — Your voice in calls ("Me" is really you)

In a call, the mic also hears the speakers when there are no headphones, so
other people's words end up in "Me" lines. For each mic line:

- **Echo by content**: if its words mostly match a computer-audio line that
  overlaps it in time (allowing ~0.5 s delay), it's the speakers leaking in →
  drop it.
- **Echo by voice**: with a voice profile, a mic line that doesn't match the
  user's voice *and* overlaps speech on the computer audio → drop it.
- Mic lines that are the user stay "Me". Without a profile, only the content
  check runs.

Test: synthetic mix (system audio added into the mic track at −12 dB, 150 ms
delay) on meeting 25 → no "Me" line repeats a computer-audio line; real "Me"
lines kept.

### Phase 4 — Meeting lifecycle and call detection

- **Auto-stop**:
  - Started from a call offer: stops 15 s after that app releases the mic.
  - Any meeting: stops after 3 minutes with no speech on either track (also
    covers Teams keeping the mic open after the call).
  - Then transcribes and finds tasks as if Stop was pressed; the main window
    says why it stopped. Setting: "Stop meetings automatically" (on).
- **Shortcut confirmation**: during a meeting the first press shows
  "Press again to stop" on the bar for 3 s; a second press within 3 s stops.
  (A dialog isn't possible: the bar never takes focus.)
- **Browser false alarms**: a browser using the mic counts as a call only if
  one of its windows' titles names a call site (Google Meet, Zoom, Microsoft
  Teams, WhatsApp, Discord, Slack, Webex, Skype, Messenger…). Checked when the
  mic turns on; once offered, the offer stays until the mic is released.
- **Lingering mic** (Teams): the offer is withdrawn after 3 minutes without
  speech on the speakers.

### Phase 5 — Storage

- **FLAC**: recordings (meeting tracks, listening sessions) are converted from
  WAV to FLAC right after they're recorded/processed (pure-Rust encoder, in the
  background). Speech at 16 kHz mono is expected to shrink to ~45–60% of the
  WAV — FLAC is lossless, so it is ~2×, not 10×. Playback (WebView2) and the
  engine (`soundfile`, ~2 MB) read FLAC. Existing recordings are converted once,
  in the background.
- **Retention**: "Keep recordings for N days" also applies to meeting audio
  (transcripts, summaries and tasks are kept). Re-transcribe is disabled once
  the audio is gone (as today).
- **Model manager** (Settings → Storage): every downloaded model with its size
  and whether the current settings use it; Delete for unused ones. On this PC
  that's ~6 GB of unused Whisper sizes.
- **Hindi/Gujarati model**: keep only the int8 encoder after quantising, delete
  the float32 originals (to be measured; the cache is 2.4 GB today).

### Phase 6 — Features

- **Rename speakers**: click "Speaker 1" in a meeting → type "Priya"; all their
  lines update. "Remember this voice" stores the speaker's average voice
  embedding (`people` table, ~1 KB each). Later meetings label matching voices
  automatically. After renaming, Find tasks uses the names.
- **Edit the transcript**: edit a line's text; its words are re-timed across
  the line (estimated). Find tasks can be run again.
- **Search**: SQLite full-text index (FTS5) over recordings, meetings,
  transcripts and tasks; a search box in the sidebar. Results open at the
  matching words (reusing the "play from the quote" jump).

### Phase 7 — Polish

- **Hugging Face token** → OS keychain (`keyring` crate: Windows Credential
  Manager / macOS Keychain / Secret Service); moved out of the database once.
- **Interface CPU**: measure the window's CPU with "CPU only". Pause the
  drifting background and sidebar blur while the window is hidden or minimised;
  with CPU only, use a still background and no blur.

### Phase 8 — Sharing (installer, first-run download, updates)

- **Task AI without Ollama**: the app runs `llama-server` (llama.cpp, MIT)
  itself, like the speech engine: the CPU build, or the Vulkan build which uses
  NVIDIA, AMD **and** Intel GPUs without CUDA libraries. Model as GGUF from
  Hugging Face (see D2). Same JSON-schema output; the existing task-extraction
  tests must pass with the chosen model.
- **First run** (in-app "Getting ready" screen): detects the PC, shows what it
  will download and how big, downloads with resume and progress, then works
  offline:
  - Python (python-build-standalone, ~30 MB) + `uv`, core engine packages
    (~0.2 GB)
  - the Whisper size for this PC; `llama-server`; the task model
  - optional, offered when they apply: **NVIDIA speed-up** (CUDA libraries,
    ~2 GB — trimmed to the DLLs CTranslate2 needs where possible) and
    **Hindi/Gujarati** (torch CPU + model)
- **Installer**: Tauri NSIS installer (~10–20 MB) built by GitHub Actions on a
  version tag, published to GitHub Releases; fix the retired `macos-13` runner.
- **Auto-update**: Tauri updater reading GitHub Releases, signed with an
  updater key (free; separate from Windows code signing).
- `scripts/setup-*` remain for development.

Expected first download, by PC:

| PC | Download |
|---|---|
| CPU only, English | ~1.6–1.9 GB (with Qwen3 1.7B) / ~3.0 GB (Qwen3 4B) |
| + NVIDIA speed-up (optional) | +~1–2 GB |
| + Hindi/Gujarati (optional) | +~1–1.5 GB (to be measured) |

Disk on the owner's PC afterwards: from ~17.6 GB to roughly 3–5 GB, depending
on which models are kept.

## Decisions needing the owner

- **D1 — Replace Ollama with a bundled `llama-server`.** Recommended: saves
  ~2.8 GB, works offline without a separate install, and uses AMD/Intel GPUs
  too. Friends who already use Ollama gain nothing from it being kept.
- **D2 — Task model by RAM.** Recommended: Qwen3 **1.7B** (~1.1 GB) on PCs with
  < 16 GB RAM, **4B** (~2.5 GB) on 16 GB+; changeable in Settings. 1.7B is
  smaller and faster but may miss tasks the 4B finds — it must pass the same
  extraction tests before it ships as a default.
- **D3 — The 1.5 GB target.** A CPU-only PC needs ~1.6–1.9 GB with the 1.7B
  model; it can't reach 1.5 GB with a useful task model. Accept ~1.9 GB?

### Decisions taken

- **D1 — done:** Ollama replaced by a downloaded `llama-server` (llama.cpp).
- **D2 — Qwen3 4B is the default on PCs with 6 GB+ RAM** (owner decision,
  2026-10-05): accuracy over size — in tests 1.7B missed tasks the 4B found.
  1.7B stays selectable in Settings and is used below 6 GB.
- **First-run install uses `pip` (not `uv`)** in the downloaded Python, with
  `-c engine/constraints.txt` so every install gets the same pinned, tested
  package versions. (The from-source setup scripts still use `uv`, with the
  same constraints.)

## Testing and measurement

- Every phase: `cargo test`, `npm run build`, `engine/test_commands.py`, plus
  new tests for the logic it adds (speaker pipeline vs. pyannote reference,
  echo removal, auto-stop timing, FLAC round-trip, settings migration, FTS
  search, model choice by hardware).
- `engine/bench_resources.py` before/after phases 2, 5 and 8, on GPU and CPU.
- A manual pass in the running app at the end of each phase for the UI parts.

## Out of scope

Code signing, meeting detection on macOS/Linux, calendar export, a
transcript/speaker editor beyond rename + line text.

## Risks

- ONNX speaker detection may be less accurate than pyannote on hard audio
  (overlap, similar voices). Mitigation: validation gate above; tune threshold.
- First-run downloads can fail on bad connections → resumable downloads and a
  retry button; the app explains what's missing.
- Window-title matching for browser calls depends on site titles, which can
  change → the list lives in one place and is easy to update.
