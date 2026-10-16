# Mobile app, Plan 4: Summary and tasks — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a recording's text and speakers, the phone writes a short summary and finds the owner's own tasks, offline, with Qwen3 through llama.cpp. They show on the recording's screen and in the Tasks tab.

**Architecture:**
- **The model:** llama.cpp (the desktop's pinned build `b11320`) is compiled into the app with the NDK, behind a small C shim `vd_llm` with five functions. Dart calls it through FFI, in an isolate, like the speech engine.
- **The same shim builds for Windows,** so the real model runs in the PC tests.
- **The rest is pure Dart, testable with a fake engine:** prompts (the desktop's rules, without example sentences), parts sized by tokens, the JSON answer, the quote check, and a tasks queue in the processor that gives way to speech.
- **Task 1 is a spike on the M31 that confirms the FFI route:** speed, memory, and running with the screen off. If FFI fails its criteria, the route switches to `llama-server` as the desktop runs it; Tasks 2–8 don't depend on the route.

**Tech Stack:**
- As Plan 2c-b, plus llama.cpp `b11320` (C/C++), built with Android NDK 28.2 + CMake 4.1.2.
- Windows: Visual Studio Build Tools 2026.
- No new Dart packages (FFI is `dart:ffi`).
- drift schema 6 → 7.

**Spec:** [docs/superpowers/specs/2026-10-15-mobile-tasks-design.md](../specs/2026-10-15-mobile-tasks-design.md) (approved 2026-10-16). Owner's answers: "yes give choice" (1.7B everywhere, 4B "More accurate" on 8 GB+ phones); strict when no line is "Me". Measurements: the session scratchpad's `taskai/` (compare.py holds the v2 prompts, quote_check.py the check).

**Not in this plan:** calls (Plan 5), the desktop's prompt, reminders/calendar, translation.

## Global Constraints

- **The owner commits.** "Checkpoint" = `flutter test` + `flutter analyze` in the touched packages.
  - Never run `dart format`: the backend is laid out by hand in the old style, the frontend in the tall style.
  - The phone is reached over Wi-Fi (adb wireless debugging). Install only when the app's foreground service isn't running.
- **Models (pinned, as the desktop):**
  - `ModelId.taskFaster`: `https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/d7f544eead698dbd1f15126ef60b45a1e1933222/Qwen3-1.7B-Q4_K_M.gguf`, 1,107,409,472 B, SHA-256 `b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897`.
  - `ModelId.taskAccurate`: `https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/22c9fc8a8c7700b76a1789366280a6a5a1ad1120/Qwen3-4B-Q4_K_M.gguf`, 2,497,281,312 B, SHA-256 `f6f851777709861056efcdad3af01da38b31223a3ba26e61a4f8bf3a2195813a`.
  - Saved under `tasks/`. Names: "Task AI (Faster)", "Task AI (More accurate)".
- **Settings:**
  - `find_tasks` (bool, default true): Settings → Processing "Find tasks".
  - `task_ai` (`faster` | `accurate`, default `faster`): Settings → Processing "Task AI", with "Faster" / "More accurate". It is shown only on phones with total RAM ≥ 7 GiB (Android reports ~7.3 GiB for 8 GB phones); elsewhere it is always `faster`.
- **Running:** 4 threads, context 8,192, temperature 0.1, at most 1,536 tokens per answer, seed 1.
  - On invalid JSON, one retry with seed 2, then the step fails.
  - Thinking is off: the Qwen3 chat template with an empty `<think>\n\n</think>\n\n`.
  - The answer is constrained by a GBNF grammar for the JSON schema `{summary: string, tasks: [{description, assigned_by|null, due|null, quote|null}]}`.
  - The model is unloaded after each job, and the memory handed back as for speech.
- **Prompts:** the v2 texts (`taskai/compare.py` `SYSTEM_V2`, `SYSTEM_SELF_V2`) and the desktop's:
  - user prompt: `{me}\nTitle: "{title}"{part}\n\nTranscript:\n"""\n{part text}\n"""\n\n{ask}`;
  - who-am-I sentence;
  - merge prompt and merge system text "You merge meeting notes. Output only the requested JSON.";
  - asks "Extract the user's action items and summarize." / "Extract the user's to-dos and summarize.".
- **Parts:** about 3,000 tokens of transcript each (the model's own tokenizer), cut at line ends, the last ~400 tokens carried over with "(…continued) "; a line longer than a part is cut at word ends. Several parts get one merge pass.
- **The quote check** (on every task, after the answer):
  - **Kept** when the quoted line:
    - is the owner's ("Me"); or
    - is addressed to him: his name, an alias, or second person (`\b(you|your|yours)\b|तुम|आप|तू|तुझे|तुम्हें|तेरा|તું|તમે|તને|તમને|તારે|તમારે|તારું|તમારું`);
  - **Dropped** when the quote opens with a capitalised Latin name that isn't his (greeting words excepted: hello hi hey okay ok thanks yes so and well right sure great good last also then now fine please one first).
  - **A quote not in the transcript** is kept.
  - **Strict (owner):** with no "Me" line in the recording, a task is kept only when addressed to him. The recording's screen then says "Train your voice so your own promises are found too."
  - Then the desktop's clean-up: a garbled label ("Speaker :1") is snapped back to the real one, and "me"/"self" becomes "Self".
- **Mode:**
  - **To-do list:** every line with a speaker is "Me"; or the recording has a single speaker group and no voice is trained.
  - **Meeting:** everything else.
- **Queue:**
  - A recording is `done` after text and speakers. Its tasks have their own state, `tasksStatus`: `none` | `waiting` | `finding` | `found` | `failed`.
  - The step runs only when no speech job can run, saving after every part (`tasksPart`, `tasksWork`).
  - It gives way between parts: to a recording being made, to a recording waiting for its text, and to the battery (under 20% and not charging) and heat rules. It continues from the next part.
  - Older recordings stay `none` until "Find tasks".
- **Re-runs** (Process again, Find tasks):
  - the AI's untouched tasks are replaced;
  - tasks added, edited or ticked by the owner are kept (reordering doesn't count);
  - a new AI task whose quote matches a kept or deleted one is dropped;
  - deleted AI tasks stay as hidden rows.
- **Wording (exact):**
  - "Summary", "Your tasks", "Find tasks", "Finding tasks…";
  - "Finding tasks in “<title>” · part N of M";
  - "Couldn't find tasks." with "Try again";
  - "Train your voice so your own promises are found too.";
  - "No speech was detected." (summary, no tasks);
  - "Downloading the task model…";
  - Tasks tab heading "My tasks";
  - "Show N completed" / "Hide N completed";
  - "Add a task…", "Task copied", "Drag to reorder", "Where it was said", "Due (e.g. Friday)";
  - Settings: "Find tasks" (subtitle "A summary and your tasks, after each recording"), "Task AI", "Faster", "More accurate".

## Review Focus

- **The app killed in the middle of the tasks step.** Expected: at the next start the step continues from the next part, and no task is saved twice. Task 6 test `a step cut off continues from the next part`.
- **A recording started while tasks are being found.** Expected: the step stops at the end of the part, the new recording's text comes first, and the step continues afterwards. Task 6 test `a recording made meanwhile goes first`.
- **The owner ticks or edits a task while Find tasks runs again.** Expected: his change is kept and the task isn't added a second time. Task 4 test `a re-run keeps a task changed during it`.
- **Find tasks without the task model on the phone.** Expected: the recording waits ("Downloading the task model…" / the banner offers it); speech isn't held up. Task 6 test `without the task model the step waits and speech goes on`.
- **A recording deleted while its tasks are being found.** Expected: the step stops cleanly, and its tasks go with it. Task 6 test `a recording deleted mid-step leaves nothing behind`.

---

### Task 1: llama.cpp in the app, through FFI (spike first)

**Files:**
- Create:
  - `mobile/native/llm/CMakeLists.txt` (llama.cpp `b11320` via FetchContent, URL + SHA-256 of the tag's source tarball; builds `vd_llm` shared, CPU only, no server or tools);
  - `mobile/native/llm/vd_llm.cpp`, `vd_llm.h`;
  - `mobile/native/llm/build_windows.ps1` (`vd_llm.dll` + llama/ggml DLLs into `mobile/native/llm/out/windows/`, git-ignored);
  - `mobile/backend/lib/engine/tasks/llm_engine.dart`.
- Modify: `mobile/frontend/android/app/build.gradle.kts` (`externalNativeBuild { cmake { path = file("../../../native/llm/CMakeLists.txt") } }`, arm64-v8a only), `.gitignore`.
- Test: `mobile/backend/test/engine/tasks/llm_engine_test.dart` (real model, behind `VOICEDESK_LLM_MODEL` + `VOICEDESK_LLM_LIB`).

**Interfaces:**
- Produces (C, `vd_llm.h`):
  ```c
  void* vd_llm_load(const char* model_path, int n_ctx, int n_threads);   // null on failure
  int   vd_llm_count_tokens(void* h, const char* text);                   // -1 on failure
  char* vd_llm_generate(void* h, const char* prompt, const char* grammar, int max_tokens, float temperature, unsigned int seed); // malloc'd UTF-8, null on failure
  void  vd_llm_free_string(char* s);
  void  vd_llm_close(void* h);
  ```
- Produces (Dart):
  - `abstract class LlmEngine { Future<int> countTokens(String text); Future<String> generate({required String prompt, required String grammar, int maxTokens = 1536, double temperature = 0.1, int seed = 1}); Future<void> close(); }`
  - `class LlamaEngine implements LlmEngine` with `static Future<LlamaEngine> start(File model, {int threads = 4, int contextSize = 8192, String? libraryPath})`.
    - Runs in its own isolate.
    - `close()` frees the model, then the isolate hands memory back (`mallopt` as `SherpaSpeech`).
  - `class LlmFailed implements Exception { final String reason; }`

- [ ] **Step 1: Spike on the M31.** Build `vd_llm` for arm64 with the NDK, and a throwaway debug app screen that loads Qwen3 1.7B from `/data/local/tmp` (pushed) and generates 300 tokens from a 3,000-token prompt. Record in the ledger:
  - load time;
  - prompt tokens/s and generated tokens/s;
  - peak PSS (`dumpsys meminfo`);
  - the same run with the screen off for 5 minutes under the foreground service.

  **Go on with FFI if** it completes with the screen off and the peak is under 2 GB. Otherwise stop and switch Task 1 to `llama-server` packed as `libllama_server.so` and run on 127.0.0.1, as `desktop/backend/core/src/llm.rs` does, keeping the `LlmEngine` interface.
- [ ] **Step 2: Write the failing tests** (real model on the PC):
  - `counts tokens with the model's tokenizer`: "Hello world" gives 2–3; a Gujarati sentence gives more than its English one;
  - `an answer follows the grammar`: `jsonDecode` succeeds and has `summary` and `tasks`;
  - `the same seed gives the same answer`;
  - `closing frees it`: RSS growth over 3 load/close cycles is under 300 MB.
- [ ] **Step 3: Run them** — FAIL (no library).
- [ ] **Step 4: Implement** the shim:
  - sampler chain: grammar → temperature → dist(seed);
  - stops at end-of-generation or `max_tokens`;
  - the Dart side via `DynamicLibrary.open` (`libvd_llm.so` on Android, the `libraryPath` DLL on Windows).
- [ ] **Step 5: Run them** — PASS. Then **Checkpoint.**

### Task 2: The task models and their settings

**Files:**
- Modify: `mobile/backend/lib/engine/models/catalogue.dart`, `speech_model.dart` (`neededModelIdsProvider`), `speech_setup.dart` (`PhoneClass.canRunLargeTaskAi`), `mobile/frontend/lib/ui/wording.dart`, `settings/settings_screen.dart`, `settings/storage_screen.dart`.
- Create: `mobile/backend/lib/engine/tasks/task_settings.dart`.
- Test: `test/engine/tasks/task_settings_test.dart`, frontend `settings_screen_test.dart`, `storage_screen_test.dart`.

**Interfaces:**
- Produces:
  - `ModelId.taskFaster`, `ModelId.taskAccurate` (added last), with the Global Constraints pins;
  - `enum TaskAi { faster, accurate }`;
  - `taskSettingsProvider = AsyncNotifierProvider<TaskSettingsNotifier, TaskSettings>`:
    - `TaskSettings(findTasks: true, ai: TaskAi.faster)`;
    - `setFindTasks(bool)`, `setAi(TaskAi)`;
    - keys `find_tasks`, `task_ai`;
  - `taskModelProvider = FutureProvider<ModelId?>` (null when Find tasks is off; `taskFaster` unless `accurate` and the phone can run it);
  - `PhoneClass.canRunLargeTaskAi` (total RAM ≥ 7 GiB);
  - `neededModelIdsProvider` includes the task model when Find tasks is on.
  - The Speech card's processing rows don't change.

- [ ] **Step 1: Write the failing tests:**
  - `Find tasks is on by default and kept`;
  - `More accurate needs a phone with 8 GB`;
  - `the task model is needed while Find tasks is on`;
  - screens: `the Find tasks switch saves it`, `Task AI shows only on an 8 GB phone`, `Storage lists both task models`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS. **Checkpoint.**

### Task 3: Prompts, parts, the answer and the quote check (pure Dart)

**Files:**
- Create in `mobile/backend/lib/engine/tasks/`:
  - `task_prompts.dart` (the v2 system texts, who-am-I, asks, merge prompt, ChatML wrapper);
  - `task_grammar.dart` (the GBNF constant);
  - `task_parts.dart`;
  - `task_answer.dart`;
  - `quote_check.dart`;
  - `task_mode.dart`.
- Test: one test file per source file under `mobile/backend/test/engine/tasks/`.

**Interfaces:**
- Produces:
  - `String transcriptForAi(List<Phrase> lines)`: `[mm:ss] Speaker: text`, one speaker's lines joined, lines without a speaker as `[mm:ss] text`. This is the desktop's `format_transcript`.
  - `String whoAmI(YourWords words)`.
  - `String chatPrompt(String system, String user)`: the Qwen3 ChatML, thinking off.
  - `Future<List<String>> transcriptParts(String transcript, Future<int> Function(String) countTokens, {int maxTokens = 3000, int overlapTokens = 400})`.
  - `class FoundTask { String description; String? assignedBy; String? due; String? quote; }` and `class TaskAnswer { String summary; List<FoundTask> tasks; }`, with `TaskAnswer.parse(String json)`, which throws `FormatException`.
  - `List<FoundTask> snapLabels(List<FoundTask>, Set<String> speakers)`.
  - `bool keepTask(FoundTask t, List<Phrase> lines, {required List<String> ownerNames, required bool hasMe})`.
  - `int? quoteStartMs(FoundTask t, List<Phrase> lines)`.
  - `enum TaskMode { meeting, todo }` and `TaskMode taskMode(List<Phrase> lines, {required bool voiceTrained})`.

- [ ] **Step 1: Write the failing tests:**
  - Ported from `llm.rs`:
    - `the transcript groups a speaker's lines`;
    - `long transcripts are cut at line ends with the last part carried over` (fake counter: 1 token per 4 chars);
    - `a garbled label is snapped back` ("Speaker :1" → "Person 1"; "me" → "Self").
  - The quote check (the cases from `taskai/cases.py`):
    - `the owner's own line is kept`;
    - `a line to him by name or "you" is kept`;
    - `"Priya, please update the slide" is dropped`;
    - `"Hello, …Nishchay, you need…" is kept (greeting)`;
    - `his name in Gujarati script is not someone else's`;
    - `a quote not in the transcript is kept`;
    - `with no "Me" line, his own "I'll send it" is dropped`.
  - `the answer parses, and a broken one throws`.
  - `to-do list when only Me speaks, or one voice without a trained voice; meeting otherwise`.
  - `the ChatML has thinking off`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS. **Checkpoint.**

### Task 4: Tasks and summaries in the database

**Files:**
- Create: `mobile/backend/lib/data/tasks_repository.dart`.
- Modify: `db.dart` (+g; schema 7), `recording.dart`, `recordings_repository.dart`, `providers.dart`.
- Test: `test/data/tasks_repository_test.dart`, `migration_test.dart`.

**Interfaces:**
- Produces:
  - Table `Tasks`:
    - id; meetingId (deleted with it);
    - description; assignedBy?; due?; quote?; quoteMs?;
    - done; position;
    - `fromAi`, `edited`, `deleted`;
    - createdAt.
  - `Meetings`: `tasksStatus` (text, default `none`), `tasksPart` (int, default 0), `tasksWork` (text JSON, default `''`).
  - `Recording`: `tasksStatus`, `summary`.
  - `TasksRepository`:
    - `watchAll()`: open by position, then done;
    - `watchFor(int meetingId)`;
    - `add(String description, {int? meetingId})`;
    - `edit(int id, {String? description, String? due})`: sets `edited`;
    - `setDone(int id, bool done)`: sets `edited`;
    - `delete(int id)`: an AI task becomes a hidden `deleted` row; the owner's own is removed;
    - `reorder(List<int> ids)`;
    - `saveFound(int meetingId, String summary, List<(FoundTask, int? quoteMs)> found)`: the re-run rules, in one transaction.
  - The queue (`RecordingsRepository`):
    - `tasksWaiting()`: done recordings with `tasksStatus` `waiting` or `finding`, oldest first;
    - `setTasksStatus(int id, String status)`;
    - `saveTasksPart(int id, int part, String work)`.

- [ ] **Step 1: Write the failing tests:**
  - `found tasks are saved with the summary`;
  - `a re-run replaces untouched AI tasks and keeps the owner's`;
  - `a deleted AI task is not found again`;
  - `a re-run keeps a task changed during it`;
  - `the Tasks tab order: open by position, done last`;
  - migration `a version-6 database opens as version 7`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS. **Checkpoint.**

### Task 5: Finding a recording's tasks

**Files:**
- Create: `mobile/backend/lib/engine/tasks/task_finder.dart`.
- Test: `test/engine/tasks/task_finder_test.dart` (fake `LlmEngine`).

**Interfaces:**
- Consumes: Tasks 1, 3, 4.
- Produces:
  - `class TaskFinder` with `TaskFinder(LlmEngine engine, {required YourWords words, required bool voiceTrained})` and `Future<TaskStep> next(Recording r, List<Phrase> lines, {required int part, required String work})`. It runs **one** part, or the merge once all parts are done. It returns `TaskStep.part(int next, String work, int ofParts)` or `TaskStep.done(String summary, List<(FoundTask, int?)> found)`.
  - No speech: `TaskStep.done('No speech was detected.', [])`.
  - Invalid JSON: retried once with seed 2, then `LlmFailed('invalid_json')`.

- [ ] **Step 1: Write the failing tests:**
  - `one part: the answer, checked and snapped`;
  - `three parts then one merge`;
  - `the work so far is carried in the step` (a new `TaskFinder` given `part` and `work` continues);
  - `invalid JSON is tried once more, then fails`;
  - `a to-do list uses the own-notes prompt`;
  - `no speech gives the desktop's summary`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS. **Checkpoint.**

### Task 6: The tasks queue in the processor

**Files:**
- Modify: `mobile/backend/lib/engine/pipeline/processor.dart` (+ `ProcessingState.step` `tasks`, `part`, `parts`), `speed_book.dart` (key `tasks:<faster|accurate>`), `recordings_repository.dart` (Process again → `tasksStatus` `waiting` after speech).
- Test: `processor_test.dart` (group `tasks`, fake engine through `llmEngineFactoryProvider`).

**Interfaces:**
- Produces:
  - `llmEngineFactoryProvider = Provider<Future<LlmEngine> Function(File model)>`;
  - `Processor.findTasks(int id)` (sets `waiting`, kicks);
  - `_tasksStep()`, which runs after speech and upkeep when no speech job can run:
    1. the oldest of `tasksWaiting()`;
    2. its model is ready, else `ProcessingState(waiting: 'task_model')`;
    3. the engine is started once per pass;
    4. one part at a time, saving after each;
    5. it gives way (see Global Constraints);
    6. the engine is closed at the end of the pass;
  - A recording reaching `done` with Find tasks on gets `tasksStatus` `waiting`.
  - On failure: `failed` (error kept in `tasksWork`); Try again → `findTasks`.

- [ ] **Step 1: Write the failing tests:**
  - `after the text, tasks are found and saved`;
  - `with Find tasks off nothing is found`;
  - `a step cut off continues from the next part`;
  - `a recording made meanwhile goes first`;
  - `without the task model the step waits and speech goes on`;
  - `a recording deleted mid-step leaves nothing behind`;
  - `a failed step can be tried again`;
  - `Find tasks on an old recording runs only this step`;
  - `the engine is closed after the pass`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS. **Checkpoint.**

### Task 7: The recording's screen and the Tasks tab

**Files:**
- Create: `mobile/frontend/lib/ui/tasks/task_row.dart`.
- Modify: `ui/tasks/tasks_screen.dart`, `ui/recording/recording_detail_screen.dart`, `ui/wording.dart` (`processingLine` for step `tasks`), `ui/record/speech_model_banner.dart` (the task model in the banner).
- Test: frontend `tasks_screen_test.dart`, `recording_detail_test.dart`, `processing_test.dart`.

**Interfaces:**
- Produces:
  - `TaskRow` (shared by both screens):
    - tick;
    - tap to edit the words and "Due (e.g. Friday)";
    - menu Copy ("Task copied") / Delete (snack with Undo, as recordings) / "Where it was said";
    - drag handle "Drag to reorder" (open tasks only).
  - The Tasks tab: "My tasks", the open tasks (reorderable), "Show N completed" / "Hide N completed", "Add a task…".
  - **"Where it was said"** opens the recording's screen and plays from `quoteMs`: `RecordingDetailScreen(recordingId: id, playFromMs: ms)`.
  - **The recording's screen** below the player:
    - "Summary";
    - "Your tasks";
    - "Find tasks" (not while finding);
    - "Finding tasks…";
    - "Couldn't find tasks." + "Try again";
    - the train-your-voice hint (strict mode, no trained voice).

- [ ] **Step 1: Write the failing tests:**
  - Tasks tab:
    - `open tasks first, completed behind Show N completed`;
    - `tick, edit, copy, delete with Undo`;
    - `add a task`;
    - `drag to reorder saves the order`;
    - `Where it was said opens the recording at the line`.
  - Recording:
    - `the summary and its tasks show`;
    - `Find tasks runs it`;
    - `while finding it says so`;
    - `a failed step offers Try again`;
    - `without Me lines the hint shows`.
  - Processing line: `Finding tasks in “Weekly review” · part 2 of 3`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS. **Checkpoint.**

### Task 8: The real model on the PC, then the M31, then the docs

- [ ] **Step 1: The PC gate** (`test/engine/tasks/task_quality_test.dart`, behind the environment variables):
  - It runs the Dart `TaskFinder` with `LlamaEngine` (Windows DLL) and Qwen3 1.7B on `taskai/cases.py`'s 12 cases, ported to Dart test data, 3 seeds.
  - It must find ≥ 57/57 tasks, with ≤ 5 of other people's tasks in 36 runs.
  - New cases:
    - a long mostly-Gujarati meeting (several parts by tokens);
    - a meeting with no "Me" lines;
    - a single-speaker voice note with no trained voice.
  - The same with 4B: ≥ 57/57.
- [ ] **Step 2: On the M31** (release build, installed when idle):
  - Find tasks on the David/Zira recording;
  - a 30-min recording's tasks step: time and peak memory, on battery and on charge;
  - the Tasks tab actions;
  - "Where it was said".
- [ ] **Step 3: Docs.**
  - Mobile spec Plans list (4 built).
  - Status file.
  - Ledger `2026-10-16-mobile-plan-4-progress.md`.
