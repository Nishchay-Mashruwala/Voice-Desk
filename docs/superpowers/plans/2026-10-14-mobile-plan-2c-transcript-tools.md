# Mobile app, Plan 2c-a: Transcript tools and downloads — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The owner can:
- fix the words of a transcript line;
- tell the app the other names people call them;
- process a recording again with another accuracy or other languages;
- see every downloaded model, download or delete each one, with a green "Downloaded" tag.

**Architecture:**
- Logic stays in `mobile/backend`.
- Transcript lines get their database id, so a screen can edit one.
- An edited line's words are re-timed by a port of the desktop's `retime_words`.
- "Process again" runs the normal job on the recording. Its lines are saved as **draft** lines, hidden from the screens. When the job completes they replace the old lines in one transaction, so the old text stays until the new one is complete.
- The Storage page is a frontend screen over the existing `modelsProvider`.

**Tech Stack:** As Plan 2b. drift schema 3 → 4. No new packages.

**Spec:** [docs/superpowers/specs/2026-10-14-mobile-next-features-design.md](../specs/2026-10-14-mobile-next-features-design.md):
- B1 "Fix the words in a line";
- B3 "Other names people call you";
- B6, the "Downloaded models" part with the owner's 2026-10-14 additions;
- B9 "Process again";
- "The order of work" (owner, 2026-10-14).

Plan 2b's ledger: [2026-10-14-mobile-plan-2b-progress.md](2026-10-14-mobile-plan-2b-progress.md).

**Not in this plan:**
- speakers (Part C);
- copy/share, FLAC, keep N days, the recordings part of Storage, first-start setup, Licences & credits;
- the "Copy this line" and "Said by…" menu items (they come with B2 and Part C).

## Global Constraints

- Screens decide nothing; wording lives in `mobile/frontend/lib/ui/wording.dart` or the screen, as now.
- **The owner commits.** "Checkpoint" = `flutter test` + `flutter analyze` in the touched package(s).
- The owner's recordings stay outside the repository.
- **Wording (exact):**
  - "Other names people call you" / "Nicknames or spellings, comma separated."
  - "Fix the words" · "Save" · "Cancel" · "A line can't be empty" · "That line is no longer there"
  - "Process again" · title `Process “<title>” again?` · "The same audio with the same settings gives the same words. To try for better ones, choose another accuracy or languages." · "Your fixes to its lines will be replaced."
  - Settings heading "Storage", tile "Downloaded models" with subtitle "Download or delete the speech models"; page title "Storage"; the tag "Downloaded"; "Download"; "Delete <name>?"; "Frees X MB. If a later setting needs it, it downloads again by itself."; "Frees X MB, but the speech settings or a recording waiting to be processed need it. It downloads again before then."; "Deleted — X MB freed"; "It's in use right now — try again when processing has finished"
- **Edits:**
  - offered only when the recording's status is `done` or `error`;
  - an edited line keeps its start, end and id;
  - Leave out and vocabulary are not applied to it.
- **Process again:**
  - offered only for `done` or `error`;
  - the dialog pre-sets **More accurate** and the recording's own languages; the preferred Indian language stays the recording's;
  - the recording's setup becomes the one chosen.
- **The green tag** is `VdBadge('Downloaded', kind: BadgeKind.ok)`.

## Review Focus

- **Process again with a model missing for the chosen setup.** Expected: the recording waits, the banner offers the download (Plan 2b's `neededModelIdsProvider`), and the old text stays visible. Task 4 test `processing again with a missing model waits and keeps the old text`.
- **The app killed in the middle of a re-run.** Expected: it resumes from `processedMs` without repeating its new lines; the old lines are untouched until the end. Task 4 test `a re-run cut off resumes without repeating its new lines`.
- **Deleting a model while recording or processing.** Expected: refused with the in-use message. Task 6 test `a model can't be deleted while processing`.
- **An edit to Gujarati text, punctuation only, or an empty line.** Expected: words re-timed (Gujarati letters and vowel signs count as letters); an empty line refused. Task 2 tests.
- **A re-run that fails.** Expected: the old text stays and Try again continues the re-run, not a fresh one. Task 4 test `a failed re-run keeps the old lines, and Try again continues it`.

---

### Task 1: Other names people call you

**Files:**
- Modify: `mobile/backend/lib/engine/speech/your_words.dart`, `mobile/backend/lib/engine/speech/vocabulary.dart`, `mobile/frontend/lib/ui/settings/settings_screen.dart`, `mobile/frontend/test/ui/fakes.dart`
- Test: `mobile/backend/test/engine/speech/your_words_test.dart`, `mobile/backend/test/engine/speech/vocabulary_test.dart`, `mobile/frontend/test/ui/settings_screen_test.dart`

**Interfaces:**
- Produces:
  - `YourWords.aliases` (String, settings key `aliases`);
  - `YourWordsNotifier.set({String? name, String? aliases, String? vocabulary, String? leaveOut})`;
  - `Vocabulary.fromSettings({required String name, String aliases = '', required String vocabulary, required CommonWords common, double fixBelow = 0.6})`. Each alias, split on commas and new lines, and its parts of 3+ letters become entries, like the name.
  - The settings field `Key('your-aliases')`, under "Your name".

- [ ] **Step 1: Write the failing tests**
  - `other names are saved and read back`.
  - `an other name is fixed like the name` (aliases `Nishu, Nish Bhai`: "Nishoo" with conf 0.3 → "Nishu"; "Nishoo" with conf 0.95 stays).
  - Frontend: `other names are saved when you leave the field` (saved `aliases:Nishu`).
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint** (both packages).

### Task 2: Editing a line, with its words re-timed

**Files:**
- Create: `mobile/backend/lib/data/retime.dart`
- Modify: `mobile/backend/lib/data/transcript.dart`, `mobile/backend/lib/data/transcript_repository.dart`
- Test: `mobile/backend/test/data/retime_test.dart`, `mobile/backend/test/data/transcript_repository_test.dart`

**Interfaces:**
- Produces:
  - `Phrase.id` (`int?`; set on lines read from the database, null on the engine's; included in equality);
  - `List<Word> retimeWords(List<Word> old, String text, int startMs, int endMs)`: a port of `desktop/backend/core/src/transcript.rs` `retime_words` (lines 169–226) in ms. Kept words keep their times and `conf`; new words get even shares and no `conf`. Words are compared by `norm`: lowercase, keeping letters, digits and marks;
  - `class LineGone implements Exception`;
  - `Future<void> TranscriptRepository.editLine(int lineId, String text)`: trims; empty → `ArgumentError`; a missing line → `LineGone`; changes only `text` and `wordsJson`.

- [ ] **Step 1: Write the failing tests** (the desktop's tests, in ms)
  - `edited text keeps the times of unchanged words`: old `send 0–500, the 500–700, report 700–1200`, text "Send the final report.", 0–2000 → words `Send, the, final, report.`; "final" is 700–700; "report." starts at 700.
  - `new words at the end share the rest of the time`: `hello 0–1000` → "hello there friend" → (0,1000), (1000,2000), (2000,3000).
  - `Gujarati words match by their letters and signs`: "હા એનું background" → "હા એનું બેકગ્રાઉન્ડ"; the first two keep their times.
  - Repository: `editing a line changes its text and words, nothing else`.
  - Repository: `an empty line is refused`.
  - Repository: `editing a line that is gone throws LineGone`.
  - Repository: `lines read back carry their id`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS; all other backend tests pass.
- [ ] **Step 5: Checkpoint.**

### Task 3: Fix the words (screen)

**Files:**
- Modify: `mobile/frontend/lib/ui/recording/recording_detail_screen.dart`
- Test: `mobile/frontend/test/ui/recording_detail_test.dart`

**Interfaces:**
- Consumes: `Phrase.id`, `editLine`, `LineGone` (Task 2).
- Produces:
  - **Long-press a line** opens a bottom sheet with "Fix the words". The long-press does nothing unless the status is `done` or `error`. Tapping words and times still plays.
  - "Fix the words" opens a dialog with a `TextField(key: Key('line-edit'))` holding the line's text, and Cancel / Save. Save is disabled while the field is empty.
  - Save calls `editLine`; a `LineGone` shows a SnackBar "That line is no longer there".

- [ ] **Step 1: Write the failing tests**
  - `long-press a line and fix its words` (the fake repository records `edit:<lineId>:<text>`).
  - `Save is off for an empty line`.
  - `no fixing while the recording is being processed`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint** (frontend).

### Task 4: Process again (backend)

**Files:**
- Modify: `mobile/backend/lib/data/db.dart` (+ `db.g.dart`), `recording.dart`, `recordings_repository.dart`, `transcript_repository.dart`, `mobile/backend/lib/engine/pipeline/processor.dart`
- Test: `mobile/backend/test/data/migration_test.dart`, `transcript_repository_test.dart`, `mobile/backend/test/engine/pipeline/processor_test.dart`

**Interfaces:**
- Produces:
  - Schema 4: `TranscriptLines.draft` (bool, default false) and `Meetings.reprocessing` (bool, default false); migration from 3.
  - `Recording.reprocessing`.
  - `TranscriptRepository.save(int id, List<Phrase> phrases, {required int processedMs, bool draft = false})`; `watch` shows non-draft lines only.
  - `Future<void> TranscriptRepository.commitDraft(int meetingId)`: in one transaction, deletes the non-draft lines, makes the drafts normal lines, and clears `reprocessing`.
  - `Future<void> RecordingsRepository.processAgain(int id, SpeechSetup setup)`: in one transaction, deletes leftover draft lines and sets `reprocessing = true`, `processedMs = 0`, `attempts = 0`, status `queued` and the setup columns.
  - `Future<void> Processor.processAgain(int id, SpeechSetup setup)`: calls the repository, then `kick()`.
  - The processor saves with `draft: r.reprocessing`. At the end of the job it calls `commitDraft` before `done`. `retry` leaves `reprocessing` as it is.

- [ ] **Step 1: Write the failing tests**
  - Migration: `a version-3 database opens as version 4 with no drafts`.
  - Repository: `draft lines stay hidden until committed, then replace the old ones`.
  - Processor:
    - `processing again keeps the old lines until the new ones are complete, then shows only the new` (watch during the job: old; after: new);
    - `processing again uses the setup chosen for it`;
    - `processing again with a missing model waits and keeps the old text`;
    - `a re-run cut off resumes without repeating its new lines` (a job stopped mid-way by the gate, then resumed);
    - `a failed re-run keeps the old lines, and Try again continues it`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement**; regenerate drift.
- [ ] **Step 4: Run them** — PASS; the whole backend suite passes.
- [ ] **Step 5: Checkpoint.**

### Task 5: Process again (screen)

**Files:**
- Modify: `mobile/frontend/lib/ui/recording/recording_detail_screen.dart`, `mobile/frontend/test/ui/fakes.dart` (`IdleProcessor.processAgain` records its calls)
- Test: `mobile/frontend/test/ui/recording_detail_test.dart`

**Interfaces:**
- Consumes: `Processor.processAgain`, `Recording.setup`, `Lang`, `EnglishModel` (Plan 2b), `languageName` (wording).
- Produces: an AppBar `IconButton(key: Key('process-again'), icon: Icons.refresh, tooltip: 'Process again')`, enabled only for `done` / `error`. Its dialog follows the Global Constraints:
  - a `SegmentedButton<EnglishModel>` Faster / More accurate;
  - `FilterChip`s for the languages (at least one stays on);
  - Cancel / Process again.

- [ ] **Step 1: Write the failing tests**
  - `Process again asks, with More accurate and the recording's languages pre-set` (confirm → `processAgain(7, en+gu, accurate)`).
  - `choosing Faster and English only is what is processed`.
  - `Cancel does nothing`.
  - `not offered while processing`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint** (frontend).

### Task 6: Storage: every downloaded model, with green tags

**Files:**
- Create: `mobile/frontend/lib/ui/settings/storage_screen.dart`
- Modify:
  - `mobile/backend/lib/engine/models/speech_model.dart` (`Models.bytesOnDisk(ModelId)`, delegating to the store);
  - `mobile/frontend/lib/ui/settings/settings_screen.dart` (heading "Storage" + the tile);
  - `mobile/frontend/lib/ui/settings/speech_card.dart` (green tags);
  - `mobile/frontend/lib/ui/wording.dart`;
  - `mobile/frontend/test/ui/fakes.dart`
- Test: `mobile/frontend/test/ui/storage_screen_test.dart`, `mobile/frontend/test/ui/speech_card_test.dart`

**Interfaces:**
- Consumes: `modelsProvider`, `neededModelIdsProvider`, `recorderProvider`, `processorProvider`, `freeSpaceProvider`, `kCatalogue`.
- Produces: `StorageScreen`.
  - **Header:** "Models: X MB · Free on this phone: Y GB".
  - **One row per model** except `indicTokens` (counted with Hindi/Gujarati), in catalogue order, each with its name and size:
    - ready: the green tag and a Delete icon (`tooltip: 'Delete'`);
    - missing: "Download" with its MB;
    - downloading: its percent and a progress bar;
    - failed: the reason and "Try again".
  - **Delete:** refused while the recorder isn't idle or the processor is busy (`ProcessingState.recordingId != null`). Otherwise it asks, with the "needed" variant when `neededModelIdsProvider` contains the model, deletes, and shows the "Deleted — X MB freed" SnackBar.
  - **Speech card:** an Accuracy row whose model is ready shows the green tag, followed by "about N min for a 30-min recording".

- [ ] **Step 1: Write the failing tests**
  - `every model is listed with its state` (no "Hindi/Gujarati words" row).
  - `downloaded is a green tag`.
  - `Download starts it`.
  - `Delete asks, then deletes and says what was freed`.
  - `a model the settings need says so before deleting`.
  - `a model can't be deleted while processing`.
  - Speech card: `a downloaded accuracy model shows the green tag` (replaces the old text expectation).
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS; the whole frontend suite passes.
- [ ] **Step 5: Checkpoint** (both packages).

### Task 7: On the Galaxy M31, and the docs

- [ ] **Step 1: Check the phone first.** Only when the app's foreground service isn't running (`dumpsys activity services com.rajvee.mobile`: no recording or processing), install the debug build (`pm install -r`). Otherwise leave it for the owner and say so.
- [ ] **Step 2: Check on the phone, by screenshots:**
  - Settings → "Other names people call you";
  - Storage (green tags, sizes);
  - a recording: long-press → Fix the words → saved;
  - Process again with More accurate. This needs its 482 MB: ask the owner before downloading it, or use Faster + Gujarati, already on the phone.
- [ ] **Step 3: Update the docs.**
  - The mobile spec's Plans list: 2c-a built.
  - The status file.
  - A new ledger `2026-10-14-mobile-plan-2c-progress.md`.
