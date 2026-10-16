# Mobile app, Plan 2c-b: Everyday tools — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The rest of Part B:
- copy or share a transcript;
- recordings kept as verified FLAC;
- audio kept for N days (the text stays);
- the recordings part of Settings → Storage;
- a first-start setup;
- Licences & credits;
- Process again is blocked for recordings whose audio is gone.

**Architecture:**
- **FLAC:** a small pure-Dart encoder/decoder (fixed predictors + Rice coding, RFC 9639), testable on the PC; no FFmpeg, no platform code. It streams: a 2-hour recording never sits in memory.
- **Upkeep:** compressing finished recordings and deleting old audio run in the processor's loop when it has no speech job, so it is still one job at a time. The loop runs at app start and after every job.
- **Reading audio:** everything that reads audio goes through `pieces()` / `readSamples` / `audioDuration`, which take either the WAV pieces or `audio.flac`.
- **Screens:** the first-start setup is a full-screen flow in the frontend, shown before the tabs until `setup_done`.

**Tech Stack:** as Plan 3. Two additions:
- **`share_plus`** (frontend) for Android's share sheet. Choose an exact version at least two weeks old with `flutter pub add`; the clipboard is Flutter's own `Clipboard`.
- **Tests only:** a PC check with Python `soundfile` (libsndfile) in a scratch venv.

drift schema 5 → 6.

**Spec:** [docs/superpowers/specs/2026-10-14-mobile-next-features-design.md](../specs/2026-10-14-mobile-next-features-design.md), Part B: B2, B4, B5, B6 (the recordings part; the models part is built), B7, B8; the Errors and Testing sections. Owner, 2026-10-15, item 3: "copy or share a transcript, smaller audio files (FLAC), keeping recordings for N days, recordings in the Storage page, first-start setup, a Licences & credits page". Also from the 2026-10-15 list: block Process again for recordings without audio.

**Not in this plan:** summary and tasks (Plan 4), calls (Plan 5), the desktop.

## Global Constraints

- **The owner commits.** "Checkpoint" = `flutter test` + `flutter analyze` in the touched packages.
  - Never run `dart format`: the backend is laid out by hand in the old style, the frontend in the tall style. Match the file you are in.
  - The phone is reached over Wi-Fi (adb wireless debugging). Install only when the app's foreground service isn't running.
- **FLAC (B4):**
  - Lossless, 16 kHz mono 16-bit. Fixed block size 4096 samples (the last frame shorter).
  - Metadata: STREAMINFO, then a SEEKTABLE with a point every 10 s (160,000 samples) starting at sample 0.
  - Saved as `audio.flac` in the recording's folder. It is written to `audio.flac.part` first and renamed only after the check.
  - The check: the FLAC is decoded back and compared sample for sample with the pieces. Only if they are identical are the pieces deleted, and `audioPath` set to the FLAC's path.
  - When: after a recording's processing ends (done or failed), and at app start for any done or failed recording that still has pieces. Recordings that are recording, queued, processing or waiting for charge are never converted.
  - A failed check keeps the pieces and tries again at the next start. After 3 failures: "Couldn't compress this recording's audio; it's kept as it was" (on its screen).
- **Keep recordings for (B5):**
  - Settings key `keep_audio_days`. Choices: Forever (0) · 7 days · 30 days · 90 days · 1 year (365). Default 30.
  - Hint: "Older recordings' audio is deleted; their text stays."
  - Applies to recordings whose start is older than N days **and whose status is done**. Only their audio files go: `audioDeleted` is set and `audioPath` cleared. Title, transcript, words, speakers and summary stay.
  - Runs at app start and after each job.
  - Shortening the period asks first: "Delete the audio of N recordings older than X now? Their text stays." (X: "7 days", "30 days", "90 days", "1 year").
  - Afterwards the recording's screen hides the player and says "The audio for this recording is no longer available.". Tapping words does nothing. Its tile badge reads "Text only". **Process again is off** (as are Play and seeking).
- **Copy / share (B2):**
  - The recording's screen header gets a Share button (`Key('share-button')`), offered when the recording has lines. It opens a menu: "Copy transcript" (snack "Copied to clipboard") · "Share…" (Android share sheet, plain text). The line menu gets "Copy this line" (that line's text; snack "Copied to clipboard").
  - The format:
    ```
    Weekly review
    14 Oct 2026, 14:05 · 32 min

    [00:02] Me: Good morning, shall we start?
    [00:05] Kiran: Yes. હા, આજે બે વાત છે.
    ```
  - A new `[mm:ss]` line each time the speaker changes; lines of the same speaker are joined with a space.
  - Times are `[h:mm:ss]` past an hour.
  - Lines without speakers: each line is `[mm:ss] text`.
  - Length *(builder's call)*: whole minutes rounded, at least "1 min"; from an hour: "1 h 05 min".
- **Storage (B6):**
  - "On this phone": Recordings X · Models X · App data X (the database file) · Free space X.
  - "Recordings": the total audio size and count, the "Keep recordings for" choice, and the recordings with audio, largest first. Each row shows its title, size and **Delete**: the whole recording, with the same confirm as on its screen ("Delete this recording?" / "Its audio is removed from the phone."), then a snack "Recording deleted" with Undo; the delete happens when the snack times out, as on the Record screen.
  - Then the existing "Downloaded models" list.
- **First start (B7):**
  - Shown once, full screen, before the tabs, while settings key `setup_done` isn't `true`. Back and Next on every step but the first. Steps:
  1. **Welcome:** the orb, "Speak, and it writes." and "Voice Desk records your meetings and turns them into text — all on this phone, even offline." Button **Get started**.
  2. **Permissions:** Microphone "to record"; Notifications "to show and stop a recording"; Unrestricted battery "so Android doesn't stop a long recording". Each has an **Allow** button, or the green "Allowed" (Settings' check and wording). Next is always on.
  3. **About you:** "Your name" (placeholder "e.g. Nishchay", hint "How people say your name in meetings."); "Other names people call you"; the Languages chips and "which do you speak more" (Settings → Speech's own widgets). Saved when you move on. The name is optional.
  4. **Your voice:** "Train my voice" (opens the training screen), or **Skip**. Shows "Voice saved <d MMM yyyy>" once trained.
  5. **Download:**
     - The models the choices need, each with its size, and the total.
     - "Wi-Fi recommended. If it's interrupted, it continues where it stopped."
     - **Download (X MB)**, then progress.
     - **"Use the app while it downloads"** finishes the setup; the download goes on and the Record banner shows it.
     - When all are on the phone: "Voice Desk is ready — it works offline from now on." and **Start**.
     - With nothing to download, it goes straight to that message.
  - **On a phone already in use** (the owner's): it shows once after the update. The fields come filled from the settings, and the models are marked "Downloaded".
- **Licences & credits (B8):**
  - Settings → About → "Licences & credits" opens a credits list. Each row shows its credit text, licence name and link. A button "All licences" opens Flutter's `showLicensePage`, to which the model licence texts are added with `LicenseRegistry.addLicense`.
  - The rows:
    - "Speech model by NVIDIA (Parakeet), CC BY 4.0; converted to ONNX int8 by the sherpa-onnx project." (both English models);
    - IndicConformer by AI4Bharat, MIT;
    - the phone versions of IndicConformer by Parismita Global Solutions, Apache-2.0;
    - Silero VAD, MIT;
    - the CAM++ voice model from 3D-Speaker, Apache-2.0;
    - sherpa-onnx, Apache-2.0;
    - the English word list, from the en_US Hunspell dictionary (SCOWL size 60, wordlist.aspell.net), with its copyright notice.
  - Each licence text is copied verbatim from its official source into `mobile/frontend/assets/licences/`. pyannote is not used, so it is not listed.
- **Errors (spec table):** FLAC check failures are silent until the third. Audio deleted: the sentence above, and no player.

## Review Focus

- **The app killed in the middle of compressing.** Expected: the pieces are untouched. The leftover `audio.flac.part` is removed and the conversion done again next time. Task 3 test `a half-written FLAC from a killed app is redone`.
- **Process again or Try again on a compressed recording**, including a resume from the middle (`processedMs` > 0). Expected: it reads the FLAC from that point, with the same samples the pieces had. Task 2 test `reading from the middle of a FLAC gives the pieces' samples`.
- **Keep recordings for N days with a failed or waiting recording older than N days.** Expected: untouched, so Try again still has audio. Task 4 test `retention never touches unfinished recordings`.
- **A recording whose audio was deleted.** Expected: no player, words don't play, Process again off, Share and Copy still work. Task 4 screen test `a text-only recording can be read and shared, not played or processed again`.
- **A recording processed again while it is being compressed.** Expected: the compression finishes first (one job at a time); the new run then reads the FLAC. Task 3 test `upkeep and speech jobs take turns`.

---

### Task 1: FLAC encoder and decoder (pure Dart)

**Files:**
- Create: `mobile/backend/lib/engine/audio/flac.dart`
- Test: `mobile/backend/test/engine/audio/flac_test.dart`, PC check script `mobile/backend/tool/flac_check.py`

**Interfaces:**
- Produces:
  - `const kFlacBlock = 4096; const kSeekEverySamples = 160000;`
  - `Future<void> writeFlac(Stream<Int16List> samples, File out)`: streams 16 kHz mono 16-bit samples to a FLAC file. It reserves the metadata blocks, writes frames as samples arrive, then goes back to fill STREAMINFO (total samples, min/max block and frame sizes; MD5 left as zeros, "unknown") and the SEEKTABLE.
  - `class FlacInfo { int totalSamples; List<(int sample, int offset)> seekPoints; int firstFrameOffset; }` and `Future<FlacInfo> readFlacInfo(File f)`.
  - `Stream<Int16List> readFlac(File f, {int fromSample = 0})`: decodes from the seek point at or before `fromSample`, skips to `fromSample` exactly, and yields one frame's samples at a time. It reads what `writeFlac` writes: CONSTANT, VERBATIM, and FIXED orders 0–4 with Rice partitions. Anything else throws `FormatException`.
  - `Duration flacDuration(File f)` (from STREAMINFO, synchronous; used where `wavDuration` is).
- Encoding choices:
  - Per frame, try CONSTANT, then FIXED orders 0–4, choosing for each the Rice partition order 0–8 with the best parameter per partition. Keep the smallest, falling back to VERBATIM.
  - Frame header: sync for a fixed block size; block size code 4096, or "8/16-bit block size at the end" for the last frame; sample rate code 16 kHz; mono; 16-bit; frame number in UTF-8 coding; CRC-8. Footer: CRC-16 (both as RFC 9639).

- [ ] **Step 1: Write the failing tests**
  - `silence, a tone and noise come back exactly`: 3 signals of 10 s each, plus one of 4096 × 3 + 17 samples (a short last frame). Expect `readFlac` output == input.
  - `speech is smaller than the WAV`: a 20 s synthetic tone + noise. Expect the file under 75% of 20 × 32000 bytes. (Real speech is checked on the PC script.)
  - `the seek table has a point every 10 s from the start`: 35 s → points at samples 0, 160000, 320000, 480000. Each offset is the start of a frame whose first sample is that sample.
  - `reading from a sample gives the samples from there`: `readFlac(f, fromSample: 170001)` equals input[170001..].
  - `frames carry valid CRCs`: recompute CRC-8/CRC-16 over each frame and expect a match.
  - `a file that isn't ours is refused`: random bytes → `FormatException`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement** in `flac.dart`, as RFC 9639. Bit writer and reader classes are private to the file.
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: PC check:** `tool/flac_check.py <file.flac> <file.wav>` reads the FLAC with Python `soundfile` (libsndfile) and compares it with the WAV.
  - Run it on a FLAC made from `rec17.wav` (VOICEDESK_TEST_AUDIO) by a test helper guarded by that variable: `real speech round-trips and libsndfile reads it`.
  - Expected: identical, and the size printed (about 50–60% of the WAV).
- [ ] **Step 6: Checkpoint.**

### Task 2: Everything that reads audio reads either form

**Files:**
- Modify: `mobile/backend/lib/engine/audio/pcm_reader.dart`, `wav.dart`, `player.dart`, `mobile/backend/lib/data/recordings_repository.dart`
- Test: `mobile/backend/test/engine/audio/pcm_reader_test.dart`, `recordings_repository_test.dart`

**Interfaces:**
- Consumes: Task 1's `readFlac`, `flacDuration`.
- Produces:
  - `Duration audioDuration(File f)`: by the extension (`.flac` → `flacDuration`, else `wavDuration`). `totalMs` and `JustAudioPlayer.load` use it.
  - `readSamples(pieces, fromMs, toMs, chunkMs)` takes `[audio.flac]` too (same chunks, same values).
  - `RecordingsRepository.pieces(id)` returns `[audio.flac]` when it exists and no WAV piece is newer, else the WAV pieces (a leftover `audio.flac.part` is ignored).

- [ ] **Step 1: Write the failing tests:**
  - `reading a FLAC gives the samples the pieces had`;
  - `reading from the middle of a FLAC gives the pieces' samples` (`fromMs: 61234`, across a piece boundary, `toMs` set);
  - `pieces are the FLAC once there is one`;
  - `a FLAC's length is its samples`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.** `readSamples` converts the FLAC's Int16 frames into the same `chunkMs` Float32 chunks as for WAV.
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 3: Compressing finished recordings (upkeep in the processor's loop)

**Files:**
- Create: `mobile/backend/lib/engine/audio/compress.dart`
- Modify: `mobile/backend/lib/data/db.dart` (+g; schema 6), `recording.dart`, `recordings_repository.dart`, `mobile/backend/lib/engine/pipeline/processor.dart`
- Test: `mobile/backend/test/engine/audio/compress_test.dart`, `processor_test.dart`, `migration_test.dart`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  - **Schema 6:** `Meetings.audioDeleted` (bool, default false) and `Meetings.flacFailures` (int, default 0). Migration from 5.
  - `Recording.audioDeleted` (bool) and `Recording.compressFailed` (bool, `flacFailures >= 3`).
  - `Future<bool> compressPieces(List<File> pieces, Directory dir)`, run in `Isolate.run`. It removes a leftover `audio.flac.part`, writes `audio.flac.part` from the pieces, decodes it back comparing sample for sample, then renames it to `audio.flac`. It returns false on any mismatch or error, deleting the `.part`. It never deletes pieces.
  - `RecordingsRepository`:
    - `Future<List<Recording>> toCompress()`: done or error, not `audioDeleted`, with WAV pieces;
    - `Future<void> compressed(int id)`: deletes the pieces once `audio.flac` exists and the status is still done or error, and sets `audioPath`;
    - `Future<void> countCompressFailure(int id)`: `flacFailures += 1`.
  - **The processor:** `_upkeep()` runs when the loop finds no speech job it may run now (no work, waiting for a model or for charge). It goes through `toCompress()` one recording at a time, then runs Task 4's retention. It stops as soon as a speech job is waiting (kick → `_again`).
    - A FLAC that was written but whose pieces were kept (the recording went back into processing) gets them deleted on a later pass.
    - `ProcessingState` stays idle during upkeep (no notification).
  - Screen: a done/failed recording with `compressFailed` shows "Couldn't compress this recording's audio; it's kept as it was" (muted, above the transcript).

- [ ] **Step 1: Write the failing tests.**
  - `a finished recording becomes one FLAC, and its pieces go`;
  - `a FLAC that doesn't match keeps the pieces and counts a failure` (inject a corrupting writer through a test hook on `compressPieces`);
  - `a half-written FLAC from a killed app is redone` (a stale `.part` beside the pieces);
  - `recordings still to be processed are not compressed` (queued, processing, waiting for charge, recording);
  - `upkeep and speech jobs take turns` (a recording queued during compression is processed after it, from the FLAC);
  - `the third failure says so` (screen);
  - migration `a version-5 database opens as version 6`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 4: Keep recordings for N days, and text-only recordings

**Files:**
- Create: `mobile/backend/lib/data/retention.dart`
- Modify: `recordings_repository.dart`, `processor.dart` (upkeep), `mobile/frontend/lib/ui/recording/recording_detail_screen.dart`, `mobile/frontend/lib/ui/record/recording_tile.dart`, `wording.dart`
- Test: `mobile/backend/test/data/retention_test.dart`, frontend `recording_detail_test.dart`, `record_screen_test.dart`

**Interfaces:**
- Produces:
  - `const kKeepAudioKey = 'keep_audio_days'; const kKeepAudioChoices = [0, 7, 30, 90, 365]; const kKeepAudioDefault = 30;`
  - `keepAudioProvider = AsyncNotifierProvider<KeepAudio, int>` with `set(int days)`.
  - `RecordingsRepository.audioOlderThan(DateTime cutoff)` → `List<Recording>` (done, audio present, `startedAt` before the cutoff).
  - `RecordingsRepository.deleteAudio(int id)`: deletes the FLAC and pieces, sets `audioDeleted`, clears `audioPath`.
  - `Future<int> applyRetention(RecordingsRepository repo, int days, DateTime now)` returns how many lost their audio. 0 days does nothing. The processor's `_upkeep` calls it with the setting.
  - **Screens:**
    - a text-only recording hides the player card and shows "The audio for this recording is no longer available.";
    - words and times don't play;
    - Process again (`Key('process-again')`) is disabled;
    - the tile badge is "Text only".
  - `recordingBadgeText` gives "Text only" for `audioDeleted` and done.

- [ ] **Step 1: Write the failing tests.**
  - `old finished recordings lose their audio, keep their text` (31 days, done, with FLAC → files gone, lines kept, `audioDeleted`);
  - `retention never touches unfinished recordings` (error, queued, processing, waiting, recording; all 40 days old);
  - `Forever keeps everything`;
  - `the setting is 30 days unless changed, and is kept`;
  - screen `a text-only recording can be read and shared, not played or processed again`;
  - tile `a text-only recording says so`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 5: Storage: what's on the phone, and the recordings

**Files:**
- Modify: `mobile/frontend/lib/ui/settings/storage_screen.dart`, `mobile/backend/lib/data/recordings_repository.dart`, `mobile/backend/lib/data/providers.dart`
- Test: frontend `storage_screen_test.dart`, backend `recordings_repository_test.dart`

**Interfaces:**
- Consumes: Task 4's `keepAudioProvider`, `audioOlderThan`.
- Produces:
  - `RecordingsRepository.audioSizes()` → `List<(Recording, int bytes)>`: recordings with audio, largest first.
  - `appDataBytesProvider` (the database file's size, via `AppDatabase`'s path; 0 in tests).
  - The page's sections, in order:
    1. "On this phone";
    2. "Recordings" (the total and count, the "Keep recordings for" dropdown with the hint, the list with Delete);
    3. "Downloaded models" (as now).
  - Changing the period to a shorter one asks first (Global Constraints wording), with N from `audioOlderThan`. Cancel keeps the old value.

- [ ] **Step 1: Write the failing tests:**
  - `on this phone adds up recordings, models, app data and free space`;
  - `recordings with audio are listed largest first`;
  - `Delete asks, then deletes after the Undo time; Undo keeps it`;
  - `a shorter period asks first and says how many`;
  - repository `audio sizes count the FLAC or the pieces`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 6: Copy and share a transcript

**Files:**
- Create: `mobile/backend/lib/data/transcript_text.dart`
- Modify: `mobile/frontend/pubspec.yaml` (share_plus), `recording_detail_screen.dart`
- Test: `mobile/backend/test/data/transcript_text_test.dart`, frontend `recording_detail_test.dart`

**Interfaces:**
- Produces:
  - `String transcriptText(Recording r, List<Phrase> lines)` (the Global Constraints format).
  - `shareTextProvider = Provider<Future<void> Function(String text)>` in the frontend (share_plus; tests replace it).
  - The header's Share button and menu; "Copy this line" in the line menu.

- [ ] **Step 1: Write the failing tests.**
  - Format:
    - `one speaker's lines join, a change starts a new line`;
    - `times past an hour have hours`;
    - `lines without speakers are each a line`;
    - `the length reads 32 min, 1 min, 1 h 05 min`.
  - Screen:
    - `Copy transcript puts it on the clipboard`;
    - `Share… hands the text to the share sheet`;
    - `Copy this line copies just that line`;
    - `no Share without lines`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.** `flutter pub add share_plus:<exact version>` in `mobile/frontend`.
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 7: First-start setup

**Files:**
- Create: `mobile/frontend/lib/ui/setup/setup_screen.dart`, `mobile/backend/lib/engine/setup_flag.dart`
- Modify: `mobile/frontend/lib/ui/app.dart`, `mobile/frontend/lib/ui/settings/speech_card.dart` (the language chips and the Hindi/Gujarati question as a reusable `LanguagesPicker` widget), `settings_screen.dart` (the name and other-names fields reusable as `NameFields`)
- Test: `mobile/frontend/test/ui/setup_test.dart`, `app_test.dart`

**Interfaces:**
- Produces:
  - `const kSetupDoneKey = 'setup_done';`
  - `setupDoneProvider = AsyncNotifierProvider<SetupDone, bool>` with `finish()`.
  - `VoiceDeskApp` shows `SetupScreen` until it is done, then the tabs. While the flag loads it shows an empty scaffold, never the tabs first.
  - `SetupScreen`: a `PageView` of the five steps (Global Constraints wording), driven by Back/Next. The Download step:
    - lists `neededModelIdsProvider` with `modelName` and sizes, plus the total;
    - starts `Models.downloadNeeded()`;
    - shows `neededModelsProvider`'s progress;
    - "Use the app while it downloads" calls `finish()`.

- [ ] **Step 1: Write the failing tests.**
  - `a new phone starts with the setup, an old flag goes straight to the tabs`;
  - `Next and Back move through the steps; Next is on while permissions are refused`;
  - `About you is saved when moving on`;
  - `Skip on Your voice goes to Download`;
  - `Download lists what is needed with the total, and starts it`;
  - `Use the app while it downloads finishes the setup`;
  - `with everything downloaded it says Voice Desk is ready`;
  - `on a phone in use the fields come filled and models show Downloaded`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 8: Licences & credits

**Files:**
- Create: `mobile/frontend/lib/ui/settings/credits_screen.dart`, `mobile/frontend/assets/licences/*.txt` (verbatim from the sources below), `mobile/frontend/lib/ui/licences.dart` (`registerModelLicences()`, called once in `main` before `runApp`)
- Modify: `settings_screen.dart` (About card), `mobile/frontend/pubspec.yaml` (assets)
- Test: `mobile/frontend/test/ui/credits_test.dart`

Licence texts, each copied verbatim from its official source:
- `cc-by-4.0.txt`: the CC BY 4.0 legal code.
- `indicconformer-mit.txt`: AI4Bharat's IndicConformer MIT licence, with its copyright line, from its GitHub repository.
- `parismita-apache-2.0.txt`: the Apache-2.0 text and the notice of the Hugging Face repository `parismitaglobalsolutions/indicconformer-sherpa-onnx`.
- `silero-vad-mit.txt`: the snakers4/silero-vad `LICENSE`.
- `3d-speaker-apache-2.0.txt`: the modelscope/3D-Speaker `LICENSE`.
- `sherpa-onnx-apache-2.0.txt`: the k2-fsa/sherpa-onnx `LICENSE`.
- `scowl.txt`: the SCOWL / en_US Hunspell copyright notice from wordlist.aspell.net.

- [ ] **Step 1: Write the failing tests:**
  - `About opens Licences & credits with every credit`: the seven rows, the Parakeet text exact;
  - `All licences shows the model licences too`: `LicenseRegistry.licenses` includes the packages `Parakeet`, `IndicConformer`, `Silero VAD`, `CAM++`, `English word list`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 9: On the Galaxy M31, and the docs

- [ ] **Step 1:** Install the release build when the app is idle.
- [ ] **Step 2:** Check:
  - the owner's recordings are compressed at start: sizes before and after, and every one still plays, seeks (drag the slider to the middle and to the end) and highlights words;
  - Process again on a compressed recording;
  - the setup shows once with the fields filled;
  - Share opens the share sheet;
  - Licences & credits opens.
- [ ] **Step 3: Docs.** Mobile spec Plans list (2c-b built); status file; ledger `2026-10-15-mobile-plan-2c-b-progress.md`.
