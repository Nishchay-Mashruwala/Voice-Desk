# Status and next steps — handoff

Date: 2026-10-09, updated 2026-10-13 · Read this first when picking the work up again.

**Where we are (2026-10-13, afternoon):** desktop split done (part 2
uncommitted) · project reorganised into `desktop/{frontend,backend}` and
`mobile/{frontend,backend}` (uncommitted, section 0) · **mobile Plan 1
(recording) complete**: all tasks, final review, fix pass, checked on the M31 ·
**PC look applied** to the mobile app (owner approved) · **"process while
recording" approved and written into the spec** · **Plan 2a (English speech
to text on the phone) complete** — 13 tasks, final review, fix pass, checked
on the M31 — see "Plan 2a" below · next: 2b (Hindi/Gujarati), 3 speakers,
4 tasks, 5 calls.

Sections 2–3 below name folders as they were then (`frontend/`, `backend/`,
`backend/desktop/`); today they are `desktop/frontend/`, `desktop/backend/`,
`desktop/backend/app/`.

This file records what was done in the session of 2026-10-09, what is still
open, and the exact next step for each thread. Details of the design are in
[2026-10-09-frontend-backend-split-design.md](2026-10-09-frontend-backend-split-design.md).

## Owner's standing instructions

- **Don't commit** part 2's changes (or anything new) until the owner asks.
- Don't delete things outside the project (Ollama, caches) without asking.

## 0. Project layout (reorganised 2026-10-13) — DONE, NOT COMMITTED

Owner's request: each app in its own folder, each with its own `frontend/`
(UI) and `backend/` (logic).

```
Voice Desk Project/
  desktop/
    frontend/   React UI, tauri.mjs, package.json      (was frontend/)
    backend/    Rust workspace: Cargo.toml, target/    (was backend/)
      app/      the Tauri app                          (was backend/desktop/)
      core/     logic without Tauri
      engine/   Python speech engine
    scripts/    setup, installer, check-release        (was scripts/)
  mobile/
    frontend/   Flutter app `mobile_frontend`: lib/main.dart, lib/ui/,
                test/ui/, android/, ios/  — `flutter run` here
    backend/    Dart package `mobile_backend`: lib/data/, lib/engine/,
                lib/start.dart (openBackend), test/data/, test/engine/
  docs/superpowers/   specs/, plans/
  .github/  .gitignore  README.md  Setup Voice Desk (Windows).bat
  .venv/    the engine's dev Python (stays at the root; setup scripts and
            the dev app look for it two levels above desktop/backend)
```

- Moved with plain `mv` (part 2's deletions aren't staged, so `git mv` fails);
  git detects the renames when the owner commits.
- Updated: Cargo workspace members (`core`, `app`), dev `.venv` path in
  `app/src/lib.rs`, `tauri.mjs` → `../backend/app`, `.gitignore`, setup
  scripts (`.venv` one level above `desktop/`), `check-release.py`
  (`DESKTOP = "backend/app"`, paths relative to `desktop/`), the setup `.bat`,
  `.github/workflows/build.yml` (all paths under `desktop/`), README.
- Mobile: imports are `package:mobile_backend/...` and
  `package:mobile_frontend/...`; the frontend depends on the backend with
  `mobile_backend: {path: ../backend}`. Android glue (manifest,
  `MainActivity.kt` free-space channel, icons) stays in
  `mobile/frontend/android/` — it is part of the app shell.
- `.superpowers/` (the executing-plans skill's scratch folder: task briefs
  copied from the plan, test logs, the ledger) was deleted; the ledger is kept
  as [../plans/2026-10-12-mobile-plan-1-progress.md](../plans/2026-10-12-mobile-plan-1-progress.md).
- Verified: `cargo test` 71 pass, engine tests 62 pass, `npm run build`,
  debug app started and its engine loaded Whisper from the root `.venv`;
  mobile backend 28 tests + frontend 12 tests pass, `flutter analyze` clean
  in both; APK built from `mobile/frontend`, installed and started on the M31.
- `python desktop/scripts/check-release.py` reports files "not in git" until
  the moves are committed (expected).
- `npm run tauri dev` uses port 1420; when the owner's other project
  (Trailblaze) runs its vite dev server, that port is taken — stop it first.

## 1. Delete models that are in use — DONE

Settings → Storage can delete any downloaded model, also one the settings use
(the speech engine or task AI holding it is stopped first; refused while
recording/processing). Committed by the owner as `3f77214 Delete in-use`.

## 2. Frontend / backend split, part 1 — DONE, committed

Branch `restructure-frontend-backend` (not merged, not pushed):

| Commit | What |
|---|---|
| `fc40ca2` | Spec (part 1) |
| `c80fd9e` | Code moved into `frontend/` and `backend/` (`engine/`, `desktop/` = old `src-tauri/`), Rust workspace in `backend/`, `frontend/tauri.mjs` points the Tauri CLI at `backend/desktop` |
| `2195178` | `backend/core` crate with no Tauri (db, task AI, pipeline, engine client and setup, downloads, search, models); `Events` trait; desktop `AppState` wraps core's `Backend` via Deref |
| `8f0f01d` | Spec part 2 |

Verified then: all tests, dev app run and driven, release build.

## 3. Part 2: UI only in frontend, logic only in backend — DONE, NOT COMMITTED

All five steps of spec part 2 are implemented in the working tree
(41 changed files + 5 new: `backend/core/src/{catalog,rules,setup,transcript}.rs`,
`frontend/src/wording.ts`; `frontend/src/retime.ts` and `taskMarks.ts` deleted).

1. Transcripts: word re-timing and task marks in core `transcript.rs`;
   `meeting_transcript` command; edits take text only.
2. Models: catalog and fit rules in core `catalog.rs`; `model_options(draft)`
   (fixes the task-model Auto disagreement).
3. Setup: core `setup.rs`; `setup_plan(draft, choices)` and `setup_start(choices)`
   (`engine_install` / `llm_pull` commands removed from the UI).
4. Rules: core `rules.rs`; `save_settings` checks, clamps and returns the saved
   settings; `settings_rules`, `check_shortcut`, `command_phrases`,
   `open_task_count`; backend rejects empty titles/tasks, lists meetings only,
   keeps done tasks in place on reorder, enforces voice-training minimum.
5. Display text: backend and engine send ids/numbers (model ids like
   `whisper:medium`, stage ids, setup step ids, notice kinds, model `kind`);
   `frontend/src/wording.ts` words them. Errors stay as text.

Verified: 71 Rust tests, 62 engine tests, `npm run build`, dev app driven
(Listen, Settings, Meetings pages; save/reject paths). README module map updated.

Deliberate differences from the spec: the voice-training passage stays in the
frontend (it's wording); small UI affordances stay (disabled buttons on empty
input, can't untick the last language) though the backend also enforces them.

### Remaining for the split
- [ ] Commit part 2 when the owner asks (suggested: one commit; message
      "UI only in frontend, logic only in backend").
- [ ] `python desktop/scripts/check-release.py` fails until the four new core
      files and the moved folders are committed (expected).
- [ ] CI release build is unverified: `.github/workflows/build.yml` now runs
      `tauriScript: node desktop/frontend/tauri.mjs`. Run the workflow manually once
      (workflow_dispatch) before the next tag.
- [ ] Merge `restructure-frontend-backend` into `main` (owner's call).
- [ ] Mark the split spec's status as done.

## 4. Cleanup — DONE by the owner

- The old 45 GB Rust build folder was cleaned (now `desktop/backend/target`,
  rebuilt as needed).
- **Ollama is not used** by Voice Desk (task AI is its own `llama-server`);
  the owner uninstalled it.
- Nothing in `.github/`, `desktop/scripts/`, `docs/` or the setup `.bat` is unused.

## 5. Mobile app (Flutter) — IN PROGRESS

Decisions: Flutter (Dart), Android first; local-first (records and stores on
the phone; every data call behind one repository layer) so the **server can be
added later** (an HTTP program around `desktop/backend/core` + `engine`).
Planned packages: `record`, `just_audio`, `flutter_foreground_task` (recording
with the screen off), `drift` or `sqflite`, `riverpod`, later `dio`.

### Done
- Flutter 3.47.7 stable installed by git clone at `C:\src\flutter`;
  `C:\src\flutter\bin` added to the **user PATH** (winget has no Flutter
  package). VS Code must be fully restarted for its terminals to see it.
- Android Studio installed; Android SDK 36 at
  `C:\Users\Rajvee\AppData\Local\Android\Sdk`; `flutter doctor`: no issues.
- Owner's phone: Samsung Galaxy M31 (**SM M315F**), USB debugging on, detected
  by `flutter devices`.
- Project created by the owner: `mobile/` (`flutter create --org com.rajvee
  --platforms android,ios mobile`); untracked in git. Since 2026-10-13 the
  app is in `mobile/frontend/` and its logic in `mobile/backend/` (section 0).

### Build fixed (2026-10-12)
- **Gradle download** (was the blocker): one of GitHub's download IPs,
  `185.199.109.133` (`release-assets.githubusercontent.com`), is unreachable
  from this network; Java picked it and timed out. Fixed by downloading
  `gradle-9.3.1-all.zip` with curl, checking its SHA-256 against
  services.gradle.org (match), and placing it in
  `C:\Users\Rajvee\.gradle\wrapper\dists\gradle-9.3.1-all\9ot9r568e8zfvvd4mn8rbu1j0\`.
  If a future Gradle version is needed, the same problem may recur: same fix.
- **Android NDK 28.2.13676358** was missing, and Gradle's automatic install
  fails with the new Android CLI. Installed with
  `%LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest\bin\android.exe sdk install "ndk/28.2.13676358"`
  (new package naming: `ndk/<version>`, not `ndk;<version>`).
- `flutter build apk --debug` in `mobile/frontend/` succeeds
  (`build\app\outputs\flutter-apk\app-debug.apk`). Gradle's
  "restricted method in java.lang.System" warnings are harmless.

### Next steps
1. ~~Fix the Gradle download~~ (done).
2. ~~Run on the phone~~ (done 2026-10-12): `flutter run -d RZ8N723F3XW`
   installs and opens the demo app (titled "Voice Desk") on the Galaxy M31
   (Android 12); package `com.rajvee.mobile`. Day to day the owner runs
   `flutter run` in `mobile/frontend/` for hot reload.
3. Plan the app with the owner (brainstorming → spec). **In progress** — see
   "Mobile app planning" below.
4. Then build: recording first, then the meetings list, then tasks.

### Mobile app planning (brainstorming, 2026-10-12)
Owner's answers so far:
- Version 1 must **record and process** (transcripts + tasks), **on the phone**
  (no server/PC), Android phones with **4 GB RAM+** (not only the M31; models
  picked per phone like the desktop's Auto), languages **English + Hindi/
  Gujarati written as spoken**, **who said what** (speaker detection).
- Acceptable wait: **up to ~15 min for a 30-min meeting**.
- Approach **A**: Flutter app + on-device runtimes (sherpa-onnx, onnxruntime,
  llama.cpp); processing logic in Dart under `lib/engine` + `lib/data`, UI in
  `lib/ui` (now `mobile/backend/lib/{engine,data}` and `mobile/frontend/lib/ui`).

Speed test on the Galaxy M31 (Exynos 9611, 4×A73 2.3 GHz + 4×A53, no ARM
dot-product instructions, 5.7 GB RAM), 4 threads, the owner's 108 s
"Gujarati Test" meeting (mic + system mixed to 16 kHz mono):

| Step | Model | Time / audio | 30-min meeting | Peak RAM | Quality |
|---|---|---|---|---|---|
| English speech | Whisper base int8 (sherpa) | 0.83× | ~25 min | 0.6 GB | English ok, Gujarati junk loops |
| English speech | **Parakeet TDT-CTC 110M int8** (sherpa, NeMo CTC) | **0.17×** | **~5 min** | 0.4 GB | English good |
| All languages | Omnilingual ASR 300M CTC int8 | 1.05× | ~32 min | 1.0 GB | some Gujarati good, English bad |
| Hindi/Gujarati | **IndicConformer 600M int8 encoder** (onnxruntime 1.31) | **0.36×** (+ decoding) | **~12–13 min** if on all audio | 1.0 GB | (desktop quality) |
| Speakers | pyannote seg + eres2net, 1 thread | 4.0× | ~2 h | 0.3 GB | |
| Speakers | pyannote seg + **CAM++** (4 threads) | 0.73× | ~22 min | 0.2 GB | |
| Task AI | Qwen3 0.6B Q4_K_M (llama.cpp) | pp 14.8 t/s, tg 12.4 t/s | ~11 min (3 chunks of 3k tokens) | 0.8 GB | |
| Task AI | Qwen3 1.7B Q4_K_M | pp 7.3 t/s, tg 4.2 t/s | ~24 min | 1.2 GB | |

Conclusion: on the M31 the full pipeline takes ~50–60 min for a 30-min
meeting (transcription alone ~15–18 min); 15 min is not reachable there with
everything on. Phones with ARMv8.2 dot-product (most mid/high-range from
~2020–21 on) should be roughly 2–4× faster, especially the task AI.
Owner chose: weaker phones get **every feature, just slower** (time shown).
Design agreed in 5 parts and written to
[2026-10-12-mobile-app-design.md](2026-10-12-mobile-app-design.md)
(not committed). Additions agreed during design: **call detection** (offer
"Process this call when it ends?"; audio from the phone's own call recorder
in `Recordings/Call`), and the recordings list **below the Record button**
(tabs: Record · Tasks · Settings).
Owner approved the spec ("start building"). Split into 5 plans, each ending
with a working app: 1 foundation + recording · 2 models + speech to text ·
3 speakers · 4 task AI + Tasks tab · 5 calls. **Plan 1 written:**
[../plans/2026-10-12-mobile-plan-1-recording.md](../plans/2026-10-12-mobile-plan-1-recording.md)
(10 tasks). Owner chose to have it built inline in the session.

### Plan 1 build — status (2026-10-12)
Progress record (ledger, rulings):
[../plans/2026-10-12-mobile-plan-1-progress.md](../plans/2026-10-12-mobile-plan-1-progress.md).
When resuming with the executing-plans skill, start its ledger from that file.
Nothing committed; `mobile/` is untracked.

**Tasks 1–9: DONE** — `flutter test`: 40 tests pass (28 in `mobile/backend`,
12 in `mobile/frontend`); `flutter analyze`: clean. Paths in the table are
relative to `mobile/frontend/` (`lib/main.dart`, `lib/ui/`, `MainActivity.kt`,
manifest) or `mobile/backend/` (`lib/engine/`, `lib/data/`).

| Task | What | Files |
|---|---|---|
| 1 | Packages, `minSdk = 26`, tabs Record · Tasks · Settings | `lib/main.dart`, `lib/ui/app.dart`, `lib/ui/tasks/` |
| 2 | WAV helpers (header, repair after crash, duration) | `lib/engine/audio/wav.dart` |
| 3 | 1-minute piece writer | `lib/engine/audio/piece_writer.dart` |
| 4 | drift DB (`Meetings`, `Settings`) + `RecordingsRepository` (create, list, rename, delete, recover) | `lib/data/` |
| 5 | Free storage (Kotlin StatFs channel `voicedesk/storage`) | `lib/engine/audio/free_space.dart`, `MainActivity.kt` |
| 6 | Recorder controller + mic source + foreground notification (Pause/Resume/Stop) | `lib/engine/audio/recorder_controller.dart`, `audio_source.dart`, `recording_notification.dart`, manifest |
| 7 | Record screen with recordings list below, swipe delete + Undo, battery dialog | `lib/ui/record/`, `lib/ui/wording.dart`, `lib/engine/permissions.dart` |
| 8 | Recording detail: player across pieces, rename, delete | `lib/ui/recording/`, `lib/engine/audio/player.dart` |
| 9 | Settings (permissions + version), start-up recovery of interrupted recordings | `lib/ui/settings/`, `lib/main.dart` |

Rulings made while building (full list in the ledger): `permission_handler`
pinned to 12.x (13.x needs compileSdk 37); SnackBar `persist: false` (Flutter
3.47 keeps SnackBars with an action forever, so swipe-deletes never happened);
`package_info_plus` added; app label "Voice Desk"; stop waits ≤ 2 s for the mic
stream; leftover recording notification stopped at start-up.

**Owner's extra request — app icon: DONE.** Adaptive launcher icon built from
the desktop's `desktop/backend/app/icons/app-icon.png` (gradient background layer +
microphone cut out by brightness, scaled into the safe zone), legacy PNGs, and
a white microphone status-bar icon (`res/drawable/ic_notification.xml`,
manifest meta-data `com.rajvee.mobile.NOTIFICATION_ICON`). Generator script:
the session scratchpad `make_icons.py` (re-create it if icons need redoing:
background = bilinear of corner colours (129,70,250) (59,135,250) (55,38,223)
(35,87,200) darkened to (14,21,65) in the middle; mic alpha = smoothstep on
min(R,G,B) from 60 to 110 within box (230,130,800,935); mic height 0.56 of the
layer). Checked on the phone: home screen icon complete.

**Task 10 (on the Galaxy M31): DONE (2026-10-13).**
- ✅ Recording with the **screen off** (notification counted past 2:20).
- ✅ Notification shows the white mic icon, "Recording · mm:ss"; **Pause /
  Resume / Stop** from the notification work (Paused · 01:47 → Recording ·
  01:51 → saved 01:58).
- ✅ **1-minute pieces** correct on disk (`app_flutter/recordings/<id>/`, full
  piece = 1,920,044 bytes).
- ✅ **Crash/kill recovery**: a recording cut off by reinstalling came back as
  5:13, "Waiting to be processed".
- ✅ **Playback** across pieces, after 4 fixes (each with a test that failed
  first): the detail screen's player was thrown away at once (`playerProvider`
  is autoDispose and was only `ref.read`; now held with `ref.listenManual`);
  the Pause button stayed after the end (now stops and goes back to the
  start); the time after a seek into another piece showed the wrong minute
  (just_audio reports the new position before the new piece; `JustAudioPlayer`
  now computes it); a seek finishing after the screen closed no longer throws.
- ✅ Rename, blank rename → default title, swipe delete + Undo keeps it,
  swipe delete without Undo deletes it, delete from the detail screen removes
  its folder.
- ✅ Fixed: stopping from the **notification** now clears the title field
  (`RecordScreen` clears it whenever the recorder goes back to idle).
- Tests now: 31 in `mobile/backend` (new `test/engine/audio/player_test.dart`
  with a fake just_audio plugin), 14 in `mobile/frontend`.
- Owner tested on the phone too (made recordings 16:25, 16:29 "Meeting",
  16:32): app works for them.

Driving the phone from the PC: helper `phone.sh` in the session scratchpad
(`tap "<label>"`, `texts`, `shot <name>`); `uiautomator dump` sometimes
returns "null root node" — retry. The phone locks after 60 s: `wake` in
`phone.sh` wakes it and swipes the lock away. The `uiautomator` text of a
changing time can be stale — check times with screenshots. A 5-second Undo
bar is too short for `tap "Undo"` (two dumps): tap its spot (936, 1936).

**After Task 10: final review** of all of Plan 1 (fresh reviewer, per the
executing-plans skill), fix Critical/Important findings, report rulings.

### Plan 1 final review and fix pass (2026-10-13) — DONE
Fresh reviewer: 1 Critical, 4 Important, 12 Minor. Fixed, each with a test
that failed first, and checked on the M31:
- **Back / swiping the app from Recents stopped the recording** while the
  notification kept saying "Recording" (confirmed: 8 s of audio). Now the
  Flutter engine starts with the process (`VoiceDeskApplication.kt`, cached
  engine) so closing the window doesn't stop the recorder; the service no
  longer auto-restarts after a kill, and stops itself if Android restarts it.
- **Any other sound (a video, a voice note, Voice Desk's own player) paused
  the recording for good** — seen live at 13:11. `audioInterruption: none`.
- Double tap on Record / failures during start or writing could leave the mic
  on or an unstoppable "Recording": new `starting` phase, best-effort stop.
- A live recording can't be deleted/played from its screen.
- Android Auto Backup turned off (`allowBackup="false"`): recordings would
  otherwise go to Google Drive.
- Minors deferred (in the ledger): permanently refused permissions in
  Settings, messages that never clear, permission explanations, rebuilds per
  audio chunk, slider seeking per drag frame, piece names after 16.7 h, a few
  decisions still in screens, storage-full notification, test temp folders.
- Tests now: 43 backend, 26 frontend. Test recordings left on the phone
  (13 Oct 13:02, 13:07, 13:10, 13:22, 13:27) — the owner can delete them.

### PC look (2026-10-13) — DONE
`mobile/frontend/lib/ui/theme.dart` (the desktop's colours, light/dark),
`widgets/orb.dart` (round gradient mic with glow, red rings while recording,
amber when paused), `widgets/page_header.dart` ("Speak, and it *writes*."),
`widgets/badge.dart` (status badges); cards on every screen.

### Plan 2a — English speech to text on the phone (2026-10-13) — COMPLETE
Plan: [../plans/2026-10-13-mobile-plan-2a-english-speech.md](../plans/2026-10-13-mobile-plan-2a-english-speech.md).
Ledger (39 rulings, 8 deferred minors): [../plans/2026-10-13-mobile-plan-2a-progress.md](../plans/2026-10-13-mobile-plan-2a-progress.md).
Final review: 0 Critical, 5 Important + 3 raised from Minor, all fixed with
tests: engine failures no longer leave a recording stuck or hang processing;
battery/heat apply during a job; a stalled download can be retried; a
downloaded archive is reused and unpacking needs ~265 MB; "Plug in to
continue" notification while waiting; no clipped first word at the Stop
handover; a double tap downloads once; Stop in the notification hands the
service to processing without stopping it (checked on the M31).
Owner's change: processing waits under **20%** battery (not 30%).
- Model: Silero VAD + Parakeet 110M int8, downloaded once (105 MB; resumable,
  SHA-256 checked, tries other addresses) and unpacked on the phone; Record
  screen banner and a Settings card; "Only process while charging" switch.
- Processing: one recording at a time, resumes after the last saved line;
  **while recording**, each finished minute is turned into text (2 threads);
  after Stop the rest (4 threads); waits on low battery / heat; one shared
  foreground service shows "Processing · 40% · about 3 min left".
- Screens: processing line, "Processing 40%" badges, the transcript on a
  recording's screen (tap a line to play from it, playing line highlighted).
- On the M31: download ~50 s + unpack ~75 s; the 10 waiting recordings
  (13.9 min, mostly silence) done in ~2.8 min; the owner's speech readable;
  kill during Stop recovered and resumed; idle memory 438 MB (debug build).
- **Still to see on the phone:** lines appearing *during* a recording with
  real speech (the PC's test voice was too quiet for the voice detector) and
  peak memory while processing — needs someone speaking ~2 min near the phone.
- The owner's own speech on the M31: "Mike testing one, two, three", "I get it.
  We have to do this task then we will complete it" — accurate.
- Tests: 119 backend (incl. 2 real-model tests on the PC with
  `VOICEDESK_TEST_MODELS`/`VOICEDESK_SHERPA_LIB`), 42 frontend.
- Gotchas: Windows' System32 has a 3 kB `onnxruntime.dll` stub (tests preload
  the real one); a closure sent to `Isolate.run` must not capture providers;
  the debug APK is now 265 MB (sherpa-onnx for 4 ABIs; release: split per ABI).

### After Plan 2a (owner's requests, 2026-10-13) — DONE
- Recording screen: title no longer a box touching the "Done" tag.
- Portrait only (Android manifest + SystemChrome; iOS Info.plist too).
- **Word-by-word highlighting** while playing (as on the PC); tap a word to
  play from it; the transcript follows the playing word.
- **Settings → You and your words**: name, vocabulary, Leave out — applied to
  new transcripts (see the spec's "Your name, vocabulary and Leave out").
- **Accuracy goal** written into the spec: ordinary words like "fine" must not
  come out as "by"; first lead: pad speech segments before recognition.
- Tests: backend 135, frontend 48.

### Owner's requests waiting (2026-10-12), to agree before building
(Both approved 2026-10-13: the PC look is built; processing while recording
is in the spec and Plan 2a.)
1. **UI like the PC app.** Proposed: dark theme, the desktop's purple accent and
   gradient, logo, the round mic button with glow ("Speak, and it writes."),
   cards for sections, same wording style. Look at `desktop/frontend/src/styles.css`
   and `desktop/frontend/src/views/Listen.tsx` for colours and layout. Not started.
2. **Processing must not take too long.** Proposed (needs owner's OK; it
   changes the spec): **process while recording** — transcribe each 1-minute
   piece during the meeting (on the M31 transcription runs at ~0.53× real
   time, so it keeps up), and compute speaker voice prints per piece too;
   after Stop only the last piece, the speaker clustering and the task AI
   remain → estimated ~15–25 min after a 30-min meeting on the M31 instead of
   ~60, much less on newer phones. Plus tuning: IndicConformer only on pieces
   that aren't clearly English; speaker-detection step size. This shapes
   Plans 2–4 (not written yet).

### Mobile plans still to write and build
2 Models + speech to text (incl. first-start flow, queue, processing service,
FLAC after processing) · 3 Speakers · 4 Task AI + Tasks tab (first: compare
Qwen3 0.6B vs 1.7B vs 4B task quality on PC) · 5 Calls. Each: spec section →
plan → build → test on the phone.

Test leftovers kept until the design is decided (delete afterwards):
`C:\src\vdspeed` (llama.cpp build, Qwen GGUFs, onnxruntime AAR, ort_bench)
and the session scratchpad `speedtest` folder (sherpa binaries, models, audio).
Phone test folder `/data/local/tmp/vdspeed` already deleted. Android SDK
`cmake/4.1.2` was installed for the llama.cpp build (keep; the app will need it).

## Gotchas learnt this session
- After folder renames, Rust builds fail with "failed to read plugin
  permissions … Voice Project\src-tauri\…": run
  `cargo clean -p tauri -p tauri-plugin-*` (and `--release` for release builds).
- `npm run tauri …` must be run from `desktop/frontend/` (it uses `tauri.mjs`).
- Flutter: `flutter run` / app tests in `mobile/frontend/`; logic tests and
  `dart run build_runner build` (database code) in `mobile/backend/`.
- `flutter run` stuck on "Connecting to the VM Service is taking longer than
  expected…" (no `r` key list): Flutter read a stale "Dart VM service is
  listening" line in the phone's logcat from an earlier run (e.g. a
  `--no-resident` launch) and kept retrying that dead port. Fix: stop it,
  `adb -s RZ8N723F3XW logcat -c`, run again. Don't use `--no-resident` for
  launches the owner will then `flutter run` against.
- The dev app can be driven for testing with
  `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222` and the
  DevTools protocol (`window.__TAURI_INTERNALS__.invoke(...)`).
