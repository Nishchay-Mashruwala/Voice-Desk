# Voice Desk mobile — summary and tasks (Plan 4 design)

*Status: approved by the owner, 2026-10-16 ("move forward with tasks"), with the answers below.*

## Intent

The owner's list for 2026-10-15, item 2: "Summary and tasks: the phone writes
a summary and finds tasks, shown in the Tasks tab. First compare task-AI model
sizes on the PC."

As on the desktop, after a recording is turned into text, the phone does two things:
- writes a short summary;
- picks out **the owner's own tasks**: what someone asked him to do, and what he said he would do.

They appear on the recording's screen and in the Tasks tab. Everything runs
on the phone, offline, like the speech: the phone never uses the PC.

## Goals

- **After each recording** (after the text and the speakers):
  - a 2–4 sentence summary;
  - the owner's tasks, each with who asked, when it is due (as said) and the words it came from.
- **The recording's screen:** "Summary", and "Your tasks" with the same row actions as the Tasks tab.
- **The Tasks tab** (desktop's "My tasks", phone-sized):
  - open tasks, then "Show N completed";
  - tick done, edit the words and the due date, add, delete, copy;
  - drag to reorder;
  - "Where it was said" opens the recording and plays from the start of that line.
- **Settings → Processing:** "Find tasks" on/off (default on).
- **Storage:** the task model, with Download and Delete like the speech models.

## Non-goals

- Translation, reminders, calendar entries, sharing tasks to other apps (copying a task is in).
- Changing the desktop. Its prompt has the same weakness found here (see the findings); a separate change, if the owner wants it.

## Findings this design rests on (PC, 2026-10-15)

Qwen3 0.6B, 1.7B and 4B (Q4_K_M, the desktop's files) on 12 cases, 3 runs each:
- the desktop's three task tests;
- the two desktop meetings with speech, neither with a task for the owner;
- the David/Zira conversation;
- written cases like the phone's output: Hinglish in Devanagari and Gujarati with English, other people's tasks only, a long meeting in two parts, to-dos in Hinglish, a nickname.

Each ran with the desktop's exact prompt, chunking and JSON schema. Scripts and results: the session scratchpad's `taskai/`.

| | 0.6B | 1.7B | 4B |
|---|---|---|---|
| Desktop prompt: tasks found | 30/57 | 44/57 | 57/57 |
| Desktop prompt: runs fully right | 3/36 | 11/36 | 30/36 |
| Prompt without examples ("v2"): tasks found | 40/57 | 57/57 | 57/57 |
| v2 + quote check: other people's tasks let in | 5 | 5 | 2 |
| v2 + quote check: tasks nobody gave | 9 | 6 | 0 |
| v2 + quote check: runs fully right | 11/36 | 25/36 | 34/36 |
| Size of the model file | 0.4 GB | 1.1 GB | 2.5 GB |
| 30-min meeting on the M31 (speed test, 2026-10-12) | ~11 min | ~24 min | not measured (~2× 1.7B expected) |

- **The small models copy the prompt's example.** "Send the Q3 deck to Priya … by Friday" turned up in meetings where nobody said it; the desktop notes this for 1.7B too. A prompt with the same rules and no example sentences ("v2") stops it.
- **Other people's tasks:** "Rahul: I'll do the migration", "Priya, please update the slide". A check on each task's quote removes most of them, whatever the model. The task is kept only when the quoted line:
  - is the owner's own; or
  - is addressed to him: his name, a nickname, or "you" / आप / તું …;
  - and doesn't open with someone else's name.

  Tested on the stored answers, it lost no real task.
- **0.6B is poor** even then. The mobile spec's open check said: "If 0.6B is poor, use 1.7B on every phone (M31: ~24 min for that step)."

## Decisions

### The model *(the owner, 2026-10-16: "yes give choice")*
- **Qwen3 1.7B Q4_K_M on every phone:**
  - the desktop's pinned file (unsloth, commit `d7f544ee…`, SHA-256 checked);
  - 1.1 GB, downloaded when "Find tasks" is on;
  - about 1.3 GB of memory while it runs, after the speech models have been freed.
- **Qwen3 4B Q4_K_M as a choice** on phones with 8 GB or more (Android reports about 7.3 GiB for those):
  - Settings → Processing → "Task AI": "Faster" (1.7B, the default) / "More accurate" (4B);
  - the desktop's pinned file (unsloth, commit `22c9fc8a…`), 2.5 GB;
  - about twice as slow as 1.7B;
  - phones under 8 GB don't show the choice.

### The prompt and the check *(my call)*
- **The prompt:** the desktop's rules, roles and JSON schema, without the example sentences ("v2"; text in the scratchpad's `taskai/compare.py`).
- **Settings:** temperature 0.1, thinking off, at most 1,536 tokens per answer.
- **Who the owner is:** his name and other names, and "Lines labelled 'Me' were spoken by the user", as on the desktop.
- **The quote check:** as in the findings. A quote that isn't in the transcript is kept (it can't be judged).
- Then the desktop's clean-up: "Speaker :1" is snapped back to the real label, and "me"/"self" becomes "Self".

### Meeting or to-do list *(my call)*
- **To-do list:** when every line with a speaker is "Me" (the owner talking to himself), or when the recording has a single speaker and no voice is trained (the phone's owner recording alone). It uses the desktop's own-notes prompt: every to-do, and a one-sentence summary.
- **Meeting:** everything else, including recordings made without speaker detection.

### When no line is "Me" *(the owner, 2026-10-16: strict)*
Without a trained voice, with speaker detection off, and for every recording from before Plan 3, no line says who the owner is. Then only tasks addressed to him are kept: by name, a nickname or "you". His own "I'll send it" is missed. The recording's screen says "Train your voice so your own promises are found too."

### When it runs *(my call)*
- **Its own queue, after speech.** A recording is **done** once its text and speakers are: it can be read, fixed, processed again and compressed. Its tasks are a separate state: waiting, finding, found or failed (`meetings.tasksStatus`).
- **Speech goes first.** The tasks step runs only when no recording waits for speech (as upkeep does). It is saved part by part and gives way between parts:
  - to a recording that starts;
  - to a recording waiting for its text;
  - to the battery or heat rules.

  The step continues from the next part afterwards.
- **The screens:**
  - its line under the mic: "Finding tasks in “Weekly review” · part 2 of 3";
  - the recording's screen: "Finding tasks…" while waiting or running.
- **The rules of speech still apply:** one job at a time; it waits for charging when the battery is under 20% (and the setting is on) and while the phone is hot; it starts after the speech models are freed.
- **Long transcripts:** the desktop's chunking and merge pass, but parts are sized **by tokens**:
  - about 3,000 tokens of transcript each, counted with the model's own tokenizer, cut at line ends, the last ~400 tokens carried over;
  - a line longer than a part is cut at word ends.

  Measured with Qwen3's tokenizer, Gujarati takes about 0.57 tokens per byte against 0.25–0.33 for English. The desktop's 12,000-byte parts would overflow the 8,192-token context.
- **Time:** the speed book learns this step too, per language mix. The estimate before a recording is processed includes it.
  - A 30-min English meeting on the M31 with 1.7B: about 24 min (speed test).
  - The same mostly in Gujarati is 2–3× the tokens: perhaps 50–70 min (estimate, not measured).
- **Older recordings** don't get tasks by themselves (hours on the M31).
- **"Find tasks"** on any finished recording runs only this step. Use it on an old recording, or after fixing words or moving lines to "Me".
- **If the step fails:** the text and speakers stay, and the screen shows "Couldn't find tasks." with Try again, which reruns only this step.
- **Process again** and **Find tasks** run it again *(my call)*:
  - **Replaced:** the AI's tasks he hasn't touched.
  - **Kept:** the ones he added, edited or ticked. Reordering doesn't count.
  - **Not brought back:** a new AI task whose quote matches a kept one, or one he deleted, is dropped. Deleted AI tasks are kept hidden for this.

### How it runs on the phone *(left to the builder, after a spike on the M31)*
llama.cpp, built with the NDK 28.2 and CMake 4.1.2 already installed, for arm64. Either:
- the **`llama-server`** program packed as one of the app's native libraries and run on 127.0.0.1, exactly as the desktop does (JSON schema, chat template); or
- llama.cpp linked through **Dart FFI**.

The spike decides between them by:
- whether Android keeps a child process alive under the foreground service;
- the memory each way;
- the build effort.

Whichever is used: 4 threads, context 8,192, and the model unloaded after the job (memory back to the phone as for speech).

### Data
- `tasks`: as the desktop's table, plus where the quote starts:
  - id, recording (deleted with it), description, assigned by, due, quote;
  - `quoteMs`: where the quoted line starts;
  - done, position, `edited` (touched by the owner), `deleted` (an AI task he removed: hidden, kept so it isn't found again), created at.
- `meetings.tasksStatus` (none, waiting, finding, found, failed) and `meetings.tasksPart` (where a paused step continues).
- `meetings.summary` (exists).
- Settings key `find_tasks` (default on).
- The model catalogue gets `ModelId.taskAi` "Task AI".

## Errors

| Problem | Behaviour |
|---|---|
| The task model isn't downloaded | Recordings get text and speakers; the tasks step waits for the model ("Downloading the task model…"), like a missing speech model |
| The step fails or the phone kills it | Text and speakers kept; "Couldn't find tasks." with Try again |
| Invalid JSON from the model | Tried once more with another seed; then as a failure |
| No speech | Summary "No speech was detected.", no tasks (desktop) |

## Testing

- **Ported desktop tests:** prompts, chunking, the merge, the JSON parsing and the label snapping.
- **New unit tests:** the quote check (the cases above), to-do list vs meeting, Process again keeping edited tasks, and the Tasks tab (tick, edit, add, delete, reorder, where it was said).
- **Real model on the PC** (behind an environment variable): the 12 cases with 1.7B. It must stay at or above 57/57 tasks found and at most 5 of other people's tasks in 36 runs. New cases for this design:
  - a long mostly-Gujarati meeting (several parts by tokens);
  - recordings with no "Me" lines;
  - a single-speaker voice note without a trained voice.
- **On the M31:** a 30-min recording's tasks step: time and memory; the step on battery and on charge.

## The owner's answers (2026-10-16)

1. Task model: "yes give choice". 1.7B on every phone, and 4B as "More accurate" on phones with 8 GB or more.
2. No "Me" lines: strict, only tasks addressed to him, with the hint to train his voice.
