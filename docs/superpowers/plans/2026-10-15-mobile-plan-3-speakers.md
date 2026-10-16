# Mobile app, Plan 3: Speakers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every transcript line says who said it. The owner's lines show "Me" after a short voice reading. Other people start as "Person 1, 2…". The owner can rename people, and the phone recognises them in later recordings. A single line can be moved to the right person, and Settings lists the remembered people.

**Architecture:**
- **One small voice model (CAM++), measured on the PC 2026-10-15:**

  | | Same voice | Other voice |
  |---|---|---|
  | Two-voice conversation | similarity ≥ 0.33 | ≤ 0.31 |
  | The owner's voice | ≥ 0.33 across his recordings | ≤ 0.15 against the PC voices |

  The two-voice conversation's speech time was 100% right at a clustering distance of 0.6–0.7. Speed: about 1.5% of the speech's length on the PC.
- **During speech-to-text (live or after Stop),** the engine isolate computes a voice print for every phrase. Phrases over 3 s get one per 1.5 s window, at a 0.75 s step. The prints are saved with each line.
- **When the job's speech is done,** a pure-Dart grouping step:
  - clusters the phrases (average linkage on cosine distance);
  - assigns the windows of long phrases to the nearest group, and splits those lines where the speaker changes;
  - applies the desktop's clean-up rules;
  - names the groups: "Me" from the trained voice, remembered people, otherwise "Person N".
- Renaming, remembering and moving lines are repository operations over the saved groups.

**Tech Stack:** As Plan 2c-a. sherpa_onnx `SpeakerEmbeddingExtractor`. drift schema 4 → 5. No new packages.

**Spec:** [docs/superpowers/specs/2026-10-14-mobile-next-features-design.md](../specs/2026-10-14-mobile-next-features-design.md), Part C (C1–C5). The approach is (a), "one voice print per phrase … long phrases cut into ~1.5 s windows", which C1 left to the builder. The mobile spec's step 3 applies too. Owner, 2026-10-15: "Speakers: who said what, 'Me' from a short voice reading, renaming and remembering people, moving a line to the right person, a People list."

**Not in this plan:** summary and tasks (Plan 4), copy/share (2c-b), speakers on the desktop.

## Global Constraints

- **The owner commits.** "Checkpoint" = `flutter test` + `flutter analyze` in the touched packages. The phone is reached over Wi-Fi (adb wireless debugging).
- **Model (exact):** `https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx` (the release tag is spelled "recongition"), 28,281,164 B, SHA-256 `aa3cfc16963a10586a9393f5035d6d6b57e98d358b347f80c2a30bf4f00ceba2`.
  - Saved as `speech/speakers/campplus.onnx`.
  - `ModelId.speakers`, named "Speaker detection".
  - It produces 192-number voice prints, L2-normalised.
- **Voice-print pieces:** a phrase ≤ 3000 ms is one piece. A longer phrase is cut into windows of 1500 ms every 750 ms, plus a last window ending at the phrase end when more than 300 ms would be left out. Phrases under 400 ms get no print.
- **Grouping:**
  - average linkage;
  - merge while the mean cosine **similarity ≥ 0.35** (distance ≤ 0.65);
  - a group's print is the duration-weighted mean of its pieces, normalised.
- **Clean-up (desktop `meeting.py` / `speakers.py`):**
  - groups with under 1500 ms of speech merge into the nearest group;
  - a speaker turn under 250 ms joins its neighbour;
  - inside a long phrase, a single window between two windows of one group belongs to that group.
- **Names:**
  - "Me": the group with the highest similarity to the trained voice, when **≥ 0.30**; at most one.
  - Remembered people: only groups with ≥ 3000 ms of speech are compared; a match needs similarity **≥ 0.35**; best pairs first; each person names at most one group.
  - The rest: "Person 1", "Person 2"… in order of first appearance.
- **Voice training:**
  - recording stops by itself at 25 s; Done is enabled from 8 s;
  - needs ≥ 6 s of speech by VAD;
  - the print is the mean of 3000 ms windows every 1500 ms, normalised.
- **Remembering:** needs ≥ 2000 ms of the person's speech and uses up to 30 s. A name already remembered (ignoring case) merges: the prints are averaged by their speech time.
- **Wording (spec C, exact):**
  - "Person 1"
  - "Your voice" / "Not trained yet" / "Voice saved <d MMM yyyy>" / "Train my voice" / "Re-train" / "Forget my voice"
  - "Read this aloud in your normal voice:" / "Keep reading…" / "Done"
  - the passage: "The quick brown fox jumps over the lazy dog. I'm teaching Voice Desk what my voice sounds like, so it can tell my lines from everyone else's. Tomorrow I will send the report, review the design, and call the team at three."
  - "Only Ns of speech was heard. Please read the text aloud for about 15 seconds."
  - "Forget your voice?" / "Voice Desk deletes what it learned about your voice. Until you train it again, your lines show as Person 1, 2…" / "Forget"
  - "Rename <X> to" / "Their name" / "Recognise this voice in future recordings" / "Saved on this phone only" / "Rename" / "Cancel"
  - "Your own lines can't be renamed" / "Type a name"
  - "Renamed — <name>'s voice will be recognised in future recordings" / "Renamed to <name>"
  - "Not enough of their speech to remember the voice (needs 2 s or more)"
  - "Said by…" / "Someone else…"
  - "People" / "Forget <name>'s voice? Their name stays on past recordings."
  - "Speaker detection" (Settings → Speech switch, default on)
- **Speakers belong to a recording's setup:** `SpeechSetup.speakers` (bool). New recordings take the setting. Recordings made before Plan 3 have none. Process again takes the setting as it is now.

## Review Focus

- **A recording with one speaker only** (the owner alone). Expected: one group, "Me" if trained, else "Person 1"; no splitting. Task 4 test `one voice is one group`.
- **Quick back-and-forth inside one phrase** (a gap under the VAD's 0.5 s). Expected: the line is split at the change. Task 4 test `a phrase with two voices is split where the speaker changes`.
- **Speaker detection off, or its model missing.** Expected: off, no prints and no names; on with the model missing, the recording waits for it like any model. Task 3 test.
- **Process again of a recording whose lines were renamed or moved.** Expected: the new run names groups afresh (remembered voices come back), and the old names don't leak into the drafts. Task 5 test.
- **Forgetting your voice, or a person, after recordings used them.** Expected: past recordings keep their names; new recordings no longer match. Task 7 test.

---

### Task 1: The speaker model and the setting

**Files:**
- Modify: `mobile/backend/lib/engine/models/catalogue.dart`, `mobile/backend/lib/engine/speech/speech_setup.dart`, `mobile/backend/lib/data/db.dart` (+g), `recording.dart`, `recordings_repository.dart`, `mobile/frontend/lib/ui/wording.dart`, `mobile/frontend/lib/ui/settings/speech_card.dart`, `mobile/frontend/lib/ui/settings/storage_screen.dart`
- Test: `speech_setup_test.dart`, `migration_test.dart`, `recordings_repository_test.dart`, frontend `speech_card_test.dart`, `storage_screen_test.dart`

**Interfaces:**
- Produces:
  - `ModelId.speakers` (added last in the enum);
  - `SpeechSetup.speakers` (bool, default false; `models` adds `ModelId.speakers` when on; `key` unchanged);
  - `SpeechSettings.speakers` (settings key `speaker_detection`, default true), with `SpeechSettingsNotifier.setSpeakers(bool)`;
  - schema 5: `Meetings.speakers` (bool, default false), and the voice-print and speaker columns of Task 2;
  - Storage lists "Speaker detection";
  - the Speech card has a `SwitchListTile` "Speaker detection" with the subtitle "Who said what, after each recording".

- [ ] **Step 1: Write the failing tests.**
  - `speaker detection is on by default and kept`.
  - `a setup with speakers needs the speaker model`.
  - `a recording keeps whether it was made with speakers`.
  - Migration: `a version-4 database opens as version 5, old recordings without speakers`.
  - Frontend: `the speaker detection switch saves it`; Storage `lists the speaker model`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 2: Voice prints from the engine, saved with the lines

**Files:**
- Create: `mobile/backend/lib/engine/speakers/voice_print.dart`
- Modify: `mobile/backend/lib/data/transcript.dart`, `transcript_repository.dart`, `db.dart`, `mobile/backend/lib/engine/speech/sherpa_speech.dart`, `speech_to_text.dart`, `mobile/backend/lib/engine/speech/your_words.dart` (polish keeps prints)
- Test: `mobile/backend/test/engine/speakers/voice_print_test.dart`, `transcript_repository_test.dart`, `sherpa_speech_test.dart` (real model)

**Interfaces:**
- Produces:
  - `class VoicePiece { int startMs, endMs; Float32List print; }`;
  - `Phrase.voices` (`List<VoicePiece>`, default empty; not part of equality);
  - `List<(int, int)> printPieces(int startSample, int endSample)` (Global Constraints values);
  - `double similarity(Float32List a, Float32List b)`;
  - `Float32List meanPrint(List<(Float32List, int weight)>)`;
  - `String encodePrint(Float32List)` / `Float32List decodePrint(String)` (base64 of little-endian float32).
  - Schema 5 columns on `TranscriptLines`: `voicesJson` (text, default `'[]'`), `speaker` (text, nullable) and `speakerGroup` (int, nullable).
  - The engine (when `setup.speakers` and the model file is given): `SpeechFiles.speakers` (`File?`). It computes the pieces' prints for every phrase it writes, from the phrase's own samples, and returns them on `Phrase.voices`.
  - `TranscriptPolish.apply` keeps `voices` on the lines it changes.

- [ ] **Step 1: Write the failing tests.**
  - `a short phrase is one piece, a long one 1.5 s windows`: 2000 ms → [(0, 2000)]; 4000 ms → (0,1500), (750,2250), (1500,3000), (2250,3750), (2500,4000); a 300 ms phrase → none.
  - `prints round-trip through text`.
  - `similarity and the weighted mean`.
  - Repository: `voice pieces are saved with their line`.
  - Real model: `a phrase's voice prints come back from the engine` (rec2: every phrase over 400 ms has prints of 192 numbers).
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 3: Grouping and naming (pure Dart)

**Files:**
- Create: `mobile/backend/lib/engine/speakers/grouping.dart`
- Test: `mobile/backend/test/engine/speakers/grouping_test.dart`

**Interfaces:**
- Produces:
  - `class SpeakerResult { List<Phrase> lines; List<SpeakerGroup> groups; }` (`lines` split where needed, each with `speaker` and `speakerGroup`);
  - `class SpeakerGroup { int id; String label; Float32List print; int speechMs; }`;
  - `class KnownVoice { String name; Float32List print; }`;
  - `SpeakerResult groupSpeakers(List<Phrase> lines, {Float32List? me, List<KnownVoice> people = const []})`;
  - `Phrase.speaker` (`String?`) and `Phrase.speakerGroup` (`int?`), both part of equality.

- [ ] **Step 1: Write the failing tests** (prints made by hand: unit vectors near two or three directions):
  - `two voices make two groups, named Person 1 and 2 in order of first appearance`;
  - `one voice is one group`;
  - `a phrase with two voices is split where the speaker changes` (window prints A, A, B, B; the words go to the side their middle falls in);
  - `a single stray window stays with its neighbours`;
  - `a group with under 1.5 s of speech joins the nearest`;
  - `the trained voice is Me` (≥ 0.30) and `a voice below the line is not Me`;
  - `a remembered person names their group; each person names one group; best pairs first`;
  - `groups with under 3 s of speech are not matched to remembered people`;
  - `lines without prints keep no speaker` (speakers off).
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement** average linkage with the nearest-neighbour chain (O(n²)) on the line-level prints (the mean of each line's pieces), then the window assignment, the clean-up and the names.
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 4: The speakers step in processing

**Files:**
- Create: `mobile/backend/lib/data/speakers_repository.dart`
- Modify: `db.dart` (schema 5: `MeetingSpeakers`, `People`), `providers.dart`, `transcript_repository.dart`, `mobile/backend/lib/engine/pipeline/processor.dart`, `mobile/backend/lib/engine/speech/speech_to_text.dart`
- Test: `processor_test.dart`, `mobile/backend/test/data/speakers_repository_test.dart`, `sherpa_speech_test.dart` (real model)

**Interfaces:**
- Produces:
  - Tables:
    - `MeetingSpeakers(id, meetingId → cascade, groupId, label, printB64, speechMs, draft)`;
    - `People(id, name unique-ignoring-case via a lowercase `key` column, printB64, speechMs, updatedAt)`.
  - The voice print: settings keys `voice_print` and `voice_saved_at`.
  - `SpeakersRepository`:
    - `Future<Float32List?> myVoice()`
    - `Future<List<KnownVoice>> people()`
    - `Future<void> saveGroups(int meetingId, SpeakerResult r, {required bool draft})` (replaces the lines' speaker fields and the meeting's groups)
  - `TranscriptRepository.linesForGrouping(int meetingId, {required bool draft})` (with prints).
  - **The processor:** after a job's last `save`, when `r.setup.speakers`, it calls `groupSpeakers` on the job's lines (drafts on a re-run) and saves, before `commitDraft` and `done`. The step shows as `ProcessingState(step: 'speakers')`. A failure in this step keeps the text: the recording goes `done`, with an error noted `speakers_failed`.

- [ ] **Step 1: Write the failing tests.**
  - Processor:
    - `after the text, lines get their speakers` (fake engine with prints of two voices → Person 1 / Person 2 saved);
    - `with speakers off nothing is named`;
    - `a re-run names groups afresh`;
    - `the trained voice and remembered people name groups`;
    - `a speakers step that fails keeps the text`.
  - Repository: `groups are saved and replace the old ones`.
  - Real model: `two voices in a conversation make two people` (the David/Zira conversation, built by the test from `spk/line*.wav` in VOICEDESK_TEST_AUDIO): ≥ 95% of the speech time is right.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 5: "Me": training your voice

**Files:**
- Create: `mobile/backend/lib/engine/speakers/voice_training.dart`, `mobile/frontend/lib/ui/settings/voice_training_screen.dart`
- Modify: `mobile/frontend/lib/ui/settings/settings_screen.dart` (a "Your voice" row in You and your words)
- Test: `mobile/backend/test/engine/speakers/voice_training_test.dart`, `mobile/frontend/test/ui/voice_training_test.dart`

**Interfaces:**
- Produces:
  - `class VoiceTraining extends Notifier<TrainingState>`: `start()`, `done()`, `cancel()`, `forget()`. State: phase (idle / recording / working / saved / failed), elapsed, level, message. It records with the existing `AudioSource`, stops itself at 25 s, and computes the print in an isolate through `VoicePrinter`.
  - `typedef VoicePrinter = Future<(Float32List?, int speechMs)> Function(Float32List samples)` (VAD + windows); the provider builds it from the models.
  - `voiceTrainingProvider`.
  - `myVoiceProvider` (`FutureProvider<(Float32List?, DateTime?)>`).

- [ ] **Step 1: Write the failing tests** (fake source and printer):
  - `Done is off until 8 s, and recording stops itself at 25 s`;
  - `too little speech says so`;
  - `a voice is saved and shown with its date`;
  - `Forget asks, then deletes`;
  - Real model: `your voice trained from one recording is Me in another` (train on rec2's speech, group rec16 → "Me").
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 6: Names on the transcript, rename and remember

**Files:**
- Modify: `mobile/frontend/lib/ui/recording/recording_detail_screen.dart`, `mobile/backend/lib/data/speakers_repository.dart`
- Test: `recording_detail_test.dart`, `speakers_repository_test.dart`

**Interfaces:**
- Produces:
  - **The screen:** each line whose speaker differs from the line before shows the label (bold, accent) above it. Tapping a label other than "Me" opens the rename sheet.
  - `SpeakersRepository.rename(int meetingId, int groupId, String name, {required bool remember})`:
    - renames the group's lines and its `MeetingSpeakers` row;
    - with `remember`: under 2 s of speech → `NotEnoughSpeech`; otherwise upserts `People` (a name already there merges, the prints averaged by speech time).
  - Errors: `CantRenameMe`; an empty name or "Me" → `ArgumentError`.

- [ ] **Step 1: Write the failing tests.**
  - Screen:
    - `a speaker's name shows where the speaker changes`;
    - `tap a name, rename, remembered`;
    - `Me can't be renamed`;
    - `an empty name is refused`.
  - Repository:
    - `rename changes every line of the group`;
    - `remembering a name already known merges the voices`;
    - `under 2 s of speech can't be remembered`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 7: Said by… and the People list

**Files:**
- Create: `mobile/frontend/lib/ui/settings/people_screen.dart`
- Modify: `recording_detail_screen.dart` (line menu), `settings_screen.dart`, `speakers_repository.dart`
- Test: `recording_detail_test.dart`, `mobile/frontend/test/ui/people_screen_test.dart`, `speakers_repository_test.dart`

**Interfaces:**
- Produces:
  - `SpeakersRepository.moveLine(int lineId, {int? groupId, required String label})`: only that line; no voice print changes.
  - `renamePerson(int id, String name)`; `forgetPerson(int id)`; `forgetMyVoice()`.
  - The line menu gets "Said by…", which lists Me (if trained), this recording's speakers, the remembered people, and "Someone else…".
  - **Settings → People:** your voice at the top (opens training); then the remembered names with Rename and Forget.

- [ ] **Step 1: Write the failing tests.**
  - `Said by moves only that line`.
  - `Someone else asks for a name`.
  - `People lists the remembered names; Forget asks, then forgets; past recordings keep their names`.
  - `forgetting your voice keeps past Me lines`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 8: On the Galaxy M31, and the docs

- [ ] **Step 1:** Install the release build when the app is idle.
- [ ] **Step 2: Process again on two-voice audio.** Make a recording by playing the David/Zira conversation from the PC speakers, then Process again it. Check:
  - two people;
  - Rename + remember;
  - a second recording names them by themselves;
  - the speakers step's time, and memory.
  - Training "Me" needs the owner's voice: ask him to do it and check, or check it with rec2 on the PC (Task 5).
- [ ] **Step 3: Docs.** Mobile spec Plans list (3 built); status file; ledger `2026-10-15-mobile-plan-3-progress.md`.
