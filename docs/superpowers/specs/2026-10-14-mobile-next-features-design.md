# Voice Desk mobile: languages, speakers and everyday tools — design

Date: 2026-10-14 · Status: approved by the owner 2026-10-14 ("start making"); Plan 2b written: [../plans/2026-10-14-mobile-plan-2b-better-speech.md](../plans/2026-10-14-mobile-plan-2b-better-speech.md)

Builds on [2026-10-12-mobile-app-design.md](2026-10-12-mobile-app-design.md)
(the mobile spec; Plans 1 and 2a are built). This document covers the nine
features the owner asked to start on 2026-10-14, plus what they depend on.
Calls marked *(my call)* were made by the designer, not the owner, and are open
to change.

## Intent

The phone app records and turns speech into English text. The owner's
meetings are "mostly Gujarati and English and sometimes Hindi", "mostly 2
people talk, rarely more, and it is mostly the same people each week,
sometimes different". To be useful for those meetings the phone has to:

- write Gujarati/Hindi as spoken, with English words mixed in;
- say who said what;
- let the owner fix what it got wrong.

It also needs the everyday tools the PC app has: copy, storage and setup.

The desktop app is the **reference for behaviour and wording only**. Owner,
verbatim: "don't use anything from the desktop for running the mobile, mobile
will run on its own without being connected to PC, use desktop as reference
for what to do in mobile". The phone downloads its own models from the
internet and never needs the PC.

## Goals

1. **Hindi/Gujarati written as spoken, with English mixed in.** Gujarati in
   Gujarati script, Hindi in Devanagari, English words in English, even in
   mid-sentence ("હા એનું background તો Scottish છે").
2. **Who said what.**
   - Every line carries a speaker; the owner's own lines are "Me".
   - Rename a speaker, and the phone remembers that voice in later recordings.
   - Move a single line to the right speaker.
3. **"Other names people call you"** (nicknames).
4. **Fix the words in a transcript line.**
5. **Keep recordings for N days** (audio deleted, text kept), with audio
   saved as compressed **FLAC**.
6. **Copy / share a transcript.**
7. **A Storage page**: sizes of recordings and models, delete.
8. **An "Accuracy" setting**: faster or more accurate speech model.
9. **First-start setup**: welcome → permissions → name → download.
10. *(my call)* **A "Licences & credits" page.** The owner asked whether the
    app needs a licence or credit. Credit is required (see Licences below), so
    this page is added.

### Accuracy, standing goal (owner, 2026-10-13)
"It shouldn't make any mistakes like fine to by." Every change to speech
recognition is measured on the owner's own recordings before and after (see
Testing).

## Non-goals

- Translation of Hindi/Gujarati to English. The mobile spec keeps
  translation out of version 1.
- A bigger Hindi/Gujarati model than the ready-made phone ones (owner,
  2026-10-14: option (a)).
- Writing the owner's name in English letters inside Gujarati/Hindi
  sentences (owner, 2026-10-14: keep the PC's behaviour, B3).
- ~~Re-processing old recordings~~ — **added by the owner (2026-10-14): see
  B9 "Process again"**. Settings changes still apply only to new recordings
  by themselves.
- Live dictation, voice commands, "only my voice can give commands". These
  are desktop features with no use in the phone app.
- Syncing anything with the PC.
- The Tasks tab and the task AI (still Plan 4) and calls (Plan 5). Nicknames
  will feed the task AI's prompt then, as on the desktop.

## Anti-goals (would make it a failure even if it works)

- Anything that needs the PC to run, or reads files from it.
- A correct word changed into a wrong one by the "fixing" rules. The owner
  would "rather miss fixing my name than change a right word" (2026-10-13).
- Lost audio: a recording's audio deleted before it was fully processed, or a
  FLAC conversion that loses samples.
- Recording that stutters or stops because processing is running.
- Voice prints or recordings leaving the phone.

## Constraints

- Standalone phone (above). The models come from public URLs, pinned with
  size and SHA-256, through the existing downloader (resume, other addresses,
  Try again).
- **Target phones** (mobile spec): Android with 4 GB RAM or more. The test
  phone is the owner's Galaxy M31: 4 fast cores and no ARM dot-product
  instructions, so it is slow. Every feature must run on it, slower is
  allowed, and the app shows the time it will take.
- **Unchanged rules from Plan 2a:**
  - processing waits when the battery is under 20% and not charging (owner),
    or when the phone is hot;
  - one job at a time;
  - live processing during recording on 2 threads, the rest after Stop on 4.
- **Unchanged look and layout:** portrait only; the PC look (dark theme,
  purple accent); screens decide nothing (backend package `mobile/backend`,
  UI in `mobile/frontend`).
- The owner commits and pushes; the builder never commits unless asked.

## Findings this design rests on (measured 2026-10-14 on the PC, sherpa-onnx 1.13.8)

1. **"fine" → "by" is a cut-off start, not a bad model.**
   - In the owner's recording 17 (copied from the phone), the phrase was cut
     too tight.
   - A cut starting at the stored line start (28.68 s) hears nothing with
     either decoder.
   - Starting 0.3–0.5 s earlier, both the current model and the transducer
     model write "fine".
   - **So each phrase is padded before recognition** (lead 1 in the mobile
     spec, now confirmed).
2. **The same Parakeet 110M model has a second variant with a transducer
   (TDT) decoder.** File: `sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8`,
   108,035,095 B, SHA-256 `f628312e9fdf8686374cb01a69425c41732529d540860311f16f37cbc32cfe9b`.
   Inside are:
   - `encoder.int8.onnx` 131,113,202 B
   - `decoder.int8.onnx` 3,955,863 B
   - `joiner.int8.onnx` 1,411,403 B
   - `tokens.txt` 9,953 B

   Compared with the CTC variant the app uses now:
   - **Same speed** on the PC: 0.049× real time, against 0.044× for CTC.
   - **More accurate on the owner's recording 2:** "Let's stop it from the
     notification bar". The CTC variant wrote "Letter always stop it…".
   - **It gives a confidence for every token** (`ys_log_probs`). The CTC
     variant gives none, so `ys_log_probs` is empty.
   - The Dart package's `OfflineRecognizerResult` drops that field, but the
     native result JSON carries it. Checked with the same 1.13.8 release in
     Python: keys `text, timestamps, durations, tokens, ys_log_probs, words…`.
     The phone reads it by calling
     `SherpaOnnxBindings.getOfflineStreamResultAsJson` itself and parsing
     the JSON, as the package does internally (`offline_recognizer.dart`,
     around line 400). *(builder: confirm on Android in the first task.)*
   - The confidence is low exactly where the model is guessing, as in the
     name: "Neste" scored 0.43 / 0.16.

   The desktop's English/Gujarati mixing depends on word confidences, so the
   phone switches to this variant.
3. **The Hindi/Gujarati models for phones exist ready-made.**
   [parismitaglobalsolutions/indicconformer-sherpa-onnx](https://huggingface.co/parismitaglobalsolutions/indicconformer-sherpa-onnx)
   publishes AI4Bharat's per-language IndicConformer Large (120M, hybrid
   CTC/RNNT; only the CTC head was exported) as int8 files:
   - `gu/model.int8.onnx` 197,595,461 B
   - `hi/model.int8.onnx` 197,595,593 B
   - a shared root `tokens.txt`

   Details:
   - They load in sherpa-onnx as NeMo CTC (`OfflineNemoEncDecCtcModelConfig`).
   - The language mask is built into each file, so plain greedy decoding is
     enough.
   - Licence: Apache-2.0 for the export, MIT for AI4Bharat's model.
   - **Not known yet:** their accuracy on the owner's speech, and their
     speed on the M31.
   - **Owner's decision (2026-10-14):** these models are used **even if they
     turn out somewhat worse than the PC**, since they are smaller (120M vs
     the desktop's 600M) and CTC only. They are still measured on the test
     set, and the mixing is tuned to get the best from them. A bigger Indian
     model is not part of this work.

   This replaces the mobile spec's earlier plan to port `indic.py` to
   onnxruntime and have the owner publish a 1 GB model. Being CTC, these
   models give no confidence through sherpa-onnx (see "Hindi or Gujarati"
   below).
4. **Speakers:** sherpa-onnx's Dart package has `OfflineSpeakerDiarization`
   (pyannote segmentation + a voice model + clustering),
   `SpeakerEmbeddingExtractor` and `SpeakerEmbeddingManager`. Speed test on
   the M31 (2026-10-12), pyannote segmentation 3.0 + CAM++ on 4 threads:
   **0.73× real time, ~22 min for a 30-min meeting** if run after Stop on the
   whole recording.

## The order of work

**Owner, 2026-10-14 (after Plan 2b):** next, in one plan (2c-a): fix a line's
words (B1), other names (B3), the downloads list with green "Downloaded" tags
(B6, models part), and Process again (B9). Speakers (Part C) in a later plan.
The rest of Part B (FLAC, keep N days, copy/share, first-start setup,
Licences & credits, the recordings part of Storage) after those.

The first proposal (my call):

Each plan ends with a working app, tested on the M31, like Plans 1 and 2a.

- **Plan 2b — Better speech:**
  - English on the transducer variant, with padding;
  - Hindi/Gujarati mixed with English;
  - the Accuracy setting;
  - the Languages settings.
- **Plan 2c — Everyday tools:**
  - fix a line's words;
  - copy/share;
  - nicknames;
  - FLAC;
  - keep recordings for N days;
  - the Storage page;
  - first-start setup;
  - Licences & credits.
- **Plan 3 — Speakers:**
  - who said what, with "Me" from voice training;
  - rename and remember;
  - move a line;
  - People in Settings.

Then Plan 4 (summary, tasks, Tasks tab) and Plan 5 (calls), as in the mobile
spec. When this design is approved, the mobile spec's Plans list and Steps
are updated to match.

---

## Part A — Speech (Plan 2b)

### A1. English: the transducer variant, padded phrases
- The English model becomes the Parakeet 110M transducer variant (Finding 2).
  It replaces the CTC files.
  - It is downloaded like the current model: tar.bz2, extracted in an
    isolate, hashes checked.
  - The old `parakeet` folder is deleted once the new one is ready.
  - *(my call)* On the owner's phone this means a one-time 108 MB download
    after the update. Recordings still waiting are processed once it is
    there; the Record screen's model banner says so.
- Word timings come from the transducer's token timestamps, as now from
  CTC's. The **confidence of a word** is computed from its tokens'
  probabilities, so a word's weakest token decides it. *(builder's exact
  rule.)*
- **Padding (as built, Plan 2b, measured on the owner's recordings):**
  - Each phrase is first read as voice activity cut it.
  - Only when the English reader is unsure (mean word confidence under
    0.8, or it heard nothing) is the phrase read again with 0.3 s of audio
    before it. The surer of the two readings is kept.
  - Padding every phrase (0.3 s before and after, the first idea) fixed
    "fine", but it turned "Good, good" into "Dave" and dropped words.
  - The padding never goes before the phrase before, or before the audio
    the job started from. Word times stay in recording time.
  - The Indian models always read the phrase with the 0.3 s before it.
  - The English transducer uses modified beam search (4 paths). It kept
    repeated words that greedy search dropped, at the same speed.
- **Live processing still works:**
  - The audio before a phrase comes from the last 25 s kept in memory.
  - What counts as settled is held back by 0.3 s more, so a job resumed
    there still has the audio before its first phrase.
- Vocabulary and Leave out are unchanged. Two additions:
  - nicknames join the vocabulary entries (Part B3);
  - *(my call)* the sound-alike fix may also require the heard word's
    confidence to be below a level (e.g. 0.6). That makes it even more
    cautious: "Neste" (0.16) can become the name, while a word heard with
    high confidence is never touched. The builder sets the level on the test
    set.

### A2. Languages
**Settings → Speech → "Languages you speak"** (desktop wording):
- Chips: English · हिन्दी Hindi · ગુજરાતી Gujarati.
  - At least one stays on.
  - Hint: "Each phrase is recognised in whichever of these you speak — mix
    them freely."
  - Default: English only, so nothing changes until the owner ticks more.
- **"Hindi or Gujarati — which do you speak more?"** appears only when both
  are ticked. Default Gujarati (desktop default).
  - Hint: "Written as spoken, Hindi and Gujarati are told apart by sound,
    and this one wins when it's unclear."
- Ticking a language downloads its model after a confirmation:
  - "Gujarati model · 198 MB. Wi-Fi recommended."
  - Progress shows inline; it resumes after interruption.
  - *(my call)* Unticking keeps the file. The Storage page shows it as "Not
    used by your settings" with Delete.
- Changes apply to recordings made from then on. A recording records the
  languages it was processed with, so a job resumed after a restart keeps
  using them.

**Model files** (Finding 3):
- Gujarati: `gu/model.int8.onnx`; Hindi: `hi/model.int8.onnx`; plus the
  shared `tokens.txt`.
- Downloaded from Hugging Face at a **pinned commit** (`resolve/<commit>/…`,
  not `main`), with the sizes and SHA-256 recorded in the catalogue.
- If that repository ever disappears, the fallback is to publish the same
  files on the project's GitHub releases. That is a later task for the
  owner, not needed now.

### A3. How a phrase is written (port of the desktop's mixed mode)
Per phrase (padded, at most 20 s, as voice activity already limits):

1. **English only ticked:** Parakeet's text, as today.
2. **An Indian language ticked:**
   - Parakeet writes the phrase in English, with word times and confidences.
   - The Indian-language model writes it in its script.
   - The two are combined by the desktop's rules, ported to Dart from:
     - `desktop/backend/engine/transcriber.py` `_combine` (lines 491–516);
     - `desktop/backend/engine/mixed.py` `merge` (lines 483–530), with its
       sound classes, similarity, word-by-word replacement, whole-sentence
       step, gap filling, the "never replaced" lists, and Gujarati endings
       kept attached ("Cityથી").
   - The English word list is the app's bundled `english-words.txt`, which
     is already on the phone.
   - Adaptations:
     - Whisper's word probabilities become Parakeet's word confidences.
       Thresholds were tuned for Whisper; the builder re-tunes them on the
       test set and keeps the desktop's values where results agree.
     - The desktop's "Whisper's language check says English" (used when
       IndicConformer is silent for 2 s or more) has no Parakeet
       equivalent. Instead the phrase counts as English when at least 80% of
       Parakeet's words are dictionary words with mean confidence ≥ 0.85
       *(my call, tunable)*.
     - "At least 70% of a chunk's words English → write it exactly as
       English" stays, per phrase.
3. **English unticked** (only Hindi and/or Gujarati): the Indian-language
   text only, no mixing.

**Hindi or Gujarati, when both are ticked.**
- The desktop picks by IndicConformer's per-letter scores: the preferred
  language wins unless the other fits better by more than 0.08 mean log-prob
  per letter. Through sherpa-onnx the phone's CTC models give no scores
  (Finding 3).
- **Requirement:** a Hindi phrase is written in Devanagari and a Gujarati
  phrase in Gujarati, checked on the test set. When it's unclear, the
  preferred language wins.
- **As built (Plan 2b): marker words.**
  - The preferred model reads each phrase.
  - Only when its reading holds more words that only the other language
    uses (है, था, क्या, मुझे… / છે, હતો, શું, તમે…) does the other model
    read it too.
  - The other reading is kept only when it holds more of its own
    language's marker words.
  - sherpa-onnx gives no CTC scores, not even in its newest code, which
    ruled out option (b). Options (a) and (c) need another library.
  - To be checked on the owner's Hindi clip.

**Live and after Stop:**
- During recording, as now: per finished 1-minute piece, at 2 threads.
- With an Indian language on, the M31 may fall behind live; the backlog
  finishes after Stop at 4 threads (mobile spec).
- *(my estimate, to be measured)* English + Gujarati is roughly twice the
  work of English alone.

**Memory:** Parakeet and the Indian model(s) are loaded together during a
job. The peak stays under the mobile spec's ~1.2 GB budget; this is measured
on the M31. If both Indian models plus Parakeet exceed it, the second Indian
model is loaded only for phrases that need it.

### A4. Accuracy setting
**Settings → Speech → "Accuracy (speech model)"**, radio cards as on the
desktop. Each card shows its download size, "Downloaded" or "Downloads X MB",
and "about N min after a 30-min recording on this phone". That figure comes
from this phone's measured speed, or the speed-test figures until measured.

| Choice | English model | Download |
|---|---|---|
| **Auto — picks for this phone** (default) | Faster on phones with under 6 GB RAM or no ARM dot-product (the M31); More accurate otherwise | — |
| **Faster** | Parakeet 110M transducer int8 (A1) | 108 MB |
| **More accurate** | Parakeet TDT 0.6B v2 int8 (`sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2`, sherpa-onnx `asr-models` release, 482,468,385 B) | 482 MB |

- Only the English reader changes. The Indian models have one size each.
- *(my estimate)* The 0.6B model is about 5× the work. On the M31 it will
  not keep up live, so most of a meeting is processed after Stop. The card's
  time says so.
- Changing the choice downloads the model when needed (with confirmation)
  and applies to new recordings.
- **Lead for the builder:**
  - The transducer models also allow sherpa-onnx's hotwords with modified
    beam search. If they work with these NeMo models on the phone, the
    name, nicknames and vocabulary are passed as hotwords too, as Whisper's
    hint on the desktop. The after-recognition fix stays.
  - Measure on the test set first. Adopt only if it fixes names without
    changing right words.

---

## Part B — Everyday tools (Plan 2c)

### B1. Fix the words in a line
- On a finished recording's screen, **long-press a line** to open a small
  menu *(my call; tapping a word still plays from it)*:
  - "Fix the words"
  - "Copy this line"
  - in Plan 3, "Said by…"
- "Fix the words" opens a text box with the line's text and **Save** /
  **Cancel**. Save is disabled while the box is empty.
  - Errors as on the desktop: "A line can't be empty", "That line is no
    longer there".
- Only that line's text and word timings change; speaker, start and end
  stay.
- **Word timings: port `retime_words`** (desktop
  `desktop/backend/core/src/transcript.rs`, lines 169–226, tests at
  328–345):
  - longest-common-subsequence match ignoring case and punctuation;
  - unchanged words keep their times;
  - new or changed runs share the time between their unchanged neighbours
    evenly.
- Leave out and vocabulary are **not** re-applied to an edited line. Your
  words are final. *(my call)*
- Lines can be edited only when the recording's status is done or failed,
  never while it is recording or processing. Processing rewrites lines, and
  an edit must not be overwritten. *(my call)*

### B2. Copy / share a transcript
- The recording's screen gets a **Share** button in its header. It opens a
  menu:
  - **"Copy transcript"**: toast "Copied to clipboard".
  - **"Share…"**: Android's share sheet, as plain text.

  Both are available when the recording has lines. The desktop has no
  transcript copy; this is new.
- **Format** *(my call; from the desktop's transcript format for the task
  AI, `llm.rs` `format_transcript`)*:
  ```
  Weekly review
  14 Oct 2026, 14:05 · 32 min

  [00:02] Me: Good morning, shall we start?
  [00:05] Kiran: Yes. હા, આજે બે વાત છે.
  ```
  - A new `[mm:ss]` line each time the speaker changes.
  - Lines of the same speaker are joined with a space.
  - Times are `[h:mm:ss]` past an hour.
  - Before Plan 3 (no speakers yet), each line is `[mm:ss] text`.
- "Copy this line" (B1) copies just that line's text.

### B3. Other names people call you
- **Settings → You and your words**, under "Your name":
  - "Other names people call you"
  - Hint: "Nicknames or spellings, comma separated." (desktop wording)
- Stored like the name (settings key, plain string, split on commas and
  newlines, trimmed, duplicates ignoring case dropped).
- **Used for:** fixing words exactly as the name is. Each nickname and its
  parts join the vocabulary entries, under the same cautious rules
  (2026-10-13). In Plan 4 they also go into the task AI prompt, as on the
  desktop ("People may also call them: …").
- **Not used to decide who is "Me".** The desktop doesn't either.
- **Inside Gujarati or Hindi speech** (owner, 2026-10-14: "keep PC
  behaviour"), the name and nicknames are written in that language's script
  as the Indian model hears them, e.g. "નિશ્ચય". The name, nickname and
  vocabulary fixes apply to English words only (Parakeet's words and the
  English words kept by the mixing), as on the desktop.
- Applies to new transcripts.

### B4. FLAC
- **When:** after a recording's processing ends, done or failed (as on the
  desktop). Steps:
  1. The 1-minute WAV pieces are joined into one `audio.flac` in the
     recording's folder.
  2. The FLAC is decoded back and compared sample for sample.
  3. Only if identical are the pieces deleted. Otherwise the pieces are
     kept and the conversion is tried again at the next app start.
  4. `audioPath` points to the FLAC.
- At app start, any finished recording that still has pieces is converted
  (the owner's existing recordings included). Recordings that are recording
  or queued are skipped.
- **Encoding:** lossless FLAC, 16 kHz mono 16-bit, with a **seek table**
  (e.g. a point every 10 s) so playback seeks exactly and quickly. *(my
  call)*
  - Expected size ~50–60% of the WAV for speech.
  - A 30-min meeting: ~57 MB WAV → ~30 MB FLAC *(estimate)*.
- **Must work on the phone without FFmpeg** (ffmpeg-kit is retired) and
  without the PC. Left to the builder: a small Dart FLAC encoder/decoder
  (fixed predictors + Rice coding; testable on the PC), or Android's
  built-in MediaCodec FLAC encoder via a platform channel.
- **Everything that reads audio reads either form:**
  - the player (just_audio/ExoPlayer plays FLAC);
  - Retry and later steps (speakers in Plan 3) through `pcm_reader`;
  - `pieces()` in the repository returns the FLAC when present.
- **Retry on a failed recording works from the FLAC.** A recording that was
  never fully processed is never converted while its job is still to run.
  *(my call)*

### B5. Keep recordings for N days
- **Settings → Storage → "Keep recordings for":**
  - Choices: Forever · 7 days · 30 days · 90 days · 1 year.
  - Default **30 days** (desktop default).
  - Hint: "Older recordings' audio is deleted; their text stays."
  - *(my call: a choice list instead of the desktop's number box, which is
    awkward on a phone.)*
- **When:** at app start and after each processing job finishes. *(The
  desktop runs at start only; a phone app may stay open for days.)*
- **What:** recordings whose start is older than N days, **and whose
  processing has finished** (status done). Failed, queued, processing and
  recording ones are never touched, so Retry still has its audio.
  - Their audio files are deleted (FLAC or pieces) and `audioPath` is
    cleared.
  - Title, transcript, word timings, speakers, summary and tasks stay.
- **Afterwards:**
  - the recording's screen hides the player and says "The audio for this
    recording is no longer available." (desktop wording);
  - tapping words does nothing;
  - its tile shows "Text only".
- Shortening the period asks first: "Delete the audio of N recordings older
  than X now? Their text stays." *(my call)*

### B6. Storage page
**Settings → Storage** opens a page *(my call; the desktop puts this under
Settings → Advanced)*:

- **"On this phone"**: Recordings X · Models X · App data X (database,
  transcripts, voice prints) · Free space X.
- **Recordings**:
  - the total audio size and count, and the "Keep recordings for" choice
    (B5);
  - the recordings with audio, largest first, each with its size and
    **Delete** (deletes the whole recording, with the same confirm as on its
    screen; Undo as on the Record screen).
- **Downloaded models** (desktop's list; owner, 2026-10-14: "list of
  everything downloaded … option to delete them and download, and make
  models' 'Downloaded' a green tag"):
  - Every model the app can download is listed: both English models,
    Gujarati, Hindi, voice activity, and later the speaker models. The shared
    Hindi/Gujarati tokens are counted with those two, not listed alone.
  - On the phone: a **green "Downloaded" tag** and **Delete**.
  - Not on the phone: **Download (X MB)**; while downloading, its progress;
    after a failure, why, with Try again.
  - The "Downloaded" labels in Settings → Speech's Accuracy rows become the
    same green tag.
  - Each row shows name, size and a badge "In use" or "Not used by your
    settings", plus **Delete**.
  - Names: "English speech model (Faster)", "English speech model (More
    accurate)", "Gujarati model", "Hindi model", "Voice activity", and in
    Plan 3 "Speaker detection", "Voice ID".
  - Confirm: "Delete <name>?" with "Frees X. If a later setting needs it, it
    downloads again by itself." For one in use: "Frees X, but your current
    settings use it. It downloads again before the next recording is
    processed." (desktop wording, phone-adapted)
  - Toast "Deleted — X freed".
  - A model can't be deleted while recording or processing: "It's in use
    right now — try again when processing has finished".
- The current Settings card "English speech model · 105 MB" moves:
  - its download state to Settings → Speech;
  - its Delete to this page.

### B7. First-start setup
Shown once, full screen, before the tabs, the first time the app opens (a
`setup_done` setting). *(my call)* On the owner's phone it shows once after
the update, with the fields filled in and models marked "Downloaded".

Steps, with Back and Next:
1. **Welcome:** the orb and "Speak, and it writes." with "Voice Desk records
   your meetings and turns them into text — all on this phone, even
   offline." Button **Get started**.
2. **Permissions:**
   - Microphone: "to record".
   - Notifications: "to show and stop a recording".
   - Unrestricted battery: "so Android doesn't stop a long recording".

   Each has an explanation and an **Allow** button, with the same checks
   and wording as Settings → Permissions. Next is always enabled; what is
   refused is asked again when needed.
3. **About you:**
   - "Your name" (placeholder "e.g. Nishchay"; hint "How people say your
     name in meetings.");
   - "Other names people call you";
   - the Languages chips (A2) and "which do you speak more".

   The name is optional, as on the desktop, where it is only nagged about.
4. **Your voice** (Plan 3, optional): the voice training (C2) or **Skip**.
5. **Download:**
   - Lists what this phone needs for the choices made: English speech model
     X MB, Gujarati model 198 MB, voice activity 0.6 MB, and in Plan 3
     speaker detection ~37 MB, with the total.
   - "Wi-Fi recommended. If it's interrupted, it continues where it
     stopped."
   - **Download (X MB)**, then progress.
   - "Use the app while it downloads": the download continues and the
     Record screen's banner shows it.
   - When done: "Voice Desk is ready — it works offline from now on."

### B9. Process again (owner, 2026-10-14)
"Process it again, so if any words were misheard they might be understood
properly." *(Design: my call, agreed in chat.)*
- **The honest part:** the same audio with the same settings gives the same
  words. A second pass helps only when something differs. The dialog says so
  and lets the owner choose this run's **accuracy** and **languages**. The
  current name, other names, vocabulary and Leave out always apply.
- A **"Process again"** button on a finished or failed recording's screen
  opens it:
  - title: 'Process "Weekly review" again?';
  - the Faster / More accurate choice, pre-set to More accurate, and the
    language chips, pre-set to the recording's own;
  - "Your fixes to its lines will be replaced.";
  - Cancel / Process again.
- The recording keeps the new setup, and its job runs like any other: it
  waits for missing models (the download banner offers them), charge and
  heat.
- **The old text stays** on screen until the new text is complete, then
  replaces it in one step. A failure keeps the old text; Try again continues
  the new run.
- Not while recording or processing.

### B8. Licences & credits
**Settings → About → "Licences & credits"**:
- A short credits list for the models and the word list, each with its
  licence name and link.
- Flutter's licence page for everything else. The model licence texts are
  added to it with `LicenseRegistry.addLicense`, so all texts are in one
  place.

Credits:

| What | Licence | Credit text |
|---|---|---|
| Parakeet TDT-CTC 110M and Parakeet TDT 0.6B v2, by NVIDIA | CC-BY-4.0 | "Speech model by NVIDIA (Parakeet), CC BY 4.0; converted to ONNX int8 by the sherpa-onnx project." |
| IndicConformer, by AI4Bharat | MIT | copyright notice + MIT text |
| Phone versions of IndicConformer, by Parismita Global Solutions | Apache-2.0 | licence text |
| Silero VAD | MIT | copyright notice + MIT text |
| pyannote segmentation 3.0 (Plan 3) | MIT | copyright notice + MIT text |
| CAM++ voice model, 3D-Speaker (Plan 3) | Apache-2.0 | licence text |
| sherpa-onnx | Apache-2.0 | licence text |
| English word list, from the en_US Hunspell dictionary (SCOWL size 60, wordlist.aspell.net) | SCOWL notice | its copyright notice |

Not legal advice. Before the app is given or sold to others, a quick
check by a lawyer is wise.

---

## Part C — Speakers (Plan 3)

### C1. Who said what
- **Settings → Speech → "Speaker detection"** (mobile spec), on by default.
- After speech to text, every line gets a speaker:
  - **"Me"**: the owner's lines, if a voice is trained (C2).
  - A **remembered person's name**, if their voice matches (C4).
  - Otherwise **"Person 1", "Person 2"…**, in order of first appearance.
    *(This is the wording played back to the owner. The desktop says
    "Speaker 1".)*
- **Tuned for small groups** (owner: mostly 2, rarely more):
  - no fixed number of speakers;
  - clustering settings chosen on two-person test recordings;
  - three or four people must still come apart.
- **Desktop clean-up rules ported** (`desktop/backend/engine/meeting.py`
  lines 25–107, `speakers.py` 173–186):
  - speakers with under 1.5 s of speech in total merge into the nearest
    one;
  - turns under 0.25 s are dropped;
  - the same speaker resuming within 1.0 s stays one turn;
  - lines are split where the speaker changes, word by word;
  - one stray word between two of the same speaker's words stays with them.
- **Speed (owner's priority: short wait after a meeting):**
  - The whole-recording diarizer after Stop costs ~22 min for 30 min on the
    M31 (Finding 4). That is too long.
  - **Requirement:** the speaker work is done during the recording as far
    as possible. After Stop only the final grouping, matching and labelling
    remain, plus the last minute. The target is a few minutes for a 30-min
    meeting on the M31, measured and shown in the estimate.
  - **Approach, left to the builder (measure on the M31 and on two-person
    test recordings):**
    - (a) one voice print (CAM++) per phrase, already cut by voice
      activity, computed live; long phrases (over ~3 s) are cut into
      ~1.5 s windows so a change of speaker inside them is found; after
      Stop, everything is clustered;
    - (b) the sherpa-onnx diarizer run live per 1-minute piece, with its
      local speakers linked across pieces by their voice prints after Stop.

    (a) is expected to be several times cheaper. Choose the cheaper one
    that keeps the two speakers apart on the test set.
- Lines during recording show no speaker. Speakers appear after Stop, when
  this step finishes.
- The recording's progress shows the step: "Processing · finding speakers
  60%" *(wording: builder, in the existing style)*.
- A failed speaker step keeps the text. Retry reruns only the speaker step
  (mobile spec rule).

### C2. "Me": voice training
**Settings → You and your words → "Your voice"**. Desktop flow, adapted
(the phone has no voice commands):
- Intro: "Read a short passage (about 15 seconds) so Voice Desk can tell
  your lines from everyone else's."
- Passage: "The quick brown fox jumps over the lazy dog. I'm teaching Voice
  Desk what my voice sounds like, so it can tell my lines from everyone
  else's. Tomorrow I will send the report, review the design, and call the
  team at three."
- The screen says "Read this aloud in your normal voice:" and shows a level
  bar and a seconds counter.
  - The button reads "Keep reading…" (disabled) until 8 s, then "Done".
  - Recording stops by itself at 25 s.
- At least 6 s of actual speech is needed: "Only Ns of speech was heard.
  Please read the text aloud for about 15 seconds."
- Badges: "Not trained yet" / "Voice saved <date>". Buttons: "Train my
  voice" / "Re-train" / "Forget my voice".
  - Forget confirms: "Forget your voice?" / "Voice Desk deletes what it
    learned about your voice. Until you train it again, your lines show as
    Person 1, 2…" / "Forget".
- **Voice print:**
  - computed from the speech in ~3 s windows (1.5 s step), averaged and
    normalised;
  - stored in the database;
  - the training audio is deleted.
- *(my call)* **The same voice model is used for "Me" and for remembered
  people**, so there is one model, one download and one kind of score. The
  desktop uses two different models.
- **"Me" is the speaker group whose voice print best matches**, above a
  threshold, at most one group. The desktop uses 0.30 for its model; for
  CAM++ the builder sets it on the test set.
- Without a trained voice there is no "Me". A one-line hint on a finished
  recording's screen offers "Train your voice so your lines show as Me".
  *(my call)*
- The speech recognisers ignore Me and the speakers; nothing else changes.

### C3. Rename a speaker
- On a finished recording, tap a speaker's name on any line, except "Me".
  A sheet opens:
  - "Rename **Person 1** to", with a box "Their name". It is empty for
    automatic names and filled for real names.
  - A tick box, ticked by default: **"Recognise this voice in future
    recordings"**, with "Saved on this phone only".
  - **Rename** / **Cancel**.
- It renames every line with that speaker in this recording.
- Errors (desktop): "Your own lines can't be renamed"; an empty name or
  "Me": "Type a name".
- Toast: "Renamed — <name>'s voice will be recognised in future recordings"
  or "Renamed to <name>".
- Renaming to a name already remembered merges into that person: the voice
  prints are averaged (desktop).

### C4. Remember voices
- **Each recording keeps one voice print per speaker group**, with that
  group's seconds of speech. *(my call)* So remembering works without
  re-reading the audio, even after the audio has been deleted (B5).
- **Remembering:**
  - needs at least 2 s of their speech: "Not enough of their speech to
    remember the voice (needs 2 s or more)";
  - uses up to 30 s of it.
- **Matching in later recordings** (desktop rules, `speakers.py` 138–170):
  - only groups with at least 3 s of speech are compared;
  - a match needs a score above the threshold (desktop 0.35; for CAM++ set
    on the test set);
  - best pairs go first;
  - each person names at most one group per recording.
- **Settings → "People"** *(my call; the desktop has no such list)*:
  - the remembered names, with Rename and **Forget** ("Forget <name>'s
    voice? Their name stays on past recordings.");
  - your own voice is shown at the top, linking to C2.

  This keeps voice prints under the owner's control.

### C5. Move one line to another speaker
New; the desktop doesn't have it.
- In the line menu (B1), **"Said by…"** opens a list:
  - Me (if trained);
  - the speakers in this recording;
  - the remembered people;
  - **"Someone else…"** (type a name).
- Only that line changes.
- *(my call)* Moving a line does not change any stored voice print. Only a
  rename with the tick box does.

---

## Data changes

drift schema 3, with a migration from 2.

- `meetings` gets:
  - `languages` (e.g. `en,gu`), the choice it was processed with;
  - `speechModel` (faster | accurate);
  - `audioDeleted` (bool), or a cleared `audioPath`, as the builder
    prefers;
  - the step already exists.
- `transcript_lines` gets:
  - `speaker` (the label shown);
  - `speakerGroup` (int, the group within the recording);
  - `edited` (bool).
- New `meeting_speakers`: meeting, group, label, voice print (Float32 bytes
  or JSON), seconds of speech.
- New `people`: id, name (unique, ignoring case), voice print, updated at.
- **The owner's voice print**: a settings entry, or a `people` row marked as
  "me" *(builder's choice)*.
- Settings keys:
  - `aliases`, `languages`, `prefer_indic`, `accuracy`;
  - `keep_audio_days`;
  - `speaker_detection`;
  - `setup_done`.
- Model catalogue: one entry per model (id, files, URL, size, SHA-256,
  licence). The current single `SpeechModel` grows into this; Storage and
  setup read it.

## Errors

| Problem | Behaviour |
|---|---|
| A model download fails | As today: resumes, checks SHA-256, Try again; the Record banner and Settings show it |
| A needed model is missing (deleted, or a language newly ticked) | Recordings wait with "Downloading the Gujarati model…"; nothing is lost |
| FLAC check fails | Pieces kept; tried again at next start; no message unless it fails 3 times ("Couldn't compress this recording's audio; it's kept as it was") |
| Audio deleted by "Keep recordings for" | "The audio for this recording is no longer available."; no player |
| Speaker step fails | Text kept; "Couldn't tell the speakers apart." with Try again |
| Voice training too short | Desktop wording (C2) |
| Remember with under 2 s of speech | Desktop wording (C4) |

## Testing

- **The owner's test set** (built first, in Plan 2b): the owner's own
  recordings with the right words written down, used as files on the PC for
  development only.
  - **Already copied off the phone** (2026-10-14, scratchpad `phone-recs`):
    recordings 2, 16 and 17 (English).
    - Recording 17 contains "fine".
    - Recording 2 contains the name and "Let's stop it".
    - Their right words are still to be written down.
  - The desktop's "Gujarati Test" clip is **not a reference**: its
    transcript is the desktop's English translation, and it is a stage clip
    with 7+ speakers. Use it for speed and rough mixing checks only.
  - **The owner records the rest and writes the right words** (agreed
    2026-10-14). Clips of 1–2 min each, on the phone:
    - Gujarati with English mixed in;
    - some Hindi;
    - the owner and one other person taking turns.

    The right words can be made by running the clips through the PC app and
    correcting its text. That is for development only; the phone never uses
    the PC.

    For the English recordings 2, 16 and 17, the builder drafts the right
    words and the owner corrects them.
  - **Plan 2b starts with a "test set" task** that asks the owner for these
    clips and their text. Until they arrive, tasks that don't need tuning go
    first: the model switch, reading confidences, the catalogue, the
    Languages and Accuracy settings, and the mixing port with the desktop's
    values and its ported tests. The tuning tasks come after.
  - Owner: one or two short recordings for each of:
    - Gujarati with English;
    - Hindi;
    - two people taking turns.
  - Every speech change reports the words wrong on it, before and after.
- **Ported desktop tests:**
  - `test_mixed.py` cases (mixing);
  - `transcript.rs` retime tests;
  - the speaker clean-up rules.
- **Unit tests (Dart, PC):**
  - padding;
  - the copy format;
  - nickname entries;
  - FLAC round trip;
  - seek table;
  - retention rules (never touches unfinished recordings);
  - the model catalogue and Storage sizes;
  - the setup flow;
  - matching and naming speakers;
  - moving a line.
- **Real-model tests** behind the existing environment variables, now also
  for the transducer, the Gujarati and Hindi models and the speaker models.
- **On the M31:**
  - a 30-min English + Gujarati two-person recording with the screen off;
  - time after Stop vs the estimate;
  - peak memory;
  - FLAC playback and seeking;
  - first-start setup from a fresh install.

## Left to the builder

- Hindi vs Gujarati decision method (A3 options).
- Speaker approach (C1 options), its thresholds, and the CAM++ model file:
  the one from the M31 speed test, unless another of sherpa-onnx's CAM++
  files is clearly better on the test set.
- FLAC encoder (B4 options).
- Exact padding (0.2–0.5 s), the word-confidence rule, and re-tuned mixing
  thresholds.
- Whether hotwords help (A4 lead).
- Packages for sharing and the clipboard (share_plus or equivalent).
- Wording not given here, in the existing style (short, plain, the
  desktop's where it exists).
