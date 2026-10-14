# Voice Desk mobile app (Android) — design

Date: 2026-10-12, updated 2026-10-13 · Status: approved; Plan 1 built

## Goal

A Flutter app for Android phones that records meetings, voice notes and phone
calls and turns them into transcripts (with who said what), a summary and
tasks, **entirely on the phone**: no server, no PC, works offline. Same idea
as the desktop app, within what Android allows.

Owner's requirements:

- Record **and process** in version 1.
- All processing on the phone; a server can be added later.
- Android phones with **4 GB of RAM or more** (not only the owner's Galaxy M31).
- Languages: **English + Hindi/Gujarati written as spoken** (in their scripts).
- **Who said what** (speaker detection, "Me" for the owner).
- **Detect calls** and offer to process them.
- Slower phones get **every feature, just slower**; the app shows how long it
  will take. Target: ~15 min for a 30-min meeting where the phone allows.

Out of scope for version 1: live dictation / voice commands, search, syncing
with the desktop app, iPhone, a server.

## What the phone can do (speed test, 2026-10-12)

Measured on the Galaxy M31 (Exynos 9611: 4×Cortex-A73 2.3 GHz + 4×A53, no ARM
dot-product instructions, 5.7 GB RAM, Android 12), 4 threads, the owner's
108 s "Gujarati Test" meeting. Full table in
[2026-10-09-status-and-next-steps.md](2026-10-09-status-and-next-steps.md).

| Step | Chosen model | Time / audio length | 30-min meeting on the M31 | Peak RAM |
|---|---|---|---|---|
| English speech | Parakeet TDT-CTC 110M int8 | 0.17× | ~5 min | 0.4 GB |
| Hindi/Gujarati speech | IndicConformer 600M int8 | ~0.4× | ~12–13 min | 1.0 GB |
| Speakers | pyannote segmentation 3.0 + CAM++ | 0.73× | ~22 min | 0.2 GB |
| Summary + tasks | Qwen3 0.6B Q4_K_M | 14.8 tok/s read, 12.4 write | ~11 min | 0.8 GB |

Rejected after measuring: Whisper base (0.83×, junk on Gujarati), Whisper
small (≈3× slower than base), Omnilingual ASR 300M (1.05×, poor English),
eres2net speakers on 1 thread (4×), Qwen3 1.7B on this phone (~24 min).

All steps on the M31: **~50–60 min for a 30-min meeting**. Phones with ARM
dot-product (most mid/high-range from ~2021) are expected to be 2–4× faster,
especially the task AI. Not measured: only the M31 is available.

## 1. Structure

Flutter project in `mobile/` (package `com.rajvee.mobile`), Android first.
Same split as the desktop: screens decide nothing. Since 2026-10-13 the split
is two folders: `mobile/frontend/` is the app (`lib/main.dart`, `lib/ui/`,
`android/`, `ios/`; `flutter run` here) and `mobile/backend/` is a Dart
package the app depends on (everything below except `ui/`).

```
mobile/frontend/lib/
  ui/          screens and widgets only
mobile/backend/lib/
  start.dart   openBackend(): database, folders, recovery at app start
  engine/      processing on the phone
    audio/       recording, 16 kHz mono PCM, joining pieces, FLAC
    speech/      voice activity (Silero), Parakeet, IndicConformer,
                 combining the two per piece (port of the desktop's mixed.py)
    speakers/    who spoke when, "Me" from the voice profile, remembered people
    tasks/       Qwen via llama.cpp: summary + tasks (prompts and parsing
                 ported from the desktop's desktop/backend/core/src/llm.rs)
    pipeline/    runs the steps in order, saves after each step
  data/        SQLite database, audio files, and the one repository the UI uses
  models/      model catalogue, picking models for this phone, downloads
  calls/       call detection and importing the dialer's call recordings
```

Native libraries in the app:

- **sherpa-onnx** (official Flutter package `sherpa_onnx`): Silero voice
  activity, Parakeet (NeMo CTC), speaker diarization, voice embeddings.
- **onnxruntime** (Android library): IndicConformer (encoder, CTC and RNNT
  decoders, as the desktop's `indic.py`; its decoding loop is ported to Dart).
- **llama.cpp**: Qwen, built with the Android NDK 28.2 and CMake 4.1.2 (both
  installed), called from Dart through FFI.

Every data call goes through `data/`'s repository so a server can be added
behind it later without changing the screens.

## 2. Recording and calls

### Recording (Record button)
- Runs as an Android **foreground service** (type microphone): notification
  "Recording · 12:34" with Pause and Stop; works with the screen off.
- Records **16 kHz mono PCM** (the models' input, no conversion later) in
  **1-minute WAV pieces**: a crash loses at most the last minute.
- After processing the pieces are joined and saved as **FLAC**.
- Checks free storage before starting (keeps a safe margin); if storage runs
  out mid-recording, it stops and saves.
- Interruptions: an incoming call pauses recording (Android takes the mic) and
  it resumes after the call; another app taking the mic shows a notice.
- Recordings and voice notes are the same thing; a title is optional
  (default "Recording · Oct 12, 14:05").

### Calls
Android gives normal apps no call audio (SIM calls since Android 9; WhatsApp/
Zoom/Meet calls give other apps silence from the mic and can't be captured).
So the audio comes from the **phone's own call recorder** (Samsung: Phone →
Settings → Record calls), which saves SIM calls to `Recordings/Call`.

- **Detect calls**: SIM calls through the phone state; WhatsApp/Zoom/Meet
  calls through Android's in-call audio mode.
- **During the call**: notification "Process this call when it ends?" —
  **Yes / Always / No**. If the phone's call recorder is off, it says so and
  links to that setting.
- **When the call ends**: the new file in `Recordings/Call` is matched to the
  call (by time) and processed like a recording; it appears in the list titled
  with the contact name (or number) and time.
- WhatsApp/Zoom/Meet calls, and phones whose dialer doesn't save recordings
  to a readable folder (e.g. the Google dialer): the notification says the
  call can't be recorded on Android and suggests taking it on the PC.

### Permissions (asked when first needed, each explained)
Microphone (required), notifications, phone state (call detection), audio
files (reading `Recordings/Call`), and **Unrestricted battery** (Samsung stops
background work otherwise; the app opens that settings page).

## 3. Processing

- **Starts while recording** (owner's decision, 2026-10-13, to keep the wait
  after a meeting short): see "Processing while recording" below. Whatever
  is left starts automatically when the recording stops; a call is processed
  after it ends, per the Yes/Always/No choice.
- **One job at a time**, from a queue saved in the database; after a restart
  or the app being killed, a job resumes after its last finished step.
- Runs as a foreground service: "Processing · Weekly review · step 2 of 4 ·
  about 25 min left".
- Battery under 20% (owner, 2026-10-13) and not charging: waits, notification "Plug in to
  continue". Setting "Only process while charging". Phone hot (Android
  thermal status): slows down (fewer threads) instead of overheating.
- Time estimate shown before starting, from this phone's own measured speed
  per step (first time: the speed-test figures, by phone class).
- Models loaded one at a time and freed after each step (peak ~1.2 GB).

### Steps
1. **Cut at pauses**: Silero voice activity (as the desktop).
2. **Speech to text**: Parakeet on every piece; if Hindi or Gujarati is chosen,
   IndicConformer on every piece too; per piece and word, the right text is
   kept, by the desktop's method (`mixed.py`: timings, sounds, English word
   list). English-only settings skip IndicConformer. Adaptation needed: the
   desktop's method reads Whisper's word probabilities and language guess;
   on the phone Parakeet is the English reader, so its CTC token scores take
   that role (to be checked against the desktop's results). Translation to
   English is not in version 1 (Hindi/Gujarati are written as spoken).
3. **Who spoke when**: pyannote segmentation + CAM++ voices, clustered;
   the owner's lines are "Me" (voice profile, CAM++ embedding); names given to
   people are remembered across meetings.
4. **Summary and tasks**: Qwen reads the transcript in ~3,000-token pieces
   (12,000 characters, as the desktop), with the desktop's prompts.

Each step's result is saved before the next starts; a failed step keeps the
earlier results and offers **Retry** for that step only.

### Your name, vocabulary and Leave out (owner, 2026-10-13)
Settings → "You and your words", as on the desktop. They apply to transcripts
made from then on (owner's choice: existing ones stay as they are).
- **Leave out**: the desktop's rules exactly (`omit.rs` ported): whole words,
  any case and punctuation; phrases match in a row; "the the" → "the"; word
  timings stay in step.
- **Name and vocabulary**: Parakeet can't take hints (Whisper does on the
  desktop), so they work *after* recognition: a heard word, or a few in a row,
  that sounds very much like an entry becomes the entry as written. Cautious
  by the owner's choice ("rather miss fixing my name than change a right
  word"): an exact match always counts; a sound-alike only for words that are
  **not ordinary English** (the desktop's bundled SCOWL list, 47,540 words),
  of similar length, the same first two letters and close spelling; entries
  under 4 letters only match exactly. "Nishher" → Nishchay; "Nisha", "prize",
  "fine", "by" never change.

### Accuracy goal (owner, 2026-10-13)
Ordinary words must come out right: "fine" heard as "by" (owner's recording,
a 0.8 s phrase) is not acceptable in future versions. Leads, in order:
1. Pad each speech segment (e.g. 0.2–0.3 s before and after) before
   recognition — a late VAD start can clip a soft first sound ("f-").
2. Measure on the owner's own recordings (a small test set with the right
   words), before and after each change.
3. On phones fast enough, a bigger model (Parakeet 0.6B), or a transducer
   model with beam search and hotwords.

### Processing while recording
Speech to text needs only the audio so far, so it runs during the meeting;
speakers and tasks need the whole recording and run after Stop.

- Each finished 1-minute piece is cut at pauses and transcribed in the
  background while the next piece records. A phrase still going at a piece's
  end is carried over and transcribed with the next piece, so no word is cut.
- The live work uses **2 threads**, so recording never stutters; after Stop
  the rest uses 4.
- It waits (the pieces are then done after Stop, as before) when the battery
  is under 20% and not charging, when "Only process while charging" is on and
  the phone isn't charging, or when the phone is hot.
- Expected on the M31: English (Parakeet ~0.17× real time on 4 threads,
  ~0.3× on 2) keeps up, so after Stop only the last minute remains. With
  Hindi/Gujarati on, IndicConformer (~0.36× on 4 threads) is added and the
  two together fall behind on 2 threads; the backlog finishes after Stop on 4.
  Measured per phone and shown as the estimate.
- Transcript lines are saved as each piece finishes; the recording's screen
  shows them growing during the meeting.

### Models per phone (picked automatically)

| Phone | Speech | Speakers | Task AI |
|---|---|---|---|
| 4–6 GB RAM, or no ARM dot-product (e.g. the M31) | Parakeet 110M + IndicConformer int8 | segmentation 3.0 + CAM++ | Qwen3 0.6B |
| 8 GB+ RAM with ARM dot-product | same | same | Qwen3 1.7B |

**Open check:** task quality of Qwen3 0.6B. On the desktop even 1.7B missed
tasks that 4B found. Before building the tasks step, compare 0.6B, 1.7B and
4B on real transcripts on the PC. If 0.6B is poor, use 1.7B on every phone
(M31: ~24 min for that step).

Settings switches: **Speaker detection** on/off, **Find tasks** on/off.

## 4. Screens and data

### Screens (tabs: Record · Tasks · Settings)
- **Record**: big record button, timer, sound level, title field, Pause/Stop;
  a line showing what's processing. **Below it, all recordings and calls**
  (newest first), like the PC's Listen page, each with its status
  (recording, waiting, processing %, done, failed); swipe to delete with Undo.
- **Recording detail** (tap a recording): rename; player with the transcript
  (words light up as spoken, tap a word to jump); speaker names (rename,
  "remember this voice"); summary; its tasks; Retry if a step failed; Share
  (transcript or tasks as text).
- **Tasks**: all tasks, open and done; tick, edit, add, drag to reorder;
  "where it was said" plays from just before the quote.
- **Settings**: You and your words (name, vocabulary, Leave out; later: train
  your voice) · Languages (English,
  Hindi, Gujarati; which is spoken more) · Processing (speakers on/off, tasks
  on/off, only while charging) · Calls (detect calls; Ask / Always / Never;
  is the phone's call recorder on) · Models & storage (downloaded models and
  sizes, delete; delete audio after N days) · Permissions.
- **First start**: welcome → permissions → name and languages → model download
  (total size shown first, ~1.5 GB on the M31; Wi-Fi recommended; resumable).

### Plans
Each plan ends with a working app, tested on the M31:
1. Foundation and recording — **built** (2026-10-13).
2a. **English speech to text**: model download (first start), voice activity
   + Parakeet, the processing queue and its notification, processing while
   recording, transcript lines on the recording's screen.
2b. **Hindi/Gujarati**: IndicConformer int8 on onnxruntime (its decoding
   ported from `indic.py`), combined per word with Parakeet (`mixed.py`).
   Needs the owner to publish the int8 model once (see Model downloads).
3. Speakers. 4. Summary, tasks and the Tasks tab. 5. Calls.

### Data (SQLite)
- `meetings`: title, kind (recording | call), contact, started_at, duration,
  status (recording | queued | processing | waiting_charge | done | error),
  current step, error, summary, audio path.
- `transcript_lines`: meeting, index, start, end, speaker, text, words (timings).
- `tasks`: meeting, description, assigned_by, due, quote, done, position.
- `people`: name, voice embedding. Voice profile: a file.
- `jobs`: the processing queue (meeting, next step, attempts).
- `settings`.
- Audio: 1-minute pieces while recording, then one FLAC; optional deletion
  after N days (text kept).

### Model downloads
- sherpa-onnx models: sherpa-onnx's GitHub releases.
- Qwen GGUF: Hugging Face (unsloth), pinned files with SHA-256, as the desktop.
- **IndicConformer int8**: a prepared copy published once by the owner (e.g.
  a GitHub release of the project) with its MIT licence notice; phones can't
  make the int8 copy themselves (it needs the 2.4 GB float model in memory).
- The downloader resumes, checks SHA-256, and tries the other addresses of a
  host when one doesn't answer (this network can't reach one of GitHub's
  download addresses).

## 5. Errors and testing

### Errors
| Problem | Behaviour |
|---|---|
| Microphone refused | Record screen explains, button to settings |
| Storage low / full | Won't start below the margin; stops and saves if it fills |
| Model download fails | Resumes, checks SHA-256, tries other addresses, Try again |
| A step fails | Earlier steps kept; Retry reruns that step |
| App killed while processing | Resumes after the last finished step; the same step failing twice stops with a message naming the step and how to help (turn the step off, close other apps, Unrestricted battery) |
| No call recording after a call | Notification: turn on Phone → Settings → Record calls |
| WhatsApp/Zoom/Meet call | Notification: can't be recorded on Android, take it on the PC |

### Testing
- **Unit tests (Dart, on the PC)**: combining English and Hindi/Gujarati words
  (desktop `test_mixed.py` cases ported), transcript chunking and task-answer
  parsing (desktop `llm.rs` tests ported), model picking per phone, job queue
  resume, matching calls to recording files.
- **Same results as the desktop**: run the phone pipeline on "Gujarati Test"
  and other desktop meetings; compare with the desktop's transcripts.
- **Task-AI quality** (on the PC): Qwen3 0.6B vs 1.7B vs 4B on real
  transcripts (decides the open check above).
- **On the M31**: 30-min recording with the screen off; a real SIM call with
  the dialer's recorder on, processed end to end; time estimate vs actual;
  peak memory.
- Only the M31 can be tested; other phones rely on the measurements (later:
  a device-testing service such as Firebase Test Lab).
