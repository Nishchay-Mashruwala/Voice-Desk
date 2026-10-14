# Frontend / backend split — design

Date: 2026-10-09 · Status: part 1 done (folders + core); part 2 draft for review

## Goal

Put all of Voice Desk's code in two top-level folders, `frontend/` (UI only)
and `backend/` (all logic), so that a commercial version can later run the
heavy work (transcribing, finding tasks) on a server by uploading `backend/`
and adding a thin HTTP layer, with no untangling.

Constraints from the owner:

- Two top-level code folders: `frontend/` holds only UI; logic lives in `backend/`.
- No behaviour change now: same features, installer, data folders, settings
  and existing databases. Everything still runs on the user's computer.
- `node_modules` stays out of git (already true: `.gitignore` has
  `node_modules`, which matches at any depth, and no such file is tracked).

Out of scope: an actual server, HTTP API, accounts or auth, uploads, a new
frontend. This change only makes them possible without restructuring again.

## Layout

```
frontend/                  UI only
  src/  public/  index.html
  package.json  package-lock.json  vite.config.ts  tsconfig.json  tsconfig.node.json
backend/                   all logic
  Cargo.toml               Rust workspace: members core, desktop
  engine/                  Python speech engine (was engine/), unchanged
  core/                    Rust library `voicedesk-core`, no Tauri dependency
  desktop/                 Tauri app (was src-tauri/), crate `voicedesk`
docs/  scripts/  .github/  README.md  .gitignore  "Setup Voice Desk (Windows).bat"
```

Moves use `git mv` so history follows the files.

On a future server: build `backend/engine` and `backend/core` (plus a new
`backend/server/` binary). `backend/desktop` is not built there: it only makes
sense on a user's computer.

## backend/core

A library crate with no `tauri` dependency. These modules move from
`src-tauri/src/` as they are:

| Module | Does |
|---|---|
| `llm.rs` | Task AI: runs `llama-server`, finds tasks and the summary |
| `pipeline.rs` | Recording → transcript → tasks |
| `db.rs`, `secrets.rs` | Database, Hugging Face token |
| `search.rs`, `omit.rs` | Search, left-out words ("umm") |
| `engine.rs`, `engine_setup.rs`, `downloads.rs` | Run and install the Python engine; verified downloads |
| `hardware.rs` | GPUs, RAM, cores (picks the task-AI size; memory in use) |
| `models.rs` (new) | The model logic now in `system.rs`: list downloaded models, which are in use, delete one (including in-use deletes) |

Helpers it needs move with it: `merge_json` (from `session.rs`), the
`audio::recorded` file check, `err`/`CmdResult`-style error conversion.

### Interfaces

1. **`Backend`** — core's state: `db`, `engine`, `llm`, data and recordings
   folders, the models-in-use cache, and methods now on `AppState` that are
   about data (`voice_profile_path`, `recordings_dir`, `meeting_paths`).
   Built once at startup; the desktop holds it in an `Arc`.
2. **`Events`** — one trait method, `emit(&self, name: &str, payload: Value)`.
   Core sends every progress or change notice through it
   (`meeting-progress`, `meeting-warning`, `meetings-changed`,
   `tasks-changed`, download and setup progress). Event names and payloads
   stay exactly as they are, so the UI is unaffected. The desktop implements
   it with Tauri's `AppHandle::emit`; a server would send them over a websocket.

Async: `tauri::async_runtime::spawn`/`spawn_blocking` in these modules become
`tokio::spawn`/`tokio::task::spawn_blocking` (Tauri runs on tokio, so this
works the same inside the app). Core's `tokio` gets the features it needs.

## backend/desktop

The Tauri app; it keeps everything that must run on the user's computer:

- `audio.rs` — mic and system-audio capture
- `session.rs` — live dictation (streams audio to core's engine client)
- `meetings.rs` — starting and stopping recordings, call hand-over; processing
  calls `core::pipeline`
- `meeting_detect.rs`, `overlay.rs`, `hotkey.rs`, `insert.rs`, `jumplist.rs`, `voice.rs`
- `lib.rs`, `main.rs` — app setup, tray, the `AppState` (wraps `Arc<Backend>`
  plus session, meeting, call, overlay fields), the Tauri `Events` impl
- `tasks.rs`, `system.rs` and the data commands in `meetings.rs` — `#[tauri::command]`
  wrappers that call core

Command names, arguments and return types don't change, so `frontend/`
needs no code changes.

## Paths that change

- `tauri.conf.json`: `frontendDist` → `../../frontend/dist`;
  `beforeDevCommand`/`beforeBuildCommand` run npm in `frontend/`; bundled
  engine resources → `../engine/...` (still bundled as `engine/...`, so the
  installed app's layout is unchanged).
- `engine_setup.rs` test's engine path (`CARGO_MANIFEST_DIR`/..), `build.rs`
  (VC++ redist copy), any other `../engine` or `src-tauri` references.
- `.gitignore`: `src-tauri/target` → `backend/target` (workspace target),
  `src-tauri/gen/schemas` → `backend/desktop/gen/schemas`,
  `src-tauri/redist/` → `backend/desktop/redist/`; `dist` already matches
  `frontend/dist`.
- `.github/workflows/build.yml`, `scripts/*` (setup, build-installer,
  check-release, try-as-friend), the Windows setup `.bat`, `README.md`
  (layout diagram and commands).
- Running in development: `npm run tauri dev` from `frontend/`. A root
  `package.json` with pass-through scripts is not added (YAGNI); README shows
  the command.

## Testing

- `cargo test` in `backend/` (both crates): every existing test passes; the
  moved tests run in core.
- Python engine tests in `backend/engine/` pass unchanged.
- `npm run build` in `frontend/` (tsc + Vite) passes.
- `python scripts/check-release.py` passes with the new paths.
- `cargo check -p voicedesk-core` proves core builds without Tauri.
- Manual run of the dev app: a dictation; a meeting recorded, processed, and
  tasks found; Settings → Storage lists models.
- A release build (`npm run tauri build`) produces the installer.

---

# Part 2 — UI only in frontend, logic only in backend

Part 1 moved the files. An audit then found logic still in `frontend/`
(including copies of backend rules that already disagree) and display text
built in `backend/`. Part 2 finishes the split.

**Rule.** `frontend/` renders, handles input, keeps view state, formats
values for display (sizes, durations, dates), and calls backend commands.
It decides nothing about the domain. `backend/` decides, validates and
stores, and sends **data** (ids, numbers, states), not sentences for the
screen. Error messages stay in the backend: they report what went wrong, and
the UI shows them as they are.

## 1. Models: one catalog, one rule (core `catalog.rs`)

Today `frontend/src/models.ts` holds the speech and task model catalog
(sizes, measured RAM/GPU/CPU use, speed), decides which models this computer
can run (`fitModel`), and what Auto means for the task AI (`taskSpec`). The
backend has its own Auto rule (`llm.rs` `TaskModel::from_setting`: 4B at
6 GB of RAM or more). They disagree: a chosen model the frontend thinks
doesn't fit is shown and downloaded as Auto, while the backend runs the
chosen one.

- The catalog moves to `backend/core/src/catalog.rs` (same figures).
  `TaskModel` uses it for file names, URLs and sizes; `from_setting` stays
  the one Auto rule for the task AI.
- New command **`model_options(draft: Settings) -> ModelOptions`**: for the
  speech and task lists, each model with `id`, `download_gb`, `downloaded`,
  `fit` (`on`: gpu or cpu, `ram_gb`, `gpu_gb`, `cores`, `speed_s`) or null,
  and `not_offered` (needs a GPU with N GB, N GB of RAM, or the NVIDIA pack)
  or null; plus `task_auto` (the model Auto means here) and `task_chosen`
  (the model the draft settings would run, exactly as the backend runs it).
  `draft` is the settings on screen, possibly unsaved.
- Speech Auto stays decided by the engine at load time (it depends on free
  GPU memory right then); the UI keeps showing what the engine reports.
- Model names and purposes ("Best for English") are display text: they stay
  in the frontend, keyed by model id.
- `models.ts` keeps only `gb()` and the names and purposes; `fitModel`,
  `whyNot`, `taskSpec` and the figures are deleted. `ModelPicker` renders
  `model_options`.

## 2. First-run setup: one plan, one command

Today `GettingReady.tsx` adds up download sizes (with figures that differ
from the backend's), decides the NVIDIA (GPU of 3 GB or more) and
Hindi/Gujarati packs, and chains save, `setup_status`, one of three
`engine_install` calls, then `llm_pull`.

- New command **`setup_plan(draft: Settings, choices: {nvidia, indic}) -> SetupPlan`**:
  `steps` (each `kind`: engine, engine_finish, indic or task_ai, with its
  `gb`), `total_gb`, `offer_nvidia` (`extra_gb`) or null, `offer_indic`
  (`extra_gb`, `model_gb`) or null. One set of sizes, in `engine_setup.rs`
  and `llm.rs`.
- New command **`setup_start(choices)`**: from the saved settings, runs the
  whole sequence in the backend (engine install with the right packs, then
  the task AI) and reports progress as before. The UI saves first, then
  calls it. `engine_install` and `llm_pull` remain for the backend's own use
  (finishing a setup at start) but the UI no longer sequences them.
- `setup_status` reports what the **saved** settings need (`need_engine`,
  `need_indic`, `need_task_ai`), so `Settings.tsx` stops working it out
  (including suffix-matching file names).

## 3. Transcripts: the backend times words and marks tasks (core `transcript.rs`)

Today the UI computes new word timings when a line or recording is edited
(`retime.ts`, `spreadWords`) and the backend stores them unchecked; the UI
also finds where each task was said (`taskMarks.ts`).

- `retime.ts`, `spreadWords` and `taskMarks.ts` move to Rust
  (`backend/core/src/transcript.rs`), keeping their behaviour, with tests.
- **`update_transcript_line(meeting_id, index, text)`** and
  **`update_dictation_text(id, text)`** take the text only; the backend
  re-times from the stored words and returns the saved words.
- New command **`meeting_transcript(id) -> {segments, tasks}`**: every
  segment has words (spread over the line for old transcripts); each word
  has `task` (an index into `tasks`, or null); each task has `description`,
  `quote` and `at_s` (where it was said, or null). Dictations from
  `list_dictations` get the same `task` on words and `at_s` on their tasks.
  `get_transcript` is replaced.
- The players render these: they underline words that have a task, and "play
  from this task" uses that task's `at_s` (looked up by its quote).

## 4. Rules the backend enforces and publishes

- **`save_settings`** validates and clamps every value: hold-to-talk
  0.5–10 s, silence, unload minutes, keep-audio days, at least one language
  (stored in the canonical order; the legacy `language` fallback is applied
  when reading), the Gujarati-only translate option cleared when Gujarati is
  off, the shortcut (1–3 keys).
- New command **`settings_rules() -> {limits, defaults}`**: slider ranges
  and the default settings ("Jarvis", the default shortcut…). The UI uses
  them instead of its own numbers and fallbacks.
- New command **`check_shortcut(keys) -> {ok, warning}`**: the key limit and
  the "a typing key alone" warning, used as you press keys.
- **Speakers:** each segment says whether its speaker is `renamable` (not
  "Me") and `automatic` (an engine label such as "Speaker 2" or "Others"),
  so the UI doesn't match those names itself; `rename_speaker` rejects what
  isn't renamable.
- **Meetings and tasks:** `list_meetings` returns meetings only (other kinds
  are internal); the backend rejects empty meeting titles and empty task
  descriptions; `reorder_tasks` takes the new order of open tasks and the
  backend keeps done tasks after them; `list_tasks` comes with the open-task
  count.
- **Voice training:** the backend rejects recordings under 8 s and stops at
  25 s; the passage to read comes from `voice_profile_info`.
- **Voice commands:** the phrases shown come from the backend
  (`settings.commands()`), not parsed in the UI.
- **Downloaded models:** each has a `kind` (speech, task_ai, voice_id,
  speakers, indic) so the UI doesn't look at file name endings.

## 5. Display text moves to the frontend

The backend sends data; the frontend words it.

| Now (backend text) | Becomes (data) |
|---|---|
| `LlmStatus.model` "Qwen3 4B (2.5 GB)", `.message` | `model_id`, `size_gb`, and the state flags already there |
| `engine-setup` step sentences ("Installing the speech engine") | `step` (python, engine, nvidia, indic, models, task_ai) + `pct` + `item` (a package or model id) |
| engine status "Downloading X… 42%" (`lib.rs`), `model-download` `what` | state downloading with `model` (an id), `done_mb`, `total_mb`; the engine sends a model id |
| Overlay notices "● Recording", "Press again to stop" | `session-notice` with `kind` (meeting_started, press_again_to_stop) |
| `WATCHED` call-app sentence | `watched_call_apps` returns the app list, `browsers`, `needs_pactl` |
| `ModelInfo.name` ("Speech model: Whisper small") | `kind` + `model_id`; the UI names it |

Kept as is: error messages; meeting titles the backend creates ("Recording ·
Oct 07, 17:00"), because they are stored data the user can rename; the
backend's whole-percent throttling of progress events (it limits traffic,
not presentation).

## What stays in the frontend

Rendering, input, view state, `lite.ts`, `updates.ts` (the update prompt),
`modelDownload.ts` (throttling the display), `toast`, `confirm`, `icons`,
formatting (`gb`, durations, dates), model names and purposes, language
names and links, and all wording.

## Order of work (one commit each)

1. Transcripts (§3): stored data is computed by the UI today.
2. Models (§1): fixes the Auto disagreement.
3. Setup (§2).
4. Rules (§4).
5. Display text (§5).

## Testing

- Rust tests for each moved piece, ported from the behaviour of the TS code:
  re-timing keeps unchanged words' times and spreads new ones; task quotes
  are found across lines, with a leading "Name:" and reworded endings; model
  fitting per hardware; setup plan sizes; each validation rule.
- `cargo test`, the engine tests, `npm run build`, `check-release.py`.
- Run the app after each step and drive it as in part 1: model lists match
  today's on this PC (except the Auto fix); editing a line keeps its timings;
  task underlines and "play from task" land where they did; Settings saves
  and rejects as listed; setup shows the same sizes.
- Final check: no `fitModel`, `retimeWords`, `taskOfWords`, `quoteStart` or
  `spreadWords` in `frontend/`; no user-facing sentences in backend events
  other than errors.
