# Mobile app, Plan 2a: English speech to text — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recordings turn into text on the phone: the speech model downloads once, every recording is cut at pauses and transcribed with Parakeet — during the recording, a minute at a time — and its lines show on the recording's screen.

**Architecture:** All logic in `mobile/backend` (package `mobile_backend`); `mobile/frontend` only shows it. sherpa-onnx (FFI) runs Silero voice activity + Parakeet in a background isolate behind a `SpeechToText` interface. A `Processor` (Riverpod notifier) takes one recording at a time from the database, feeds its WAV pieces from where it last stopped (`processedMs`), saves transcript lines as phrases end, and is woken by the recorder each time a 1-minute piece is finished. One foreground service (flutter_foreground_task) shows either the recording or the processing notification.

**Tech Stack:** Flutter 3.47.7 / Dart 3.13, Riverpod 3, drift 2.35 (schema 1 → 2), sherpa_onnx 1.13.8, archive 4.5.2 (tar.bz2), crypto (SHA-256), battery_plus 7.1.2, flutter_foreground_task 11.0.3 (types microphone + dataSync).

**Spec:** [docs/superpowers/specs/2026-10-12-mobile-app-design.md](../specs/2026-10-12-mobile-app-design.md) — §3 Processing (incl. "Processing while recording"), §4 Screens (Record's processing line; recording detail: player with transcript; Settings: Processing, Models & storage), §4 Data (`transcript_lines`), Model downloads, §5 Errors. Plan 1 (recording) is built; its ledger: [2026-10-12-mobile-plan-1-progress.md](2026-10-12-mobile-plan-1-progress.md).

**Not in this plan (later plans, per the spec's Plans list):** Hindi/Gujarati (2b), speakers (3), summary/tasks (4), calls (5), word-by-word highlighting while playing (lines are highlighted here), FLAC after processing (WAV pieces stay; a later storage plan), the full first-start flow (here: a download banner and a Settings card).

## Global Constraints

- Screens decide nothing: rules, ids and data live in `mobile/backend`; `mobile/frontend` shows and words them (`lib/ui/wording.dart`).
- Audio: 16 kHz mono 16-bit PCM in `piece-NNN.wav` files of 60 s (`kBytesPerSecond = 32000`, `kWavHeaderBytes = 44`); times everywhere are milliseconds from the recording's start.
- One job at a time; a job resumes after the last saved line (`meetings.processed_ms`), never repeating saved lines.
- Threads: **2** while recording (recording must never stutter), **4** after Stop, **2** when the phone is warm (thermal status MODERATE = 2).
- Wait (don't process) when: battery < **20%** (owner's value, 2026-10-13) and not charging; "Only process while charging" is on and not charging; thermal status ≥ SEVERE (3). Live processing follows the same rules; pieces skipped while waiting are done after Stop.
- Model downloads: resumable, SHA-256 checked, and when a host's address doesn't answer the next address is tried (this network can't reach one of GitHub's download addresses).
- Models (exact):
  - Silero VAD: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx` — 643,854 bytes — SHA-256 `9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6`.
  - Parakeet archive: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8.tar.bz2` — 104,337,827 bytes — SHA-256 `17f945007b52ccd8b7200ffc7c5652e9e8e961dfdf479cefcabd06cf5703630b`. Keep only `sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8/model.int8.onnx` (131,652,171 bytes, `9177a9146cf32ee0cc8152276ef95116f312018d316be37ccf57f7efea81fc1a`) and `…/tokens.txt` (9,953 bytes, `450e56bd2f036fe5b6aa821865838cc5aa9d8b0106134ce9a9ba0664abe6cd10`); delete the archive after.
  - Shown size: **105 MB** download; free storage needed to start: **300 MB**.
- VAD settings: threshold 0.5, min silence 0.5 s, min speech 0.25 s, max speech **20 s**, window 512 samples, buffer 60 s. Recognizer: NeMo CTC, greedy search, `debug: false`.
- The owner commits; each "Checkpoint" step is `flutter test` + `flutter analyze` in the touched package(s), not a git commit.
- Android: minSdk 26; the M31 runs Android 12. Run Flutter commands from `mobile/backend` (logic) or `mobile/frontend` (app).

## Review Focus

- The app is killed (or the phone restarts) mid-processing → on next start the job resumes from `processedMs`; no line is saved twice (Task 8 test `resumes after the last saved line without repeating it`).
- A recording is deleted while it is being processed → the job ends quietly, the next one starts, no lines are left behind (Task 8 test `a recording deleted mid-job is dropped`).
- The download breaks halfway or a file comes back corrupt → it resumes from the partial file; a wrong SHA-256 never counts as ready (Task 4 tests `resumes a partial download`, `a corrupt file is deleted and fails`).
- A recording with no speech → it ends `done` with no lines, and its screen says so (Task 8 test `silence only ends done with no lines`, Task 12 test `a recording with no speech says so`).
- The battery drops under 20% (not charging) during a job → the job pauses as `waiting_charge` and continues when charging starts (Task 8 test `low battery waits, charging resumes`).

---

### Task 1: Transcript lines in the database (schema 2)

**Files:**
- Modify: `mobile/backend/lib/data/db.dart` (+ regenerate `db.g.dart`), `mobile/backend/lib/data/recording.dart`, `mobile/backend/lib/data/recordings_repository.dart`, `mobile/backend/lib/data/providers.dart`
- Create: `mobile/backend/lib/data/transcript.dart`, `mobile/backend/lib/data/transcript_repository.dart`
- Test: `mobile/backend/test/data/transcript_repository_test.dart`, `mobile/backend/test/data/migration_test.dart`

**Interfaces:**
- Produces:
  - Table `TranscriptLines`: `id`, `meetingId` (int, references meetings, cascade delete), `startMs`, `endMs` (int), `text` (text), `wordsJson` (text: `[["word",startMs,endMs],…]`). Columns `Meetings.processedMs` and `Meetings.attempts` (int, default 0). `schemaVersion => 2` with `MigrationStrategy(onUpgrade: from 1 → createTable(transcriptLines) + addColumn(meetings, meetings.processedMs) + addColumn(meetings, meetings.attempts))`, and `beforeOpen` turning foreign keys on.
  - No `jobs` table (spec §4 lists one): a recording's status, `processedMs` and `attempts` are its place in the queue — the same behaviour with one table less.
  - `class Word {final String text; final int startMs, endMs;}` and `class Phrase {final int startMs, endMs; final String text; final List<Word> words;}` in `transcript.dart` (value equality — tests compare them).
  - `class TranscriptRepository { TranscriptRepository(AppDatabase db); Future<void> save(int meetingId, List<Phrase> phrases, {required int processedMs}); Stream<List<Phrase>> watch(int meetingId); Future<int> processedMs(int meetingId); }` — `save` inserts and moves `processedMs` forward in one transaction and throws `RecordingGone` when the meeting row no longer exists.
  - `Recording.processedMs` (int) and `double get progress` (processedMs / duration, 0 when no duration, at most 1).
  - `RecordingsRepository.setStatus(int id, RecordingStatus status, {String? error})`, `Future<int> startAttempt(int id)` (adds one to `attempts`, returns the new count), `Future<void> clearAttempts(int id)`, and `Future<Recording?> nextToProcess()` — oldest (by `startedAt`) with status `processing`, `queued` or `waiting_charge`.
  - `transcriptRepositoryProvider`, and `transcriptProvider = StreamProvider.family<List<Phrase>, int>`.

- [ ] **Step 1: Write the failing tests**
  - `save then watch returns the lines in time order with their words` (two phrases saved out of order come back sorted by `startMs`; words round-trip).
  - `save moves processedMs forward and never back` (save with 60000, then with 30000 → `processedMs` is 60000).
  - `save for a deleted recording throws RecordingGone and stores nothing`.
  - `deleting a recording deletes its lines`.
  - `nextToProcess takes the oldest waiting recording` (a `processing` one counts; `done`, `error` and `recording` don't).
  - `progress is processedMs over the duration` (30 s of 120 s → 0.25; no duration → 0).
  - `migration_test.dart`: `a version-1 database opens as version 2 with its recordings kept` — create the version-1 tables with raw SQL (copy the `CREATE TABLE` statements from the current `db.g.dart`) in a temp file, insert one meeting, set `PRAGMA user_version = 1`, open `AppDatabase(NativeDatabase(file))`, expect the meeting with `processedMs == 0` and an empty `transcript_lines`.
- [ ] **Step 2: Run them** — `cd mobile/backend && flutter test test/data` → FAIL (types missing).
- [ ] **Step 3: Implement** the table, column, migration, value classes, repository and providers; run `dart run build_runner build --delete-conflicting-outputs`.
- [ ] **Step 4: Run them** — PASS; the Plan 1 data tests still pass.
- [ ] **Step 5: Checkpoint** — `flutter test && flutter analyze` in `mobile/backend`.

### Task 2: Words from Parakeet's tokens

**Files:**
- Create: `mobile/backend/lib/engine/speech/words.dart`
- Test: `mobile/backend/test/engine/speech/words_test.dart`

**Interfaces:**
- Consumes: `Word`, `Phrase` (Task 1).
- Produces: `Phrase phraseFromTokens(List<String> tokens, List<double> timestamps, {required int startMs, required int endMs})` — `timestamps` are seconds from the segment's start, one per token. A token starting with `▁` or a space starts a new word (that mark is dropped); any other token (incl. punctuation) continues the word before. A word starts at its first token's time and ends where the next word starts; the last word ends at `endMs`. `text` = words joined by single spaces.

- [ ] **Step 1: Write the failing tests**
  - `joins pieces into words with times`: tokens `['▁hel','lo','▁world']`, timestamps `[0.0, 0.2, 0.48]`, startMs 1000, endMs 2000 → words `hello 1000–1480`, `world 1480–2000`; text `hello world`.
  - `punctuation stays on its word`: `['▁Yes', ',', '▁sure', '.']` → text `Yes, sure.` with two words.
  - `a space mark works like ▁`: `[' Hi', ' there']` → `Hi there`.
  - `no tokens gives an empty phrase over the segment`.
- [ ] **Step 2: Run** `flutter test test/engine/speech/words_test.dart` → FAIL.
- [ ] **Step 3: Implement** `phraseFromTokens`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Checkpoint.**

### Task 3: Reading the pieces as samples

**Files:**
- Create: `mobile/backend/lib/engine/audio/pcm_reader.dart`
- Test: `mobile/backend/test/engine/audio/pcm_reader_test.dart`

**Interfaces:**
- Consumes: `wavDuration`, `kWavHeaderBytes`, `kBytesPerSecond` (`wav.dart`).
- Produces: `Stream<Float32List> readSamples(List<File> pieces, {required int fromMs, int? toMs, int chunkMs = 10000})` — 16-bit samples as floats (`value / 32768`), starting at `fromMs` across the pieces in order, ending at `toMs` (or the end), in chunks of at most `chunkMs`. `int totalMs(List<File> pieces)`.

- [ ] **Step 1: Write the failing tests** (pieces written with `wavHeader` + known int16 ramps)
  - `reads from a point inside the second piece`: two 1-second pieces, `fromMs: 1500` → first sample equals the second piece's sample 8000 / 32768.
  - `stops at toMs`: `fromMs 0, toMs 1250` → 20,000 samples in all.
  - `chunks are at most chunkMs long`: 3 s of audio, `chunkMs 1000` → three chunks of 16,000.
  - `totalMs adds the pieces` (1 s + 0.5 s → 1500).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** with `RandomAccessFile` reads (never the whole recording in memory). **Step 4: Run** → PASS. **Step 5: Checkpoint.**

### Task 4: Resumable, checked downloads

**Files:**
- Modify: `mobile/backend/pubspec.yaml` (add `crypto`, `archive: ^4.5.2`)
- Create: `mobile/backend/lib/engine/models/downloader.dart`
- Test: `mobile/backend/test/engine/models/downloader_test.dart`

**Interfaces:**
- Produces: `class Downloader { Downloader({Future<List<InternetAddress>> Function(String host)? lookup, Duration connectTimeout = const Duration(seconds: 10)}); Future<void> fetch(Uri url, File dest, {required int size, required String sha256, void Function(int bytesDone)? onBytes}); }` — downloads into `dest.path + '.part'`, continuing a partial file with a `Range` request, follows redirects, renames to `dest` only when the size and SHA-256 match; on a mismatch deletes the part file and throws `DownloadFailed('corrupt')`. Connects to each address `lookup` returns in turn (a `HttpClient.connectionFactory` that connects to the chosen address — for `https` a `SecureSocket` — keeping the host name for TLS), moving on when one doesn't answer within `connectTimeout`. `class DownloadFailed implements Exception { final String reason; }` with reasons `corrupt`, `network`, `http_<code>`.

- [ ] **Step 1: Write the failing tests** (a local `HttpServer` on 127.0.0.1 serving 300 kB of known bytes, honouring `Range`)
  - `downloads and checks the file` (dest exists, matches, no `.part` left; `onBytes` reaches the size).
  - `resumes a partial download` (pre-write the first 100 kB to `.part` → the server sees `Range: bytes=102400-` and the result matches).
  - `a corrupt file is deleted and fails` (wrong sha256 → `DownloadFailed('corrupt')`, neither file left).
  - `tries the next address when one doesn't answer` (`lookup` returns a closed local port's address first, then the server's — download succeeds).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Step 5: Checkpoint.**

### Task 5: The speech model on the phone

**Files:**
- Create: `mobile/backend/lib/engine/models/speech_model.dart`
- Modify: `mobile/backend/lib/start.dart` (models folder provider override)
- Test: `mobile/backend/test/engine/models/speech_model_test.dart`

**Interfaces:**
- Consumes: `Downloader` (Task 4), `FreeSpace` / `freeSpaceProvider` (Plan 1).
- Produces:
  - `class SpeechModelFiles {final File vad, model, tokens;}`.
  - `class SpeechModelStore { SpeechModelStore(Directory root, Downloader d); SpeechModelFiles get files; bool get ready; Future<void> download({void Function(int done, int total)? onProgress}); Future<void> delete(); }` — `root/speech/` holds `silero_vad.onnx`, `parakeet/model.int8.onnx`, `parakeet/tokens.txt`. `ready` = all three exist with the exact sizes (Global Constraints). `download` fetches the VAD, then the archive, extracts the two members by streaming (archive 4: decode bzip2 to a temp `.tar`, then read only the wanted entries), checks each member's SHA-256, deletes the archive and temp tar; progress counts the two downloads (total 104,981,681 bytes).
  - `enum SpeechModelPhase { missing, downloading, ready, failed }`; `class SpeechModelState {phase; int done, total; String? message;}` (message ids `storage_low`, `network`, `corrupt`).
  - `speechModelProvider = NotifierProvider<SpeechModel, SpeechModelState>` with `Future<void> download()` (refuses with `storage_low` under 300 MB free) and `Future<void> delete()`; `modelsRootProvider` (overridden in `openBackend()` with `<app support>/models`).
- [ ] **Step 1: Write the failing tests** with a fake `Downloader` that writes given bytes (a tiny tar.bz2 built in the test with the `archive` package, holding the two member paths; sizes/hashes injected through a `SpeechModelStore.forTest(...)` constructor that takes the expected sizes and hashes):
  - `not ready until all three files are there`.
  - `download extracts the two files, checks them and removes the archive`.
  - `a member with the wrong hash fails and is not ready`.
  - `too little storage refuses to start with storage_low` (free 299 MB).
  - `delete removes the files and is missing again`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Step 5: Checkpoint.**

### Task 6: Speech to text with sherpa-onnx, in its own isolate

**Files:**
- Modify: `mobile/backend/pubspec.yaml` (add `sherpa_onnx: ^1.13.8`)
- Create: `mobile/backend/lib/engine/speech/speech_to_text.dart`, `mobile/backend/lib/engine/speech/sherpa_speech.dart`
- Test: `mobile/backend/test/engine/speech/sherpa_speech_test.dart` (real models; skipped unless set up)

**Interfaces:**
- Consumes: `SpeechModelFiles` (Task 5), `phraseFromTokens` (Task 2).
- Produces:
  - `abstract class SpeechToText { Future<Transcribed> push(Float32List samples); Future<Transcribed> finish(); Future<void> close(); }` and `class Transcribed {final List<Phrase> phrases; final int settledMs;}` — `push` takes audio that follows what was fed before and returns the phrases that ended in it; `settledMs` is the time up to which nothing more can come (the end of the fed audio when no speech is open, else the start of the open speech). `finish` closes the open speech.
  - `typedef SpeechToTextFactory = Future<SpeechToText> Function({required int startMs, required int threads});` and `speechToTextFactoryProvider` (default: `SherpaSpeech.start` with the store's files).
  - `SherpaSpeech.start(SpeechModelFiles files, {required int startMs, required int threads, String? libraryDir})` — spawns an isolate that calls `initBindings(libraryDir)`, creates the `VoiceActivityDetector` and `OfflineRecognizer` (values in Global Constraints), feeds the VAD in 512-sample windows (keeping the remainder), decodes each finished segment and maps it with `phraseFromTokens` (segment start = `startMs + start * 1000 ~/ 16000`); samples are sent as `TransferableTypedData`. Empty-text segments are dropped.
- [ ] **Step 1: Write the test** `transcribes the Parakeet test file` — skipped unless env `VOICEDESK_TEST_MODELS` (a folder with `silero_vad.onnx` and the Parakeet folder, e.g. the session's speed-test models) and `VOICEDESK_SHERPA_LIB` (the folder holding `sherpa-onnx-c-api.dll` from the `sherpa_onnx_windows` package in the pub cache) are set. Reads `test_wavs/0.wav` from the archive's folder, pushes it in 1-second chunks from `startMs: 5000`, then `finish()`; expects at least one phrase, all times ≥ 5000, non-empty text, words in time order.
- [ ] **Step 2: Run** with the env set → FAIL (missing). **Step 3: Implement.** **Step 4: Run** → PASS; without the env it is skipped. **Step 5: Checkpoint** (both packages build: `cd mobile/frontend && flutter build apk --debug`).

### Task 7: When processing may run

**Files:**
- Modify: `mobile/backend/pubspec.yaml` (add `battery_plus: ^7.1.2`), `mobile/frontend/android/app/src/main/kotlin/com/rajvee/mobile/VoiceDeskApplication.kt` (channel `voicedesk/device`, method `thermalStatus` → `PowerManager.currentThermalStatus` on API 29+, else 0)
- Create: `mobile/backend/lib/engine/pipeline/conditions.dart`
- Test: `mobile/backend/test/engine/pipeline/conditions_test.dart`

**Interfaces:**
- Produces:
  - `enum Gate { go, waitCharge, waitCool }` and `({Gate gate, int threads}) decide({required int battery, required bool charging, required bool onlyWhileCharging, required int thermal, required bool live})` — the rules and thread counts of Global Constraints.
  - `abstract class DeviceState { Future<int> battery(); Future<bool> charging(); Future<int> thermal(); Stream<void> get changes; }` with `PhoneDeviceState` (battery_plus + the channel) and `deviceStateProvider`; setting key `only_while_charging` (default false) via `SettingsRepository`.
- [ ] **Step 1: Write the failing tests** for `decide`: `after Stop: 4 threads`, `while recording: 2 threads`, `warm phone: 2 threads`, `hot phone waits`, `under 20% not charging waits for charge` (19%), `20% not charging goes`, `under 20% charging goes`, `only while charging, unplugged, waits for charge`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Step 5: Checkpoint.**

### Task 8: The processor (after Stop)

**Files:**
- Create: `mobile/backend/lib/engine/pipeline/processor.dart`
- Modify: `mobile/backend/lib/start.dart` (recordings left `processing` stay waiting; nothing else to do — the processor resumes them)
- Test: `mobile/backend/test/engine/pipeline/processor_test.dart`

**Interfaces:**
- Consumes: Tasks 1, 3, 5 (`speechModelProvider` readiness), 6 (`speechToTextFactoryProvider`), 7 (`deviceStateProvider`, `decide`).
- Produces:
  - `mobile/backend/lib/engine/pipeline/processing_notice.dart`: `abstract class ProcessingNotice { Future<void> show(String title, double progress, Duration? left); Future<void> hide(); }` and `processingNoticeProvider` (a no-op until Task 10 gives the real one).
  - `class ProcessingState {final int? recordingId; final String? title; final double progress; final Duration? left; final String? waiting;}` (`waiting`: `model`, `charge`, `cool`, or null).
  - `processorProvider = NotifierProvider<Processor, ProcessingState>`; `Processor.kick()` (start the loop if idle; safe to call any time), `Processor.retry(int id)` (error → queued, then kick). `build()` kicks once and re-kicks on `DeviceState.changes` and when the speech model becomes ready.
  - Loop: `nextToProcess()` → `decide(live: false)` → `startAttempt`: a third attempt means the app was cut off twice in this job → `error` with id `speech_crashed` (spec §5) → otherwise set `processing` → `SpeechToText` from `processedMs` with the decided threads → `readSamples(pieces, fromMs: processedMs)` → after each push, `TranscriptRepository.save(phrases, processedMs: settledMs)` and update `progress`/`left` (left = processing time so far ÷ audio done × audio left) → `finish()` → save with `processedMs = totalMs` → `done`. Errors → `error` with error id `speech_failed`; `RecordingGone` → drop the job. Gate `waitCharge` → status `waiting_charge`; `waitCool` → stays `queued`, `waiting: 'cool'`; model missing → `waiting: 'model'`.
- [ ] **Step 1: Write the failing tests** (in-memory db, real repositories, real WAV pieces in a temp folder, a `FakeSpeech` that returns a phrase per pushed chunk with known times, a fake `DeviceState`):
  - `processes a queued recording to done and saves its lines`.
  - `resumes after the last saved line without repeating it` (processedMs preset to 60000 → the first chunk the fake sees starts at 60000; line count = new lines only).
  - `one recording at a time, oldest first`.
  - `silence only ends done with no lines` (fake returns no phrases).
  - `a speech error marks it failed and retry finishes it`.
  - `a recording deleted mid-job is dropped` (delete inside the fake's second push → next job runs, no lines for it).
  - `low battery waits, charging resumes` (status `waiting_charge`, then `changes` with charging → `done`).
  - `no speech model: waits with waiting model`.
  - `progress and time left move as it goes`.
  - `a job that was cut off twice stops with speech_crashed` (`attempts` preset to 2 → status `error`, error `speech_crashed`; `retry` clears attempts).
  - `the processing notice shows while working and hides at the end` (fake `ProcessingNotice`).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Step 5: Checkpoint.**

### Task 9: Processing while recording

**Files:**
- Modify: `mobile/backend/lib/engine/audio/piece_writer.dart` (field `void Function(int finishedPieces)? onPieceFinished`, called after a piece is finalized when the next one opens), `mobile/backend/lib/engine/audio/recorder_controller.dart` (set it to call `processor.pieceFinished(id, n)`; after Stop call `processor.kick()`), `mobile/backend/lib/engine/pipeline/processor.dart`
- Test: `mobile/backend/test/engine/pipeline/live_processing_test.dart`, `mobile/backend/test/engine/audio/piece_writer_test.dart` (one new test)

**Interfaces:**
- Consumes: Task 8.
- Produces: `Processor.pieceFinished(int recordingId, int finishedPieces)` — if no after-Stop job is running, `decide(live: true)` says go and the model is ready: keeps one live `SpeechToText` for that recording (threads 2, from its `processedMs`), pushes the finished pieces' audio not yet fed, saves lines as they come. On Stop (`kick()` for that recording) the live instance is closed and the normal job continues from `processedMs` with 4 threads. Only one live recording at a time; a waiting gate skips (the audio is done after Stop).
- [ ] **Step 1: Write the failing tests**
  - `piece_writer: onPieceFinished reports each finished piece` (3 pieces of 0.5 s at `pieceBytes: 16000` → called with 1, then 2; not for the open last piece).
  - `lines appear during the recording, a minute at a time` (recording row status `recording`, two finished pieces → lines saved, `processedMs` ≥ 60000, status still `recording`).
  - `after Stop only the rest is done` (the fake sees from `processedMs`, nothing earlier, and the job ends `done`).
  - `while recording it uses 2 threads, after Stop 4` (the factory records `threads`).
  - `a waiting gate skips live work and the whole recording is done after Stop`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS (Plan 1 recorder tests still pass). **Step 5: Checkpoint.**

### Task 10: One foreground service for recording and processing

**Files:**
- Modify: `mobile/backend/lib/engine/audio/recording_notification.dart` (becomes the shared service), `mobile/frontend/android/app/src/main/AndroidManifest.xml` (`FOREGROUND_SERVICE_DATA_SYNC` permission; the plugin's service `android:foregroundServiceType="microphone|dataSync"`)
- Modify: `mobile/backend/lib/engine/pipeline/processing_notice.dart` (provider → the shared service)
- Test: `mobile/backend/test/engine/audio/recording_notification_test.dart` (new cases), `mobile/frontend/test/android/manifest_test.dart` (new case)

**Interfaces:**
- Consumes: `ProcessingNotice` (Task 8).
- Produces: the real `processingNoticeProvider`. One `ForegroundNotices` object implements `RecordingNotification` and `ProcessingNotice`: recording wins the notification while both run; with neither, the service stops; recording starts the service with types `[microphone, dataSync]` (restarting it if it runs as processing only); processing alone uses `[dataSync]`, text `Processing · 40% · about 3 min left` (or `Processing · 40%` with no estimate) under the recording's title.
- [ ] **Step 1: Write the failing tests** (mocked `flutter_foreground_task/methods` channel, as Plan 1's tests)
  - `processing alone starts the service as dataSync with its text`.
  - `recording during processing restarts the service with the microphone and shows the recording`.
  - `when recording stops the processing text comes back`.
  - `with nothing running the service stops`.
  - manifest: `the service may record and process` (`microphone|dataSync`, `FOREGROUND_SERVICE_DATA_SYNC`).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS (Plan 1's notification tests still pass). **Step 5: Checkpoint** (both packages).

### Task 11: Getting the speech model (screens)

**Files:**
- Create: `mobile/frontend/lib/ui/record/speech_model_banner.dart`
- Modify: `mobile/frontend/lib/ui/record/record_screen.dart` (banner above the recordings), `mobile/frontend/lib/ui/settings/settings_screen.dart` (cards "Speech model" and "Processing"), `mobile/frontend/lib/ui/wording.dart`
- Test: `mobile/frontend/test/ui/speech_model_test.dart`, `mobile/frontend/test/ui/settings_screen_test.dart` (new case)

**Interfaces:**
- Consumes: `speechModelProvider` (Task 5); setting `only_while_charging` (Task 7).
- Words (exact): banner `Turn recordings into text: download the speech model (105 MB, Wi-Fi recommended).` + button `Download`; while downloading `Downloading the speech model · 40 of 105 MB`; failed: `storage_low` → `Not enough free storage for the speech model (300 MB needed).`, `network` → `The download stopped. Check the connection and try again.`, `corrupt` → `The download was damaged. Try again.` + `Try again`. Settings: card "Speech model" (`English speech model · 105 MB` with `Download` or `Delete`), card "Processing" with switch `Only process while charging`.
- [ ] **Step 1: Write the failing tests**: `missing shows the banner and Download starts it`, `downloading shows progress in MB`, `ready hides the banner`, `a failure says why and offers Try again`, `settings: the switch saves only_while_charging`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Step 5: Checkpoint.**

### Task 12: Showing processing and the transcript (screens)

**Files:**
- Modify: `mobile/frontend/lib/ui/record/record_screen.dart` (processing line under the hero card), `mobile/frontend/lib/ui/record/recording_tile.dart` (badge `Processing 40%`), `mobile/frontend/lib/ui/recording/recording_detail_screen.dart` (transcript), `mobile/frontend/lib/ui/wording.dart`
- Test: `mobile/frontend/test/ui/processing_test.dart`, `mobile/frontend/test/ui/recording_detail_test.dart` (new cases)

**Interfaces:**
- Consumes: `processorProvider` (`ProcessingState`), `transcriptProvider`, `Recording.progress`, `Processor.retry`.
- Words (exact): line `Turning “Weekly review” into text · 40% · about 3 min left`; waiting: `charge` → `Waiting for charging to turn recordings into text`, `cool` → `Waiting for the phone to cool down`, `model` → nothing (the banner says it). Detail: lines as `00:12  text` (tap → player seeks to the line's start); the line being played is shown in the accent colour; `done` with no lines → `No speech found in this recording.`; `error` → `Couldn't turn this into text.` (`speech_crashed` → `Turning this into text stopped the app twice. Close other apps and allow Unrestricted battery, then try again.`) + `Try again` (calls `retry`); while recording or processing, lines appear as they are saved.
- [ ] **Step 1: Write the failing tests**: `the processing line names the recording, percent and time left`, `waiting for charge is said`, `the tile shows Processing 40%`, `lines show with their times and a tap seeks there`, `the playing line is highlighted`, `a recording with no speech says so`, `a failed one offers Try again`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Step 5: Checkpoint.**

### Task 13: On-device verification (Galaxy M31)

**Files:** none (verification only).

- [ ] **Step 1:** Both packages: `flutter test`, `flutter analyze`; build and install (`pm install` must print `Success` before testing).
- [ ] **Step 2:** Settings → Speech model → Download (Wi-Fi). Expected: progress to 105 MB, then ready; `adb shell run-as com.rajvee.mobile ls -lR files/models/speech` shows the three files with the exact sizes and no archive left.
- [ ] **Step 3:** Record ~3 minutes of English speech (play an English recording on the PC's speakers next to the phone, or the owner speaks), screen off. Expected: on the recording's screen, lines appear during the recording about a minute behind; after Stop it is `done` within about a minute; the transcript is readable.
- [ ] **Step 4:** Kill the app mid-processing (`am force-stop`), reopen. Expected: it resumes, no repeated lines.
- [ ] **Step 5:** Tap a line → playback from there; the playing line is highlighted.
- [ ] **Step 6:** Report in the status file: the measured speed (audio minutes per processing minute, live and after Stop) and peak memory while processing (`adb shell dumpsys meminfo com.rajvee.mobile`, TOTAL PSS, sampled every 10 s). **Checkpoint.**
