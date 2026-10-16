# Mobile app, Plan 2b: Better speech — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recordings come out right more often and in the owner's languages. English runs on Parakeet's transducer variant, with padded phrases and per-word confidence. Gujarati/Hindi are written as spoken, with English mixed in word by word (the desktop's method). A Languages and an Accuracy setting choose the models, which the phone downloads itself.

**Architecture:** All logic stays in `mobile/backend`.
- A **model catalogue** replaces the single speech model. Each model (VAD, English Faster, English More accurate, Indic tokens, Gujarati, Hindi) is downloaded, checked, sized and deleted on its own.
- A recording stores its **speech setup** (languages, preferred Indian language, English model) when it is created. Its job always uses that setup.
- The sherpa isolate runs:
  - VAD;
  - the English transducer;
  - the ticked Indian CTC model(s).

  Per padded phrase, a pure-Dart **phrase writer** (port of the desktop's `_combine` + `mixed.py`) makes the line.

**Tech Stack:** As Plan 2a (Flutter 3.47.7 / Dart 3.13, Riverpod 3, drift, sherpa_onnx 1.13.8, archive, crypto). drift schema 2 → 3. No new packages.

**Spec:** [docs/superpowers/specs/2026-10-14-mobile-next-features-design.md](../specs/2026-10-14-mobile-next-features-design.md), Part A (and Findings 1–3). It builds on [2026-10-12-mobile-app-design.md](../specs/2026-10-12-mobile-app-design.md). Plan 2a's ledger: [2026-10-13-mobile-plan-2a-progress.md](2026-10-13-mobile-plan-2a-progress.md).

**Not in this plan:** everything in Parts B (Plan 2c) and C (Plan 3); hotwords (a later lead); re-processing old recordings.

## Global Constraints

- **Screens decide nothing:** logic and ids live in `mobile/backend`; wording lives in `mobile/frontend/lib/ui/wording.dart`.
- **Standalone phone:** nothing at run time comes from the PC.
  - The owner's recordings used for tests stay **outside the repository** (the repository is public). Real-model tests find them through environment variables.
- **The owner commits.** Each "Checkpoint" step is `flutter test` + `flutter analyze` in the touched package(s), not a git commit.
- **Kept from Plan 2a:**
  - threads: 2 live, 4 after Stop, 2 when warm;
  - waits under 20% battery and not charging, or "Only process while charging", or thermal ≥ 3;
  - VAD: threshold 0.5, min silence 0.5 s, min speech 0.25 s, max speech 20 s, window 512, buffer 60 s;
  - Silero VAD download unchanged (`silero_vad.onnx`, 643,854 B, `9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6`).
- **Models (exact):**
  - **English Faster:** archive `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8.tar.bz2`, 108,035,095 B, SHA-256 `f628312e9fdf8686374cb01a69425c41732529d540860311f16f37cbc32cfe9b`. Members under `sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8/`:

    | Member | Bytes | SHA-256 |
    |---|---|---|
    | `encoder.int8.onnx` | 131,113,202 | `0f35509ddeb9b39002fb077d979a9fe74f06eb0bc4dd5c34f512f82e5111d657` |
    | `decoder.int8.onnx` | 3,955,863 | `f7c331c5504c2e593c76ed22b728e3f554af6c4a383dde862e719ced08b1da19` |
    | `joiner.int8.onnx` | 1,411,403 | `bf7dff69e9f2cdbe9943d70da358f38b361c115ba0105bae7e908e0d6ec782f6` |
    | `tokens.txt` | 9,953 | `450e56bd2f036fe5b6aa821865838cc5aa9d8b0106134ce9a9ba0664abe6cd10` |

    Shown as **108 MB**.
  - **English More accurate:** archive `…/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2`, 482,468,385 B, SHA-256 `157c157bc51155e03e37d2466522a3a737dd9c72bb25f36eb18912964161e1ad`. Members under `sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/`: `encoder.int8.onnx`, `decoder.int8.onnx`, `joiner.int8.onnx`, `tokens.txt`. Their sizes and SHA-256 are recorded in Task 2. Shown as **482 MB**.
  - **Indian models:** base `https://huggingface.co/parismitaglobalsolutions/indicconformer-sherpa-onnx/resolve/9721eb71eea141fae0982cfcdb9dd2e3d4953c4a/` (a pinned commit):

    | File | Bytes | SHA-256 |
    |---|---|---|
    | `tokens.txt` | 67,605 | `ee60967630213f31951817ac8b402b92ec18cce80718a24a49b388e56672dfb2` |
    | `gu/model.int8.onnx` | 197,595,461 | `822ed7f0b809bbd479275bf91c913d05564b88c0d082bbcba2f37999b88cb598` |
    | `hi/model.int8.onnx` | 197,595,593 | `915c71e04dd7e5378a4057fdebb252b3a587188e4e99db6d7ce0909ad5ad05fa` |

    Gujarati and Hindi are shown as **198 MB** each (the shared tokens included).
  - Loaded with sherpa-onnx `nemoCtc`, greedy search.
- **Free storage to start a download:** 3 × the archive's size for archives (bz2 + tar + unpacked); file size + 100 MB for single files.
- **Recognizer:**
  - English: `OfflineTransducerModelConfig`, `modelType: 'nemo_transducer'`, greedy search.
  - Results are read from sherpa's native result JSON (`ys_log_probs` included). The Dart `OfflineRecognizerResult` drops it.
- **Padding:** 300 ms before and after each VAD segment.
  - It never reaches before the previous phrase's padded end, before the audio this engine was given, or past the audio fed.
  - Word times stay in recording time.
- **Word confidence:** the lowest `exp(logProb)` among the word's tokens that contain a letter or digit (punctuation tokens don't count). Null when the recognizer gives none (CTC).
- **Vocabulary:** a sound-alike fix applies only when every heard word it replaces has confidence null or **< 0.6**. An exact match always applies.
- **Mixing constants: the desktop's, verbatim** (`mixed.py`, times in ms):

  | Constant | Value |
  |---|---|
  | `SAME_SOUND` | 0.72 |
  | `SAME_SOUND_SHORT` | 0.85 |
  | `EVERY_WORD` | 0.03 |
  | `BETWEEN_MAX` | 3 |
  | `RUN_MIN_WORD` | 0.6 |
  | `RUN_MIN_MEAN` | 0.85 |
  | `RUN_MIN_WORDS` | 4 |
  | `SLACK` | 600 ms |
  | `GAP` | 800 ms |
  | `SENTENCE_MIN_WORDS` | 3 |
  | `SENTENCE_PAUSE` | 800 ms |
  | `SENTENCE_SLACK` | 1000 ms |
  | `SENTENCE_SAME` | 0.62 |
  | `MAX_INDIC_WORDS` | 2 |
  | `MAX_ENGLISH_WORDS` | 3 |
  | `free()` margin | 150 ms |

  The word lists are verbatim too: `NOT_ENGLISH_ALONE`, `NATIVE_NAMES`, `COMMON_INDIC`, `NOT_ENGLISH_ALONE_EXTRA`, `ENDINGS`, `_SUFFIXES`, `_EN_RULES`, `CONSONANTS`, `VOWELS`, `CLOSE`.
  - English confidence thresholds (0.3 / 0.5 / 0.6 / 0.85) start at the desktop's values. Task 9 may re-tune them.
- **Combine** (desktop `_combine`, phone-adapted):
  - An Indic-silent stretch is ≥ **2000 ms**.
  - It is taken directly as English when it holds ≥ 2 English words, of which ≥ **80%** are dictionary words with mean confidence ≥ **0.85**.
  - `MOSTLY_ENGLISH` **0.7**.
- **Hindi or Gujarati markers** (compared after mapping Gujarati letters to Devanagari: code point − 0x180):
  - Hindi: है हैं था थे क्या मुझे मैं हम यह वह और लेकिन बहुत अच्छा रहा रही रहे मेरा मेरी मेरे तुम लिए कैसे कहाँ यहाँ वहाँ हूँ
  - Gujarati: છે છો છું છીએ હતો હતી હતું શું તમે હું આપણે મને નથી એટલે પણ કેમ મારું તમારું
- **Settings keys:**
  - `languages`: comma list in the order en,hi,gu; default `en`;
  - `prefer_indic`: `gu` or `hi`; default `gu`;
  - `accuracy`: `auto`, `faster` or `accurate`; default `auto`.
- **Auto** picks More accurate only when the CPU has ARM dot-product (`asimddp` in `/proc/cpuinfo` Features) **and** total RAM ≥ 5.5 GiB. Otherwise (e.g. the M31) it picks Faster.
- **Speed defaults** until measured (processing time ÷ audio time, after Stop, 4 threads; M31 speed test):
  - Faster 0.17;
  - More accurate 0.9 (estimate);
  - each Indian language 0.2 (estimate).
- **Wording (spec, exact):**
  - "Languages you speak"
  - "Each phrase is recognised in whichever of these you speak — mix them freely."
  - "Hindi or Gujarati — which do you speak more?"
  - "Written as spoken, Hindi and Gujarati are told apart by sound, and this one wins when it's unclear."
  - "Accuracy (speech model)"
  - "Auto — picks for this phone"
  - Chips: "English", "हिन्दी Hindi", "ગુજરાતી Gujarati"
  - "Gujarati model · 198 MB. Wi-Fi recommended."

## Review Focus

- **A recording made with Gujarati on whose Gujarati model is later deleted, or still downloading.** Expected: it waits ("model") and is never processed English-only. Task 7 test `a recording waits for the models of its own setup`.
- **The owner's phone after the update** (old CTC files present, new model missing). Expected: queued recordings wait, the banner offers the download, and the old `parakeet/` folder is removed at start. Task 2 test `the old CTC model is removed`; Task 7 test above.
- **Padding at the edges:** a phrase at 0 ms, the first phrase of a resumed job, two phrases 0.5 s apart, and the last phrase on `finish()`. Expected: no out-of-range read, no word recognized twice. Task 6 tests `padding stays within the audio and never overlaps the phrase before` and `a resumed job's first phrase is padded only from its own audio`.
- **One reader hears nothing** (English empty or Indian empty for a phrase). Expected: the other reader's words; both empty, no line. Task 5 test `one reader empty gives the other's words`.
- **A 198 MB Hugging Face file**: its `resolve/` URL redirects to another host, and the download breaks halfway. Expected: the redirect is followed, it resumes, and the SHA-256 is checked. Task 2 tests `a cross-host redirect is followed` and `a single-file model resumes and is checked`.

---

### Task 1: Word confidence

**Files:**
- Modify: `mobile/backend/lib/data/transcript.dart`, `mobile/backend/lib/data/transcript_repository.dart`, `mobile/backend/lib/engine/speech/words.dart`
- Test: `mobile/backend/test/engine/speech/words_test.dart`, `mobile/backend/test/data/transcript_repository_test.dart`

**Interfaces:**
- Produces:
  - `Word(String text, int startMs, int endMs, [double? conf])`. Value equality includes `conf`.
  - `wordsJson` elements are `["w", s, e]`, or `["w", s, e, conf]` when `conf != null`, with conf rounded to 2 decimals. Old rows read with `conf == null`.
  - `phraseFromTokens(tokens, timestamps, {required int startMs, required int endMs, List<double>? logProbs})`. A word's `conf` follows Global Constraints; it is null when `logProbs` is null or empty.

- [ ] **Step 1: Write the failing tests**
  - `a word's confidence is its weakest token's` (tokens `▁N`,`est`,`e`,`.` with log probs of 0.92, 0.43, 0.16, 0.67 → one word `Neste.`, conf 0.16).
  - `punctuation tokens don't lower a word's confidence` (`▁it` 0.93, `.` 0.49 → conf 0.93).
  - `no log probs gives no confidence`.
  - Repository: `a word's confidence round-trips, and old rows read without one` (insert a raw `wordsJson` of `[["a",0,10]]` → `conf == null`).
- [ ] **Step 2: Run them** — `cd mobile/backend && flutter test test/engine/speech/words_test.dart test/data` → FAIL.
- [ ] **Step 3: Implement** `conf` on `Word`, the JSON fourth element, and `logProbs` in `phraseFromTokens`.
- [ ] **Step 4: Run them** — PASS; all other backend tests pass.
- [ ] **Step 5: Checkpoint** — `flutter test && flutter analyze` in `mobile/backend`.

### Task 2: The model catalogue

**Files:**
- Create: `mobile/backend/lib/engine/models/catalogue.dart`, `mobile/backend/lib/engine/models/model_store.dart`
- Modify: `mobile/backend/lib/engine/models/speech_model.dart` (becomes the models notifier; `_unpack` and `_unpackInIsolate` move to `model_store.dart`), `mobile/backend/lib/start.dart`
- Test: `mobile/backend/test/engine/models/model_store_test.dart` (replaces `speech_model_test.dart`; its cases carry over), `mobile/backend/test/engine/models/downloader_test.dart`

**Interfaces:**
- Produces:
  - `enum ModelId { vad, englishFaster, englishAccurate, indicTokens, gujarati, hindi }`.
  - `class ModelSpec { ModelId id; String folder; ModelDownload download; List<ModelMember> members; String? fileName; List<ModelId> needs; int shownBytes; }`.
    - `members` is empty for a single-file model, which is saved as `<folder>/<fileName>`.
    - `needs`: gujarati and hindi need `indicTokens`.
  - `const kCatalogue` with the Global Constraints values. Folders under `<models root>/speech/`:
    - `vad` stays at `speech/silero_vad.onnx`, so phones keep their file;
    - `parakeet-tdt-110m/`, `parakeet-tdt-0.6b/`;
    - `indic/tokens.txt`, `indic/gu.int8.onnx`, `indic/hi.int8.onnx`.
  - `int minFreeToDownload(ModelSpec s)`.
  - `class ModelStore`:
    - `ModelStore(Directory root, Downloader d, {Map<ModelId, ModelSpec> catalogue = kCatalogue})`
    - `bool ready(ModelId id)` (by sizes, as now)
    - `File file(ModelId id, String name)`
    - `int bytesOnDisk(ModelId id)`
    - `Future<void> download(ModelId id, {void Function(int done, int total)? onProgress})`: archive → unpack in isolate → check members' SHA-256; single file → `Downloader.fetch` with size + SHA-256.
    - `Future<void> delete(ModelId id)`
    - `Future<void> removeOldCtc()`: deletes `speech/parakeet/` (Plan 2a's CTC model).
  - `enum ModelPhase { missing, downloading, ready, failed }`.
  - `class ModelState { ModelPhase phase; int done, total; String? message; }`.
  - `modelStoreProvider`.
  - `modelsProvider = NotifierProvider<Models, Map<ModelId, ModelState>>`, with:
    - `Future<void> download(ModelId id)`: its `needs` first; free space checked with `minFreeToDownload`; same failure messages as now (`storage_low`, `network`, `corrupt`);
    - `Future<void> delete(ModelId id)`;
    - `bool isReady(ModelId id)`.
  - `SpeechModelState` / `SpeechModelPhase` / `speechModelProvider` are removed. Task 3 adds the aggregate the screens use.

- [ ] **Step 1: Record the More accurate members.**
  - Download the 0.6B archive once on the PC into the scratchpad (its own empty folder) and check the archive's SHA-256.
  - List the four members' sizes and SHA-256 into `kCatalogue`.
  - Also keep the unpacked folder for Task 6's real-model tests.
- [ ] **Step 2: Write the failing tests** (fake `Downloader` serving bytes, as `speech_model_test.dart` does). Carry the old cases over per model.
  - `an archive model is unpacked to its folder and checked`.
  - `a single-file model resumes and is checked` (half a file present → fetch resumes; a wrong SHA-256 → deleted, `DownloadFailed('corrupt')`).
  - `downloading Gujarati gets the shared tokens first`.
  - `deleting Hindi keeps the shared tokens while Gujarati is there`.
  - `bytesOnDisk counts a model's files`.
  - `the old CTC model is removed`.
  - `not enough free space fails as storage_low` (minFree for an archive = 3× its size).
  - downloader_test: `a cross-host redirect is followed` (302 to another host → fetched there; the existing manual-redirect code may already pass).
- [ ] **Step 3: Run them** — FAIL.
- [ ] **Step 4: Implement** the catalogue, store and notifier. Call `removeOldCtc()` in `openBackend()` after the models folder is made.
- [ ] **Step 5: Run them** — PASS. The old processor/screen references don't compile yet. The backend test run is green after Task 3; until then run `flutter test test/engine/models`.

### Task 3: Speech settings and each recording's setup (schema 3)

**Files:**
- Create: `mobile/backend/lib/engine/speech/speech_setup.dart`
- Modify:
  - `mobile/backend/lib/data/db.dart` (+ `db.g.dart`), `recording.dart`, `recordings_repository.dart`;
  - `mobile/backend/lib/engine/audio/recorder_controller.dart`;
  - `mobile/backend/lib/engine/models/speech_model.dart`;
  - `mobile/frontend/android/app/src/main/kotlin/com/rajvee/mobile/VoiceDeskApplication.kt`
- Test: `mobile/backend/test/engine/speech/speech_setup_test.dart`, `mobile/backend/test/data/migration_test.dart`, `mobile/backend/test/data/recordings_repository_test.dart`

**Interfaces:**
- Consumes: `ModelId`, `modelsProvider` (Task 2).
- Produces:
  - `enum Lang { en, hi, gu }` (`code`: `en`, `hi`, `gu`).
  - `enum EnglishModel { faster, accurate }`.
  - `enum Accuracy { auto, faster, accurate }`.
  - `class SpeechSetup`:
    - fields `Set<Lang> languages; Lang prefer; EnglishModel english;`;
    - `static const englishOnly`;
    - `List<ModelId> get models`: vad; the English model if `en` is ticked; `indicTokens` + each ticked Indian language;
    - `String get key` (e.g. `faster+gu`, for speeds);
    - value equality.
  - `class SpeechSettings { Set<Lang> languages; Lang prefer; Accuracy accuracy; }`.
  - `speechSettingsProvider = AsyncNotifierProvider<SpeechSettingsNotifier, SpeechSettings>`, with:
    - `setLanguages(Set<Lang>)`: an empty set throws `ArgumentError`;
    - `setPrefer(Lang)`;
    - `setAccuracy(Accuracy)`.
  - `class PhoneClass { int totalRamBytes; bool dotProduct; EnglishModel get auto; }`. `phoneClassProvider = FutureProvider<PhoneClass>` reads RAM through `voicedesk/device` `totalRam` (Kotlin: `ActivityManager.MemoryInfo.totalMem`) and dot-product from `/proc/cpuinfo`.
  - `speechSetupProvider = FutureProvider<SpeechSetup>` (the settings now, Auto resolved).
  - `neededModelsProvider = Provider<SpeechModelsState>`: `{ModelPhase phase; int done, total; int bytesToDownload}`, the aggregate of `speechSetupProvider`'s models. It is ready when all are ready, downloading if any is, failed if any failed, missing otherwise. Also `Models.downloadNeeded()`.
  - Schema 3: `Meetings.languages` (text, default `'en'`), `Meetings.preferIndic` (`'gu'`), `Meetings.englishModel` (`'faster'`); migration from 2 adds them.
  - `Recording.setup` (`SpeechSetup`).
  - `RecordingsRepository.create({String? title, required DateTime startedAt, SpeechSetup setup = SpeechSetup.englishOnly})`.
  - `RecorderController.start` passes `await ref.read(speechSetupProvider.future)`.

- [ ] **Step 1: Write the failing tests**
  - `the default is English only, Gujarati preferred, Auto`.
  - `languages can't all be turned off`.
  - `Auto is Faster without dot-product or under 5.5 GiB, More accurate with both`.
  - `a setup needs only the models of its languages` (`{en}` → vad + englishFaster; `{en,gu}` + accurate → vad, englishAccurate, indicTokens, gujarati; `{gu}` → vad, indicTokens, gujarati).
  - `needed models are ready only when all are`.
  - migration: `a version-2 database opens as version 3 with its recordings English-only`.
  - repository: `a recording keeps the setup it was created with`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement** them; regenerate drift; add `totalRam` to the Kotlin channel.
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint** — backend `flutter test && flutter analyze`. The processor and screens are updated in Tasks 7–8. Until then they compile against the new names with the smallest change: the processor checks `neededModelsProvider`.

### Task 4: The desktop's mixing, in Dart

**Files:**
- Create: `mobile/backend/lib/engine/speech/mixed.dart`
- Test: `mobile/backend/test/engine/speech/mixed_test.dart`

**Interfaces:**
- Produces:
  - `class MixWord { String w; int s, e; String lang /* 'en' | 'indic' */; double p; }` (`p` is English confidence; 1.0 when unknown).
  - `class EnglishWords { factory EnglishWords.parse(String text); bool isEnglish(String word); }`: every entry lowercased (unlike `CommonWords`, capitalised entries count), plus the desktop's suffix rules.
  - `englishWordsProvider` loads `packages/mobile_backend/assets/english-words.txt`.
  - Functions:
    - `String indicSounds(String w)`
    - `String englishSounds(String w)`
    - `double soundSimilarity(String a, String b)`
    - `(double, int, int, int, int) localMatch(String a, String b)`
    - `List<List<int>> sentences(List<MixWord> english)`
    - `List<MixWord> merge(List<MixWord> indic, List<MixWord> english, EnglishWords dict)`
    - `String joinWords(List<MixWord> words)`
  - Behaviour is a line-for-line port of `desktop/backend/engine/mixed.py` (lines 27–534), times in ms.

- [ ] **Step 1: Port the tests.** Port `desktop/backend/engine/test_mixed.py` tests 33–127 and 157–159 one for one, same inputs (seconds → ms) and the same expected strings. For example, `english word replaces its gujarati spelling` expects `હા એનું background તો Scottish છે`; `gujarati ending stays on the english word` expects `તો Kansas Cityથી છે`. Use the bundled word list.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Port** `mixed.py` (Python regex rules in `_EN_RULES` → Dart `RegExp`, applied in order, including the capital-letter trick).
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 5: Writing a phrase from the readers

**Files:**
- Create: `mobile/backend/lib/engine/speech/phrase_writer.dart`
- Test: `mobile/backend/test/engine/speech/phrase_writer_test.dart`

**Interfaces:**
- Consumes: `Phrase`, `Word` (Task 1), `merge`, `EnglishWords` (Task 4), `Lang` (Task 3).
- Produces:
  - `Phrase? writePhrase({Phrase? english, Phrase? indic, required EnglishWords dict})`:
    - null when both are empty;
    - English only → english;
    - Indian only → indic;
    - both → Combine (Global Constraints): Indic-silent stretches (port `uncovered` from `transcriber.py`), `merge` for the rest, direct words inserted by time, ≥ 70% `en` → `english` as Parakeet wrote it.
    - Output words keep `conf` for English words, null for Indian.
  - `List<(int, int)> uncovered(List<Word> words, int startMs, int endMs, int minMs)`.
  - `bool worthTryingOther(Phrase preferredOutput, Lang preferred)`: the other language's markers ≥ 1 and more than the preferred's.
  - `Lang pickIndic(Phrase preferredOutput, Phrase otherOutput, Lang preferred)`: the other wins only when its own output has more of its markers than of the preferred's markers.

- [ ] **Step 1: Write the failing tests**
  - `one reader empty gives the other's words` (both ways; both empty → null).
  - `a mostly English phrase is written as Parakeet wrote it`.
  - `an Indic-silent stretch of confident dictionary English is taken directly` (Indic words 0–1500 ms, English words 2000–4500 ms with conf 0.9 → appended in English). The same with mean conf 0.7 → not taken.
  - `stretches without words` (port `test_stretches_without_words`: `uncovered(ws, 0, 8000, 2000) == [(1600, 4500), (4700, 8000)]`).
  - `Hindi words in a Gujarati reading suggest trying Hindi` (Gujarati-script `મુઝે ક્યા પતા થા` → true; `હું ઘરે છું` → false).
  - `the other language wins only on its own markers`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS.
- [ ] **Step 5: Checkpoint.**

### Task 6: The engine: transducer, padding, Indian models

**Files:**
- Modify: `mobile/backend/lib/engine/speech/sherpa_speech.dart`, `mobile/backend/lib/engine/speech/speech_to_text.dart`
- Test: `mobile/backend/test/engine/speech/padding_test.dart`, `mobile/backend/test/engine/speech/sherpa_speech_test.dart` (real models)

**Interfaces:**
- Consumes: `ModelStore.file` (Task 2), `SpeechSetup` (Task 3), `phraseFromTokens` with `logProbs` (Task 1), `writePhrase` / `worthTryingOther` / `pickIndic` (Task 5).
- Produces:
  - `typedef SpeechToTextFactory = Future<SpeechToText> Function({required SpeechSetup setup, required int startMs, required int threads})`.
  - `SherpaSpeech.start(SpeechFiles files, SpeechSetup setup, {required String englishWords, required int startMs, required int threads, String? libraryDir})`, where:
    - `SpeechFiles { File vad; TransducerFiles? english; File? indicTokens; Map<Lang, File> indic; }`;
    - `TransducerFiles { File encoder, decoder, joiner, tokens; }`;
    - `englishWords` is the word-list text, parsed in the isolate.
  - `(int, int) paddedRange({required int start, required int end, required int floor, required int fed, int pad = 4800})` in samples, in `sherpa_speech.dart`. It is a pure top-level function, so it can be tested without models.
  - Holding back: `settled` also keeps the padding back. With no speech going on: `fed - _confirmSamples - pad`. After a segment: its padded end.

- [ ] **Step 1: Write the failing tests**
  - `padding stays within the audio and never overlaps the phrase before`:
    - `paddedRange(start: 2000, end: 9000, floor: 0, fed: 20000)` → `(0, 13800)`;
    - `floor: 1000` → `(1000, 13800)`;
    - `fed: 10000` → `(0, 10000)`.
  - `a resumed job's first phrase is padded only from its own audio` (floor = the engine's first sample).
  - Real models, skipped without `VOICEDESK_TEST_MODELS` (a folder laid out as the store's `speech/`), `VOICEDESK_SHERPA_LIB` and `VOICEDESK_TEST_AUDIO` (the owner's recordings, outside the repo):
    - `recording 17's "fine" is heard as fine` (`rec17.wav`: the text contains `fine`; no line is just `by`);
    - `recording 2: Let's stop it, with confidences` (contains `stop it from the notification bar`, not `Letter`; English words have `conf`);
    - `Gujarati with English mixed comes out in both scripts` (`gujarati-test.wav`, setup `{en,gu}`: some words in Gujarati script, some in Latin letters).
    - Each prints its real-time factor.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.** Steps:
  1. Keep the last 25 s of fed samples, with their start index.
  2. Per VAD segment, cut `paddedRange` from that buffer.
  3. Run the English transducer when `en` is ticked, and read the result JSON (`SherpaOnnxBindings.getOfflineStreamResultAsJson` / `destroyOfflineStreamResultJson`, implementation import with an `ignore` comment) for `tokens`, `timestamps`, `ys_log_probs`.
  4. Run the preferred Indian model, and the other one (loaded on first need) when `worthTryingOther`, using `pickIndic`.
  5. Call `writePhrase`.

  The factory provider builds `SpeechFiles` from `modelStoreProvider` and reads `englishWordsProvider`'s text.
- [ ] **Step 4: Run them** — PASS (real-model tests with the environment set: models from the scratchpad, `rec2/16/17.wav` copied off the phone, `gujarati-test.wav`).
- [ ] **Step 5: Checkpoint.**

### Task 7: The processor uses each recording's setup

**Files:**
- Create: `mobile/backend/lib/engine/pipeline/speed_book.dart`
- Modify: `mobile/backend/lib/engine/pipeline/processor.dart`, `mobile/backend/lib/engine/speech/vocabulary.dart`
- Test: `mobile/backend/test/engine/pipeline/processor_test.dart`, `live_processing_test.dart`, `mobile/backend/test/engine/speech/vocabulary_test.dart`, `mobile/backend/test/engine/pipeline/speed_book_test.dart`

**Interfaces:**
- Consumes: `Recording.setup`, `modelsProvider` (Tasks 2–3), the new factory (Task 6).
- Produces:
  - Jobs and live steps start the engine with `setup: r.setup`. A recording whose models aren't all ready waits (`ProcessingState(waiting: 'model')`), and processing kicks again when any model becomes ready.
  - `class SpeedBook { SpeedBook(SettingsRepository s); Future<double> rtf(SpeechSetup s); Future<void> record(SpeechSetup s, double rtf); }`:
    - stored as `speed:<key>`, the mean of the last 5;
    - with nothing stored, the sum of the defaults in Global Constraints.
  - `speedBookProvider`.
  - The processor records an after-Stop job's speed when it ran on 4 threads over at least 60 s of audio.
  - `Duration estimateFor(SpeechSetup s, Duration audio)`.
  - `Vocabulary(entries, common, {double fixBelow = 0.6})`: sound-alike only when every replaced word has `conf == null || conf < fixBelow`.

- [ ] **Step 1: Write the failing tests**
  - `a recording waits for the models of its own setup` (setup `{en,gu}`, Gujarati missing → status stays queued, waiting `model`; Gujarati turns ready → processed with that setup, checked through a fake factory recording its `setup`).
  - `live processing uses the recording's setup`.
  - `speeds are remembered per setup, defaults until then` (`{en}` faster → 0.17; `{en,gu}` faster → 0.37; record 0.3 → 0.3).
  - vocabulary:
    - `a confidently heard word is never changed into a sound-alike` ("Nishher" conf 0.95 stays);
    - `an unsure one is` ("Nishher" conf 0.3 → "Nishchay");
    - `an exact match applies at any confidence`;
    - `Gujarati-script words never match an entry`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS; the whole backend suite passes.
- [ ] **Step 5: Checkpoint.**

### Task 8: Settings → Speech, and the download banner

**Files:**
- Create: `mobile/frontend/lib/ui/settings/speech_card.dart`
- Modify: `mobile/frontend/lib/ui/settings/settings_screen.dart` (the English model tile goes), `mobile/frontend/lib/ui/record/speech_model_banner.dart`, `mobile/frontend/lib/ui/wording.dart`, `mobile/frontend/test/ui/fakes.dart`
- Test: `mobile/frontend/test/ui/speech_card_test.dart`, `mobile/frontend/test/ui/settings_screen_test.dart`, `mobile/frontend/test/ui/record_screen_test.dart`

**Interfaces:**
- Consumes: `speechSettingsProvider`, `phoneClassProvider`, `modelsProvider`, `neededModelsProvider`, `speedBookProvider` (Tasks 2, 3, 7).
- Produces: the `SpeechCard` widget. `quietBackend()` gains overrides for the new providers.

The card, top to bottom:

1. **"Languages you speak"**, three `FilterChip`s and the hint.
   - Ticking a language whose model is missing asks first: title "Gujarati model · 198 MB", body "Wi-Fi recommended.", Cancel / Download. Download ticks it and starts the download; Cancel leaves it unticked.
   - The last ticked chip can't be unticked.
   - Under the chips, per downloading or failed language: "Downloading the Gujarati model · 45%", or "Couldn't download the Gujarati model." with Try again.
2. **The Hindi/Gujarati question.** When both are ticked: the question, a `SegmentedButton` Hindi | Gujarati, and the hint.
3. **"Accuracy (speech model)"**, three radio tiles:
   - "Auto — picks for this phone", subtitle "Now: Faster";
   - "Faster";
   - "More accurate".

   Each subtitle: "Downloaded" or "Downloads 482 MB", then " · about N min for a 30-min recording" from `estimateFor`. Choosing one that isn't downloaded asks first (same dialog shape) and downloads it.

The Record banner now shows `neededModelsProvider`: missing → "Turn recordings into text: download the speech models (X MB, Wi-Fi recommended)."; the downloading and failed texts as now.

- [ ] **Step 1: Write the failing tests**
  - `ticking Gujarati asks, then downloads`.
  - `Cancel leaves it unticked`.
  - `English can't be unticked when it's the only language`.
  - `the Hindi/Gujarati question shows only with both ticked`.
  - `accuracy cards show size or Downloaded, and the time`.
  - `More accurate asks before downloading`.
  - `the banner counts what the settings need`.
- [ ] **Step 2: Run them** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them** — PASS; the whole frontend suite passes.
- [ ] **Step 5: Checkpoint** — frontend `flutter test && flutter analyze`.

### Task 9: The owner's test set, and tuning

**Files:**
- Create: `mobile/backend/tool/word_errors.dart` (a PC tool, not shipped)
- Modify (constants only, if results say so): `sherpa_speech.dart` (pad), `phrase_writer.dart`, `mixed.dart`, `vocabulary.dart`

**Interfaces:**
- Produces: `dart run tool/word_errors.dart <audio folder> [--setup en,gu] [--accurate]`. For each `name.wav` with a `name.txt` (the right words) it prints words wrong (edit distance over words, ignoring case and punctuation) and the real-time factor, plus a total.

- [ ] **Step 1: Ask the owner for the clips** (spec Testing), 1–2 min each, recorded on the phone:
  - Gujarati with English;
  - some Hindi;
  - two people taking turns.

  Then for each, the right words. Running the clips through the PC app and correcting its text is fine. Draft the right words for `rec2`, `rec16` and `rec17` for the owner to correct. **Until the clips arrive, Tasks 1–8 and 10 don't wait.**
- [ ] **Step 2: Write the tool** and a unit test for its word-error count (`word errors: one substitution and one missing word count 2`).
- [ ] **Step 3: Measure the baseline:** CTC (Plan 2a) vs transducer, padding 0 vs 300 ms, Faster vs More accurate, `{en}` vs `{en,gu}`. Write the table into the progress ledger.
- [ ] **Step 4: Tune**, one value at a time, keeping a change only if total words wrong go down and no clip gets worse:
  - padding 200–500 ms;
  - the vocabulary `fixBelow`;
  - mixing confidence thresholds;
  - the Combine 80% / 0.85 rule;
  - the markers.

  Ported desktop tests must still pass.
- [ ] **Step 5: Checkpoint**, and add the after-tuning table to the ledger.

### Task 10: On the Galaxy M31, and the docs

- [ ] **Step 1: Install on the M31.** Start the app (the old CTC files go, and the banner asks for 108 MB). Download, record 30 s of English, check the lines.
- [ ] **Step 2: Gujarati.**
  - Tick Gujarati (the dialog, 198 MB).
  - Record a 2-min English + Gujarati recording with the screen off.
  - Check that the lines are mixed.
  - Measure the time after Stop and peak memory (`dumpsys meminfo com.rajvee.mobile` during processing).
  - Compare with the estimate.
- [ ] **Step 3: More accurate.** Choose it, download 482 MB, process the same audio again as a new recording made by playing the clip, and record its speed.
- [ ] **Step 4: Update the docs.**
  - Mobile spec: Plans list and Step 2 now use the ready-made IndicConformer files through sherpa-onnx; the owner-published model is no longer needed; Model downloads.
  - The status file.
  - A new ledger `2026-10-14-mobile-plan-2b-progress.md`: tasks, the measurements and anything deferred.
