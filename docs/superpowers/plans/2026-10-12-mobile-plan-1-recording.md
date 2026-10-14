# Mobile app, Plan 1: foundation and recording — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working Android app that records meetings and voice notes (screen off, 1-minute crash-safe pieces), lists them below the Record button, plays them back, renames and deletes them.

**Architecture:** Flutter app in `mobile/`. `lib/ui/` only shows and takes input; `lib/engine/audio/` records into 16 kHz mono WAV pieces; `lib/data/` holds a drift (SQLite) database behind one `RecordingsRepository`. Riverpod wires them. A foreground service (flutter_foreground_task) keeps recording alive with the screen off.

**Tech Stack:** Flutter 3.47.7 / Dart 3.13; record 7.1.2, just_audio 0.10.6, drift 2.35.2 + drift_flutter 0.3.1 + drift_dev 2.35.1 + build_runner 2.16.2, flutter_riverpod 3.4.3, flutter_foreground_task 11.0.3, permission_handler 13.0.2, path_provider 2.1.6, path 1.9.1, intl 0.20.3.

**Moved since (2026-10-13):** the code below was built in `mobile/` and then split: `lib/main.dart`, `lib/ui/`, `test/ui/`, `android/` and `ios/` are in `mobile/frontend/` (package `mobile_frontend`); `lib/data/`, `lib/engine/`, `test/data/` and `test/engine/` are in `mobile/backend/` (package `mobile_backend`; the start-up work `main()` used to do is now `openBackend()` in its `lib/start.dart`). Imports are `package:mobile_backend/...` / `package:mobile_frontend/...` instead of `package:mobile/...`. Progress and rulings: [2026-10-12-mobile-plan-1-progress.md](2026-10-12-mobile-plan-1-progress.md).

**Spec:** [docs/superpowers/specs/2026-10-12-mobile-app-design.md](../specs/2026-10-12-mobile-app-design.md) — sections 1, 2 (Recording), 4 (Screens: Record, Recording detail; Data: `meetings`, `settings`), 5 (errors for recording).

**Later plans** (each ends with a working app): 2 Models + speech to text (first-start flow with name, languages and model download; queue, processing service, Parakeet + IndicConformer, transcripts, FLAC after processing; Settings: You, Languages, Processing, Models & storage) · 3 Speakers (voice training, remembered people) · 4 Task AI + Tasks tab · 5 Calls (detection, import, pausing recording during calls, notice when another app takes the mic; Settings: Calls). Plan 1 asks for permissions when Record is first tapped.

## Global Constraints

- **Do not commit.** The owner commits when they ask. "Checkpoint" steps mean: `flutter analyze` clean and `flutter test` all passing.
- Android first; `minSdk = 26` (Android 8); package `com.rajvee.mobile`.
- Audio: 16 kHz, mono, PCM 16-bit; 1-minute WAV pieces (`32000 × 60 = 1,920,000` data bytes each), named `piece-000.wav`, `piece-001.wav`, … in `<app documents>/recordings/<meeting id>/`.
- `lib/ui/` decides nothing: engine and data report **ids** (status values, message ids); the UI words them.
- Default title: `Recording · ` + `DateFormat('MMM dd, HH:mm')` of the start time (e.g. `Recording · Oct 12, 14:05`).
- Tabs: **Record · Tasks · Settings**; recordings list **below the Record button**.
- Status values stored as text: `recording`, `queued`, `processing`, `waiting_charge`, `done`, `error`. Plan 1 recordings end as `queued` (shown "Waiting to be processed"; Plan 2 processes them).
- Storage: don't start below **200 MB** free; stop and save when free space drops below **50 MB**.
- Recordings shorter than **1 s** are discarded.
- Run all commands from `mobile/`. Flutter is at `C:\src\flutter\bin` (on the user PATH; restart VS Code if a terminal can't find it).

## Review Focus

- App killed or phone restarted mid-recording → on next start the recording appears with the right length; nothing but the last unflushed audio is lost (Task 4 `recoverInterrupted` test, Task 2 `finalizeWav` test).
- Storage fills while recording → recording stops and is kept, with a message (Task 6 test `stops and saves when storage runs low`).
- Microphone permission refused → no crash; Record shows why and offers settings (Task 7 widget test).
- Stop right after Start (under 1 s) → no empty recording left in the list (Task 6 test `discards recordings under 1 s`).
- Rename to blank → default title, not an empty title (Task 4 test `rename blank uses default title`).

---

### Task 1: Project setup and app shell with three tabs

**Files:**
- Modify: `mobile/pubspec.yaml`, `mobile/android/app/build.gradle.kts` (`minSdk = 26`), `mobile/lib/main.dart`
- Create: `mobile/lib/ui/app.dart`, `mobile/lib/ui/tasks/tasks_screen.dart`, `mobile/lib/ui/settings/settings_screen.dart` (placeholder body), `mobile/lib/ui/record/record_screen.dart` (placeholder body)
- Delete: `mobile/test/widget_test.dart` (demo counter test)
- Test: `mobile/test/ui/app_test.dart`

**Interfaces:**
- Produces: `class VoiceDeskApp extends StatelessWidget` (MaterialApp, title `Voice Desk`, bottom `NavigationBar` with destinations `Record`, `Tasks`, `Settings`); `main()` wraps it in `ProviderScope`.

- [ ] **Step 1:** Add dependencies (versions in Tech Stack; `drift_dev` and `build_runner` under `dev_dependencies`): `flutter pub add record just_audio drift drift_flutter flutter_riverpod flutter_foreground_task permission_handler path_provider path intl` then `flutter pub add -d drift_dev build_runner`. Set `minSdk = 26`.
- [ ] **Step 2: Write the failing test** `test/ui/app_test.dart`:

```dart
testWidgets('shows Record, Tasks and Settings tabs, Record first', (t) async {
  await t.pumpWidget(const ProviderScope(child: VoiceDeskApp()));
  expect(find.text('Record'), findsWidgets);
  expect(find.text('Tasks'), findsOneWidget);
  expect(find.text('Settings'), findsOneWidget);
  await t.tap(find.text('Tasks'));
  await t.pumpAndSettle();
  expect(find.text('Tasks appear here after your recordings are processed.'), findsOneWidget);
});
```

- [ ] **Step 3:** Run `flutter test test/ui/app_test.dart` → FAIL (`VoiceDeskApp` not defined).
- [ ] **Step 4:** Implement `VoiceDeskApp` (Material 3, `IndexedStack` of the three screens) and the Tasks empty state with exactly that sentence; replace the demo `main.dart`.
- [ ] **Step 5:** Run the test → PASS. Run `flutter run` on the M31: three tabs show.
- [ ] **Step 6: Checkpoint.**

### Task 2: WAV helpers

**Files:**
- Create: `mobile/lib/engine/audio/wav.dart`
- Test: `mobile/test/engine/audio/wav_test.dart`

**Interfaces:**
- Produces: `const kSampleRate = 16000; const kBytesPerSecond = 32000; const kWavHeaderBytes = 44;` `Uint8List wavHeader(int dataBytes)` (PCM 16-bit mono 16 kHz RIFF header); `Future<void> finalizeWav(File f)` (rewrites the RIFF size at byte 4 and data size at byte 40 from the file's length; a file shorter than 44 bytes is rewritten as an empty WAV); `Duration wavDuration(File f)` (`(length − 44) / 32000` s, as microseconds).

- [ ] **Step 1: Write the failing tests:**

```dart
test('header describes 16 kHz mono 16-bit PCM', () {
  final h = ByteData.sublistView(wavHeader(32000));
  expect(String.fromCharCodes(wavHeader(0).sublist(0, 4)), 'RIFF');
  expect(h.getUint32(4, Endian.little), 36 + 32000);
  expect(h.getUint16(22, Endian.little), 1);      // channels
  expect(h.getUint32(24, Endian.little), 16000);  // sample rate
  expect(h.getUint16(34, Endian.little), 16);     // bits
  expect(h.getUint32(40, Endian.little), 32000);  // data bytes
});
test('finalizeWav repairs a piece cut off by a crash', () async {
  final f = File('${Directory.systemTemp.createTempSync().path}/p.wav');
  await f.writeAsBytes([...wavHeader(0), ...List.filled(64000, 1)]);  // header says 0 data bytes
  await finalizeWav(f);
  final h = ByteData.sublistView(await f.readAsBytes());
  expect(h.getUint32(40, Endian.little), 64000);
  expect(wavDuration(f), const Duration(seconds: 2));
});
test('finalizeWav turns a truncated header into an empty WAV', () async {
  final f = File('${Directory.systemTemp.createTempSync().path}/p.wav')..writeAsBytesSync([1, 2, 3]);
  await finalizeWav(f);
  expect(f.lengthSync(), 44);
  expect(wavDuration(f), Duration.zero);
});
```

- [ ] **Step 2:** Run `flutter test test/engine/audio/wav_test.dart` → FAIL.
- [ ] **Step 3:** Implement the three functions in `wav.dart`.
- [ ] **Step 4:** Run → PASS. **Step 5: Checkpoint.**

### Task 3: PieceWriter (1-minute pieces)

**Files:**
- Create: `mobile/lib/engine/audio/piece_writer.dart`
- Test: `mobile/test/engine/audio/piece_writer_test.dart`

**Interfaces:**
- Consumes: Task 2 (`wavHeader`, `finalizeWav`, `kBytesPerSecond`).
- Produces: `class PieceWriter { PieceWriter(Directory dir, {int pieceBytes = kBytesPerSecond * 60}); Future<void> add(Uint8List pcm); Future<List<File>> close(); int get dataBytes; }` — opens `piece-NNN.wav` with a `wavHeader(0)` placeholder, splits incoming PCM exactly at `pieceBytes`, finalizes each full piece when the next opens, and finalizes the last on `close()`. `dataBytes` = all PCM bytes written so far (the elapsed time is `dataBytes / kBytesPerSecond`).

- [ ] **Step 1: Write the failing tests** (use a small `pieceBytes`):

```dart
test('splits at pieceBytes and names pieces in order', () async {
  final dir = Directory.systemTemp.createTempSync();
  final w = PieceWriter(dir, pieceBytes: 1000);
  await w.add(Uint8List(700));
  await w.add(Uint8List(700));   // crosses into piece 2 mid-chunk
  await w.add(Uint8List(700));   // crosses into piece 3
  final pieces = await w.close();
  expect(pieces.map((f) => p.basename(f.path)), ['piece-000.wav', 'piece-001.wav', 'piece-002.wav']);
  expect(pieces.map((f) => f.lengthSync() - 44), [1000, 1000, 100]);
  expect(w.dataBytes, 2100);
});
test('every closed piece has a valid header', () async {
  final dir = Directory.systemTemp.createTempSync();
  final w = PieceWriter(dir, pieceBytes: 1000);
  await w.add(Uint8List(1500));
  for (final f in await w.close()) {
    expect(ByteData.sublistView(f.readAsBytesSync()).getUint32(40, Endian.little), f.lengthSync() - 44);
  }
});
test('a piece is on disk before close (crash-safe)', () async {
  final dir = Directory.systemTemp.createTempSync();
  final w = PieceWriter(dir, pieceBytes: 1000);
  await w.add(Uint8List(1200));
  expect(File('${dir.path}/piece-000.wav').lengthSync(), 1044);
});
```

- [ ] **Step 2:** Run `flutter test test/engine/audio/piece_writer_test.dart` → FAIL.
- [ ] **Step 3:** Implement `PieceWriter` (append with `RandomAccessFile`, flush after each `add`).
- [ ] **Step 4:** Run → PASS. **Step 5: Checkpoint.**

### Task 4: Database and RecordingsRepository

**Files:**
- Create: `mobile/lib/data/db.dart` (drift `AppDatabase`, tables `Meetings`, `Settings`; generated `db.g.dart`), `mobile/lib/data/recording.dart`, `mobile/lib/data/recordings_repository.dart`, `mobile/lib/data/settings_repository.dart`, `mobile/lib/data/providers.dart`
- Test: `mobile/test/data/recordings_repository_test.dart`

**Interfaces:**
- Consumes: Task 2 (`finalizeWav`, `wavDuration`).
- Produces:
  - Table `Meetings`: `id` int PK auto, `title` text, `kind` text (`recording` | `call`), `contact` text nullable, `startedAt` datetime, `durationMs` int nullable, `status` text, `step` text nullable, `error` text nullable, `summary` text nullable, `audioPath` text nullable. Table `Settings`: `key` text PK, `value` text.
  - `enum RecordingStatus { recording, queued, processing, waitingCharge, done, error }` with `String get id` (`waiting_charge` for `waitingCharge`) and `static RecordingStatus fromId(String)`.
  - `class Recording { final int id; final String title; final String kind; final DateTime startedAt; final Duration? duration; final RecordingStatus status; final String? error; }`
  - `String defaultTitle(DateTime startedAt)` → `Recording · Oct 12, 14:05`.
  - `abstract class RecordingsRepository { Stream<List<Recording>> watchAll(); Future<Recording?> get(int id); Future<Recording> create({String? title, required DateTime startedAt}); Future<Directory> audioDir(int id); Future<List<File>> pieces(int id); Future<void> finish(int id, Duration duration); Future<void> rename(int id, String title); Future<void> delete(int id); Future<int> recoverInterrupted(); }` and `class LocalRecordingsRepository implements RecordingsRepository { LocalRecordingsRepository(AppDatabase db, Directory recordingsRoot); }`
    - `watchAll`: newest `startedAt` first. `create`: status `recording`, blank/null title → `defaultTitle`, creates `<root>/<id>/`. `finish`: status `queued`, stores duration. `rename`: trimmed; blank → `defaultTitle(startedAt)`. `delete`: row and folder. `pieces`: `piece-*.wav` sorted by name. `recoverInterrupted`: for rows still `recording`, `finalizeWav` every piece, duration = sum of `wavDuration`; under 1 s → delete, else `finish`; returns how many were kept.
  - `class SettingsRepository { SettingsRepository(AppDatabase db); Future<bool> getBool(String key, {bool orElse = false}); Future<void> setBool(String key, bool value); }`
  - Riverpod (`providers.dart`): `databaseProvider`, `recordingsRootProvider` (`<documents>/recordings`), `recordingsRepositoryProvider`, `settingsRepositoryProvider`, `recordingsProvider` (`StreamProvider<List<Recording>>` from `watchAll`).

- [ ] **Step 1: Write the failing tests** (in-memory DB `AppDatabase(NativeDatabase.memory())`, temp root):

```dart
test('create uses the default title and status recording', () async {
  final r = await repo.create(startedAt: DateTime(2026, 10, 12, 14, 5));
  expect(r.title, 'Recording · Oct 12, 14:05');
  expect(r.status, RecordingStatus.recording);
  expect(Directory('${root.path}/${r.id}').existsSync(), isTrue);
});
test('watchAll lists newest first', () async { /* create two, expect later startedAt first */ });
test('finish sets queued and duration', () async { /* duration 90 s → Duration(seconds: 90), status queued */ });
test('rename blank uses default title', () async {
  final r = await repo.create(startedAt: DateTime(2026, 10, 12, 14, 5), title: 'Weekly');
  await repo.rename(r.id, '   ');
  expect((await repo.get(r.id))!.title, 'Recording · Oct 12, 14:05');
});
test('delete removes the row and its audio', () async { /* get → null, folder gone */ });
test('recoverInterrupted repairs pieces and keeps the recording', () async {
  final r = await repo.create(startedAt: DateTime.now());
  final dir = await repo.audioDir(r.id);
  File('${dir.path}/piece-000.wav').writeAsBytesSync([...wavHeader(0), ...List.filled(64000, 0)]);
  expect(await repo.recoverInterrupted(), 1);
  final got = (await repo.get(r.id))!;
  expect(got.status, RecordingStatus.queued);
  expect(got.duration, const Duration(seconds: 2));
});
test('recoverInterrupted drops recordings under 1 s', () async { /* 16000 bytes → returns 0, get → null */ });
```

- [ ] **Step 2:** Run `flutter test test/data/recordings_repository_test.dart` → FAIL.
- [ ] **Step 3:** Write the tables, run `dart run build_runner build --delete-conflicting-outputs`, implement the repositories and providers (`AppDatabase` default constructor uses `driftDatabase(name: 'voicedesk')`).
- [ ] **Step 4:** Run → PASS. **Step 5: Checkpoint.**

### Task 5: Free storage check (Android StatFs)

**Files:**
- Modify: `mobile/android/app/src/main/kotlin/com/rajvee/mobile/MainActivity.kt`
- Create: `mobile/lib/engine/audio/free_space.dart`
- Test: `mobile/test/engine/audio/free_space_test.dart`

**Interfaces:**
- Produces: `abstract class FreeSpace { Future<int> bytesFree(); }`; `class AndroidFreeSpace implements FreeSpace` (MethodChannel `voicedesk/storage`, method `freeBytes`, argument = the recordings root path, Kotlin returns `StatFs(path).availableBytes`); `const kMinFreeToStart = 200 * 1024 * 1024; const kMinFreeWhileRecording = 50 * 1024 * 1024;` `bool canStartRecording(int free)`, `bool mustStopRecording(int free)`.

- [ ] **Step 1: Write the failing tests:** `canStartRecording(kMinFreeToStart - 1)` false, `canStartRecording(kMinFreeToStart)` true; `mustStopRecording(kMinFreeWhileRecording - 1)` true, `mustStopRecording(kMinFreeWhileRecording)` false; `AndroidFreeSpace` with a mocked channel (`TestDefaultBinaryMessengerBinding … setMockMethodCallHandler`) returns the handler's value.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement Dart + the Kotlin handler. **Step 4:** Run → PASS. **Step 5: Checkpoint.**

### Task 6: RecorderController (start, pause, resume, stop, storage, foreground notification)

**Files:**
- Create: `mobile/lib/engine/audio/audio_source.dart` (`AudioSource` + `MicAudioSource` using `record`), `mobile/lib/engine/audio/recording_notification.dart` (`RecordingNotification` + `ForegroundRecordingNotification` using flutter_foreground_task), `mobile/lib/engine/audio/recorder_controller.dart`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Test: `mobile/test/engine/audio/recorder_controller_test.dart` (fakes for all three dependencies)

**Interfaces:**
- Consumes: Task 3 `PieceWriter`, Task 4 `RecordingsRepository`, Task 5 `FreeSpace`, `canStartRecording`, `mustStopRecording`.
- Produces:
  - `abstract class AudioSource { Future<bool> hasPermission(); Future<Stream<Uint8List>> start(); Future<void> pause(); Future<void> resume(); Future<void> stop(); Stream<double> get level; }` — `MicAudioSource` uses `AudioRecorder().startStream(RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1))`; `level` is 0..1 from `onAmplitudeChanged`.
  - `abstract class RecordingNotification { Future<void> show(String title); Future<void> update(Duration elapsed, {required bool paused}); Future<void> hide(); Stream<String> get buttons; }` — buttons emit `pause`, `resume`, `stop`. Foreground implementation: service type microphone, text `Recording · 12:34` / `Paused · 12:34`, buttons Pause/Resume and Stop.
  - `enum RecorderPhase { idle, recording, paused }`; `class RecorderState { final RecorderPhase phase; final int? recordingId; final Duration elapsed; final double level; final String? message; }` — `message` ids: `microphone_denied`, `storage_low`, `storage_full_stopped`, `too_short`.
  - `final recorderProvider = NotifierProvider<RecorderController, RecorderState>(…)` with `start({String? title})`, `pause()`, `resume()`, `stop()`; dependencies via `audioSourceProvider`, `recordingNotificationProvider`, `freeSpaceProvider`.
  - Behaviour: start → permission check (`microphone_denied`), free space check (`storage_low`), `repo.create`, notification `show`, pipe audio into `PieceWriter` in `repo.audioDir(id)`; `elapsed = dataBytes / 32000`; every 10 s of audio check `mustStopRecording` → stop with `storage_full_stopped`; notification buttons call pause/resume/stop; stop → `writer.close()`, under 1 s → `repo.delete` + `too_short`, else `repo.finish(id, elapsed)`; notification `hide`.
- Manifest: `RECORD_AUDIO`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS`, `WAKE_LOCK`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`; the flutter_foreground_task `<service>` with `android:foregroundServiceType="microphone"`.

- [ ] **Step 1: Write the failing tests** (fake source emits chunks you control; fake free space returns a mutable value):

```dart
test('records into pieces and finishes as queued', () async {
  await ctl.start(title: 'Weekly');
  source.emit(Uint8List(32000 * 3));                 // 3 s
  await ctl.stop();
  final r = (await repo.watchAll().first).single;
  expect(r.status, RecordingStatus.queued);
  expect(r.duration, const Duration(seconds: 3));
  expect(notification.calls, containsAllInOrder(['show:Weekly', 'hide']));
});
test('microphone refused → no recording, message', () async {
  source.permission = false;
  await ctl.start();
  expect(container.read(recorderProvider).message, 'microphone_denied');
  expect(await repo.watchAll().first, isEmpty);
});
test('storage low → does not start', () async { free.value = kMinFreeToStart - 1; /* message storage_low, no row */ });
test('stops and saves when storage runs low', () async {
  await ctl.start();
  source.emit(Uint8List(32000 * 5));
  free.value = kMinFreeWhileRecording - 1;
  source.emit(Uint8List(32000 * 6));                 // passes the 10 s check
  await pumpEventQueue();
  final st = container.read(recorderProvider);
  expect(st.phase, RecorderPhase.idle);
  expect(st.message, 'storage_full_stopped');
  expect((await repo.watchAll().first).single.status, RecordingStatus.queued);
});
test('discards recordings under 1 s', () async { /* emit 16000 bytes, stop → list empty, message too_short */ });
test('pause and resume from the notification', () async {
  await ctl.start();
  notification.press('pause');  await pumpEventQueue();
  expect(container.read(recorderProvider).phase, RecorderPhase.paused);
  expect(source.calls, contains('pause'));
  notification.press('resume'); await pumpEventQueue();
  expect(container.read(recorderProvider).phase, RecorderPhase.recording);
});
```

- [ ] **Step 2:** Run `flutter test test/engine/audio/recorder_controller_test.dart` → FAIL.
- [ ] **Step 3:** Implement the controller, `MicAudioSource`, `ForegroundRecordingNotification` (initialise flutter_foreground_task in `main()`; a top-level `@pragma('vm:entry-point')` task-handler callback forwards notification button presses to the main isolate) and the manifest entries.
- [ ] **Step 4:** Run → PASS. **Step 5: Checkpoint.**

### Task 7: Record screen with the recordings list

**Files:**
- Modify: `mobile/lib/ui/record/record_screen.dart`
- Create: `mobile/lib/ui/record/recording_tile.dart`, `mobile/lib/ui/wording.dart`
- Test: `mobile/test/ui/record_screen_test.dart` (override `recorderProvider` / repository with fakes)

**Interfaces:**
- Consumes: Task 4 `recordingsProvider`, `RecordingStatus`, `settingsRepositoryProvider`; Task 6 `recorderProvider`, `RecorderState`.
- Produces: `String statusText(RecordingStatus s)` (`recording` → `Recording…`, `queued` → `Waiting to be processed`, `processing` → `Processing…`, `waitingCharge` → `Waiting for charging`, `done` → `Done`, `error` → `Failed`) and `String recorderMessageText(String id)` (`microphone_denied` → `Voice Desk needs the microphone to record. Allow it in Settings.`, `storage_low` → `Not enough free storage to start recording.`, `storage_full_stopped` → `Storage is full, so the recording stopped. It was saved.`, `too_short` → `That recording was too short to keep.`) in `ui/wording.dart`.
- Screen: title field; big round record button (idle: Record; recording: Stop); Pause/Resume; timer `mm:ss` (or `h:mm:ss`); level bar; message as a banner with an **Open settings** button for `microphone_denied` (`openAppSettings()`); below, the recordings list (title, `dd MMM, HH:mm` · duration, status text); swipe to delete → SnackBar `Recording deleted` with **Undo** (5 s), delete only when the SnackBar closes without Undo; tap → Recording detail (Task 8). First time a recording starts, if battery optimisation isn't ignored, a dialog explains *"Samsung and other phones stop apps in the background. Allow Voice Desk to run unrestricted so long recordings aren't cut off."* with **Allow** (`Permission.ignoreBatteryOptimizations.request()`) and **Not now**; remembered with `SettingsRepository.setBool('battery_asked', true)`.

- [ ] **Step 1: Write the failing widget tests:** idle shows `Record` and the list with `Waiting to be processed`; tapping Record calls `start`; while recording shows `Stop` and `00:03` for `elapsed: 3 s`; `microphone_denied` shows its sentence and `Open settings`; swipe a tile → `Recording deleted` + `Undo`, tapping Undo keeps the tile and `delete` is never called; letting the SnackBar time out calls `delete` once.
- [ ] **Step 2:** Run `flutter test test/ui/record_screen_test.dart` → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS. **Step 5: Checkpoint.**

### Task 8: Recording detail (player, rename, delete)

**Files:**
- Create: `mobile/lib/ui/recording/recording_detail_screen.dart`, `mobile/lib/engine/audio/player.dart`
- Test: `mobile/test/ui/recording_detail_test.dart`

**Interfaces:**
- Consumes: Task 4 `RecordingsRepository` (`get`, `pieces`, `rename`, `delete`).
- Produces: `abstract class Player { Future<Duration> load(List<File> pieces); Future<void> play(); Future<void> pause(); Future<void> seek(Duration to); Stream<Duration> get position; Stream<bool> get playing; Future<void> dispose(); }`; `class JustAudioPlayer implements Player` (plays the pieces back to back with `setAudioSources([...AudioSource.file(...)])`); `playerProvider` (auto-dispose).
- Screen: editable title (saves on submit / focus loss via `rename`); play/pause, seek slider, `position / duration`; status line (`statusText`); a note `The transcript, speakers and tasks appear here once processing is available.`; delete (confirm dialog → `delete` → back).

- [ ] **Step 1: Write the failing widget tests:** title shows and renaming to `Weekly` calls `rename(id, 'Weekly')`; play button calls `play` after `load` with the repository's pieces; delete → confirm → `delete(id)` and the screen pops.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS. **Step 5: Checkpoint.**

### Task 9: Settings (permissions) and startup recovery

**Files:**
- Modify: `mobile/lib/ui/settings/settings_screen.dart`, `mobile/lib/main.dart`
- Test: `mobile/test/ui/settings_screen_test.dart`

**Interfaces:**
- Consumes: Task 4 `recoverInterrupted`; permission_handler.
- Produces: `abstract class PermissionsStatus { Future<Map<String, bool>> check(); Future<void> request(String id); }` with ids `microphone`, `notifications`, `battery_unrestricted`, and `permissionsProvider`. Settings shows a **Permissions** section: one row per id (`Microphone`, `Notifications`, `Run unrestricted in the background`) with **Allowed** or an **Allow** button; and an **About** row with the app version. `main()` calls `recoverInterrupted()` before showing the app.

- [ ] **Step 1: Write the failing widget test:** with fake statuses `{microphone: true, notifications: false, battery_unrestricted: false}` the screen shows one `Allowed` and two `Allow`; tapping the Notifications `Allow` calls `request('notifications')`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement (recovery runs before `runApp`). **Step 4:** Run → PASS. **Step 5: Checkpoint.**

### Task 10: On-device verification (Galaxy M31)

**Files:** none (verification only).

- [ ] **Step 1:** `flutter test` (all pass) and `flutter analyze` (no issues).
- [ ] **Step 2:** `flutter run` on the M31. Allow microphone and notifications; accept the battery dialog.
- [ ] **Step 3:** Record ~2 minutes with the **screen off**; check the notification shows `Recording · mm:ss` and its Pause/Stop work. Expected: the list shows the recording, ~2:00, `Waiting to be processed`; `adb shell run-as com.rajvee.mobile ls files/recordings/<id>` (or the app documents path) shows `piece-000.wav`, `piece-001.wav`, `piece-002.wav`.
- [ ] **Step 4:** Start a recording, wait 30 s, kill the app (`adb shell am force-stop com.rajvee.mobile`), reopen. Expected: the recording is listed with ~0:30.
- [ ] **Step 5:** Open a recording: playback plays across piece boundaries without gaps; rename works; blank rename gives the default title; delete + Undo, then delete without Undo.
- [ ] **Step 6:** Report results (screenshots via `adb exec-out screencap -p`). **Checkpoint.**
