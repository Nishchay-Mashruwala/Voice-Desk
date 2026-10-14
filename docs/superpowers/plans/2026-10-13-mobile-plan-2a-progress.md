# Mobile Plan 2a — progress ledger

Plan: [2026-10-13-mobile-plan-2a-english-speech.md](2026-10-13-mobile-plan-2a-english-speech.md). One line per decision ("Ruling") and per finished task. **Plan 2a is complete** (2026-10-13): 13 tasks, final review, fix pass. "commits 8f0f01d..8f0f01d" means nothing was committed (the owner commits later).

Setup: Ruling: no worktree; current tree, branch restructure-frontend-backend — owner forbids commits and mobile/ is untracked — cost if wrong: none.
Setup: Ruling: "Checkpoint" steps = flutter test + flutter analyze (owner's no-commit rule) — cost if wrong: owner commits later.
Setup: Ruling: battery threshold 20% (owner changed it from the spec's 30% on 2026-10-13; spec and plan updated) — cost if wrong: none.
Setup: spec read: docs/superpowers/specs/2026-10-12-mobile-app-design.md
Pre-flight: T1→T2 Word/Phrase value classes → phraseFromTokens returns Phrase: consistent.
Pre-flight: T1→T8 TranscriptRepository.save(id, phrases, processedMs:), RecordingGone, setStatus, startAttempt/clearAttempts, nextToProcess: consistent.
Pre-flight: T1→T12 transcriptProvider (family by id), Recording.progress: consistent.
Pre-flight: T3→T8/T9 readSamples(pieces, fromMs:, toMs:, chunkMs:), totalMs: consistent.
Pre-flight: T4→T5 Downloader.fetch(url, dest, size:, sha256:, onBytes:) — T5's fake must implement Downloader: consistent (make fetch overridable).
Pre-flight: T5→T6 SpeechModelFiles(vad, model, tokens): consistent.
Pre-flight: T5→T8/T11 speechModelProvider (phase ready/missing/downloading/failed; download(), delete()): consistent.
Pre-flight: T6→T8/T9 SpeechToTextFactory({startMs, threads}), Transcribed(phrases, settledMs): consistent.
Pre-flight: T7→T8/T9 decide(...) → (gate, threads), DeviceState.changes, setting only_while_charging: consistent.
Pre-flight: T8→T9 Processor.kick(), pieceFinished(id, n); PieceWriter.onPieceFinished: consistent.
Pre-flight: T8→T10 ProcessingNotice.show(title, progress, left)/hide, provider replaced by T10: consistent.
Pre-flight: T8→T12 ProcessingState(recordingId, title, progress, left, waiting), Processor.retry: consistent.
Task 1: Ruling: transcript column getter named content (stored as "text") — a getter named text would shadow drift's text() builder — cost if wrong: none.
Task 1: Ruling: sqlite3 ^3.7.0 added as a dev dependency — the migration test writes the version-1 tables with raw SQL — cost if wrong: none (test only).
Task 1: Ruling: added test 'attempts count up and clear' for the plan's startAttempt/clearAttempts — cost if wrong: none.
Task 1: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:03 +26: All tests passed!)
Task 2: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:03 +26: All tests passed!)
Task 3: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:03 +26: All tests passed!)
Task 4: Ruling: redirects followed by hand (followRedirects false) — keeps the Range header across GitHub's redirect to another host; a 416 means the part is already whole; a 200 to a Range request rewrites from 0 — cost if wrong: none.
Task 4: checked once against the real GitHub URL (https + redirect + SHA-256) with a throwaway test: passed.
Task 4: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:03 +26: All tests passed!)
Task 5: Ruling: test doubles via optional named params on SpeechModelStore (vad:, archive:, members:) instead of a separate forTest constructor — same effect, one constructor — cost if wrong: none.
Task 5: fixed a real bug the notifier test caught: the closure sent to Isolate.run captured the notifier (unsendable) — unpacking now starts from a top-level helper.
Task 5: Ruling: the notifier test also covers download→ready→delete→missing (the plan's 'delete removes the files' test, via the notifier) — cost if wrong: none.
Task 5: checked once with the real 104 MB archive (throwaway test): unpacked and verified in 12 s on the PC. Task 11 words the unpacking time (done == total) as 'Preparing the speech model…'.
Task 5: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:03 +26: All tests passed!)
Task 6: Ruling: on Windows (tests only) sherpa_speech preloads onnxruntime.dll from libraryDir — System32 has a 3 kB onnxruntime.dll stub Windows would load first ('not a valid Win32 application') — cost if wrong: none on the phone (libraryDir is null there).
Task 6: Ruling: settledMs = end of fed audio when the VAD has no speech going, else the end of the last finished phrase (sherpa doesn't expose the open segment's start) — a resume may re-feed a little audio, never skip any — cost if wrong: a few seconds of audio processed twice after a kill.
Task 6: real models on the PC: test_wavs/0.wav → 'Well, I don't wish to see it anymore, observed Phoebe, turning away her eyes' / 'It is certainly very like the old portrait' (cased, punctuated, times offset by 5000 ms).
Task 6: debug APK is 265 MB (sherpa-onnx + onnxruntime for 4 ABIs); release builds should use --split-per-abi (later).
Task 6: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:03 +26: All tests passed!)
Task 7: Ruling: 'connected, not charging' counts as charging (plugged in) — the owner's intent is plugged-in processing — cost if wrong: processing on a plugged phone that isn't gaining charge.
Task 7: Ruling: added test 'only while charging, plugged in, goes' — the other half of the setting — cost if wrong: none.
Task 7: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:04 +26: All tests passed!)
Task 8: Ruling: Processor exposes 'bool get busy' (the loop is running) — tests wait on real conditions instead of fixed sleeps — cost if wrong: none.
Task 8: Ruling: SpeechModel.isReady reads the files on disk (not the state built at start) — the processor checks before each job — cost if wrong: none.
Task 8: Ruling: added test 'threads: 4 after Stop, 2 when the phone is warm' — the plan's thread rule had no processor-level test — cost if wrong: none.
Task 8: Ruling: start.dart unchanged — nextToProcess already includes recordings left 'processing' by a kill, so they resume — cost if wrong: none.
Task 8: Ruling: waitCool re-checks after 1 minute (a timer); waitCharge waits for the battery's charging event — cost if wrong: a cooled phone waits up to a minute.
Task 8: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:03 +26: All tests passed!)
Task 9: Ruling: the recorder talks to processing through ProcessingTrigger (processingTriggerProvider) instead of reading processorProvider — the recorder's tests would otherwise build the real processor (battery plugin, models folder) — cost if wrong: none.
Task 9: Ruling: one engine at a time — a job after Stop first closes the live engine; live work is skipped while such a job runs (done after Stop) — matches 'one job at a time' and keeps one model in memory — cost if wrong: less live work when an older recording is still being processed.
Task 9: Ruling: added tests 'the next piece continues where the last left off' (one engine per recording) and the recorder's 'tells processing about each finished piece, and when it stops' — cost if wrong: none.
Task 9: Ruling: recordingStopped is only called for a kept recording (not one dropped as too short) — cost if wrong: none.
Task 9: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:04 +26: All tests passed!)
Task 10: Ruling: one ForegroundService coordinator with two adapters (.recording, .processing) instead of one class implementing both interfaces — both have show()/hide() with different meanings — cost if wrong: none.
Task 10: Ruling: a processing notification that fails to start is ignored (processing goes on); a recording one still throws (Plan 1's I3 behaviour) — cost if wrong: processing without its notification may be stopped by Android when the app is closed.
Task 10: Ruling: when recording stops while processing runs, the service keeps its microphone type and just changes text (no restart) — cost if wrong: none (the mic isn't used).
Task 10: Plan 1's test 'a notification service that does not start is reported' now goes through ForegroundService().recording — same behaviour.
Task 10: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:08 +27: All tests passed!)
Task 11: Ruling: the setting is a backend notifier (onlyWhileChargingProvider: saves, then ProcessingTrigger.conditionsChanged wakes processing) — screens decide nothing — backend test 'the only-while-charging setting is saved and applies at once' — cost if wrong: none.
Task 11: Ruling: 'Preparing the speech model…' while unpacking (done == total) — found in Task 5 — cost if wrong: none.
Task 11: Ruling: sizes in decimal MB (104,981,681 bytes → 105 MB, as the plan's wording) — cost if wrong: none.
Task 11: Ruling: test/ui/fakes.dart (FakeSpeechModel, FakeOnlyWhileCharging, IdleProcessor, quietBackend()) used by the screen tests that now read backend notifiers — cost if wrong: none.
Task 11: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:03 +33: All tests passed!)
Task 12: Ruling: tapping a line loads the audio if needed, seeks there and plays (not only seeks) — tapping a line to hear it is what a person expects; a live recording's lines aren't tappable — cost if wrong: one tap more to start playing.
Task 12: Ruling: with no lines yet (queued/processing/recording) the screen says 'The transcript appears here as the recording is turned into text.' — the plan gave no words for this case — cost if wrong: none.
Task 12: Ruling: added tests 'without an estimate yet it gives the percent only' and 'one that stopped the app twice says how to help' — cost if wrong: none.
Task 12: the Record screen watching processorProvider is what starts the processor in the app (its build kicks once).
Task 12: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:03 +42: All tests passed!)
Task 13: on the M31 — model download via the Record banner: 105 MB in ~50 s (Wi-Fi), unpacked in ~75 s, files at the exact sizes, archive removed.
Task 13: fixed a bug found on the phone: during unpacking the banner said 'Downloading … 105 of 105 MB' (the per-MB throttle dropped the final done == total update) — test 'when the download is done it shows the full size while unpacking' RED→GREEN, suite green.
Task 13: on the M31 — once the model was ready, the 10 waiting recordings (13.9 min, mostly silence) were done in ~2.8 min (~5x real time, while a recording ran); owner's speech came out readable ('My name is Nishher. Who are you', 'This is the recording', 'Hello hello, hello', 'How are you', 'I am fine'); silent ones say 'No speech found in this recording.'
Task 13: on the M31 — live processing ran during a recording (processed_ms reached 180000 / 240000 while still recording); kill during Stop → reopened: recovered as 4:23, resumed from 4:00, done, attempts 0; tap a line → plays from 00:14 with the line in the accent colour.
Task 13: Ruling: lines appearing live with real speech not seen — the test voice from the PC speakers reached the mic at rms 164 (owner's speech 598) so the VAD found no speech; the live path is proven by processed_ms moving during the recording and the same save/watch path showing lines after Stop — to confirm with the owner speaking ~2 min — cost if wrong: live lines could fail to show while after-Stop lines work.
Task 13: memory idle (debug build) TOTAL PSS 438 MB; processing peak not measured (no speech job to run) — desktop speed test measured Parakeet at ~0.4 GB — to measure with the owner's spoken test.
Task 13: Ruling: minor visual found: the recording screen's title field shows the theme's filled box — deferred (cosmetic) — cost if wrong: none.
Task 13: fixed a race the full suite exposed: the processor loop used ref after being disposed mid-job — kick() drops errors only when the processor is gone; the final hide checks ref.mounted — test 'closing the app mid-job leaves no errors behind' RED→GREEN, backend suite 103 pass x3.
Task 13: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:04 +42: All tests passed!)
Final: Ruling: review package built from the working tree (review-working-tree.md: all 46 files Plan 2a created or changed) — nothing is committed — cost if wrong: none.
Final: review by a fresh reviewer (opus) on the working-tree package: 0 Critical, 5 Important, 11 Minor; verdict "with fixes".
Final: Ruling: M1 (settledMs up to ~0.3 s past a phrase still being confirmed: a resume at Stop/kill clips its first word) re-graded Minor → Important — it touches the live→after-Stop handover of every recording — cost if wrong: none.
Final: Ruling: M5 (double tap on Download → two downloads into one .part → corrupt, twice the data) re-graded Minor → Important — a plain double tap triggers it — cost if wrong: none.
Final: Ruling: M6 (Stop in the notification stopped the foreground service, then processing restarted it from the background, which Android 12+ may refuse) re-graded Minor → Important — stopping from the notification with the app closed is the main way to stop — cost if wrong: none.
Final: Ruling: I5 (spec's "Plug in to continue" notification missing; nothing keeps the app alive while waiting) fixed per spec (the plan had dropped it) rather than deferred — the spec is binding — cost if wrong: the waiting notification counts toward Android 15's 6 h/day dataSync limit.
Final: fixed I1 (engine failure/isolate death: recording stuck 'processing' or wrongly 'speech_crashed'; a dead engine hung all processing) — SpeechEngineFailed; isolate onError/onExit become failed replies; worker catches and replies; processor catches any error (unless disposed) — tests 'an engine that fails to start marks the recording failed and the next one still runs', 'an engine that cannot start reports SpeechEngineFailed' RED→GREEN, suite 119/119 + 42/42.
Final: fixed I2 (battery/charging/heat only checked between recordings) — the job re-decides after each chunk; on wait or fewer threads it stops at the last saved line (attempts cleared) and the loop resumes — tests 'the battery dropping mid-job pauses it, and charging resumes from there', 'a phone getting warm mid-job carries on with 2 threads' RED→GREEN.
Final: fixed I3 (a stalled download hung for ever, no Try again) — 30 s read timeout on response and body, TLS handshake timeout (raw socket destroyed on failure), any error ends the download as failed — tests 'a download that stalls fails as network and keeps what it got', 'any error during the download ends in failed, not stuck downloading' RED→GREEN; real GitHub HTTPS download re-checked.
Final: fixed I4 (unpack could run out of storage with a wrong message; temp files left; a kill during unpack re-downloaded 104 MB) — an archive already downloaded is reused; the archive is deleted once its tar is written (peak ~265 MB); the tar is always removed; a damaged archive is dropped; a full disk says storage_low — tests 'an archive already downloaded is not downloaded again', 'a full disk while unpacking says storage_low', 'a damaged archive fails as corrupt and leaves no temporary files' RED→GREEN.
Final: fixed I5 — waiting for charge/cool keeps a notice up ('Plug in to continue' / 'Waiting for the phone to cool down') — tests 'waiting for charge keeps a Plug in to continue notification up', 'waiting for charge says Plug in to continue' RED→GREEN.
Final: fixed M1 — while speech isn't confirmed, settled stays back 2 windows + 0.25 s — real-model test 'settled never passes the start of a phrase still being confirmed' RED (1792 > 1542) → GREEN.
Final: fixed M5 — 'downloading' is set before the first await — test 'a double tap on Download downloads once' RED→GREEN.
Final: fixed M6 — the recorder hands over (recordingStopped(title) → the processing notice goes up at once) before hiding its notification — tests 'processing takes over the notification before the recording one goes', 'a stopped recording shows the processing notice at once' RED→GREEN; on the M31: Stop from the notification → notification switched to processing and was removed when done (48 s in ~10 s), no service stop in between.
Final: suites after the fix pass: backend 119/119 (real models on), frontend 42/42, analyze clean in both.
Final: Ruling (declined: Hindi/Gujarati, speakers, summary/tasks, calls) — later plans — cost if wrong: none.
Final: Ruling (declined: the time estimate before starting, from this phone's measured speed) — not in 2a; the running estimate shows during a job — cost if wrong: no estimate before a job starts.
Final: Ruling (declined: word highlighting, FLAC, full first start, speaker/index columns, 'step 2 of 4') — deferred by the plan to later plans — cost if wrong: none.
Final: Ruling (declined: dataSync vs mediaProcessing type) — dataSync covers local file processing — cost if wrong: none.
Final: Ruling (declined: APK size, title field's filled box, battery broadcasts kicking often, percent on the line vs the badge) — later/cosmetic — cost if wrong: none.
Final: Ruling (declined: Plan 1 code beyond its 2a connections, iOS) — out of scope — cost if wrong: none.
Final: minor (deferred): M2 the live engine (~200 MB) stays loaded while processing waits (low battery, heat, model missing).
Final: minor (deferred): M3 any interrupted job counts toward speech_crashed, even one that made progress (clear attempts when processedMs moves).
Final: minor (deferred): M4 a kick() landing between the last _again check and _busy = false is lost until the next battery event.
Final: minor (deferred): M7 recording starts the service with dataSync too (Android 15's 6 h/day dataSync limit could end a very long day's recording service).
Final: minor (deferred): M8 SherpaSpeech.close() frees native memory only because the worker handles 'close' before the kill (0/200 lost on the PC); reply-after-free would make it certain — to watch on the phone over several jobs.
Final: minor (deferred): M9 processing starts only because the Record screen watches processorProvider (watch it from the app root).
Final: minor (deferred): M10 Settings deletes the 105 MB model without asking; the 300 MB check is MiB while texts are decimal MB.
Final: minor (deferred): M11 test gaps: no processor-level resume from an earlier settledMs; no test with an engine that hangs mid-request.
Final: on the M31 the owner's own speech transcribed well ('Mike testing one, two, three', 'I get it. We have to do this task then we will complete it'). Still open: lines appearing live in a recording over a minute with speech, and peak memory while processing.
After Plan 2a (owner's request, 2026-10-13): fixed the recording screen's title — the theme's filled, outlined field (its enabledBorder overrides border: none) made the title a box with the status tag touching it; now a plain heading with 8 px before the date/tag row — test 'the status tag sits below the title, which reads as a heading, not a box' RED (tag top 132 = title bottom 132) → GREEN, frontend 43/43; checked on the M31.
After Plan 2a (owner's request, 2026-10-13): the app is portrait only — MainActivity android:screenOrientation="portrait", SystemChrome.setPreferredOrientations([portraitUp]) at start (keepPortrait() in lib/ui/app.dart), iOS Info.plist portrait only on iPhone and iPad (+ UIRequiresFullScreen) — tests 'the app stays in portrait', 'on iOS too: portrait only, on iPhone and iPad', 'the app asks for portrait only' RED→GREEN, frontend 46/46; on the M31 with the phone forced to landscape the app stayed in portrait (rotation 0); the phone's rotation settings were restored.
