# SDD ledger — plan: docs/superpowers/plans/2026-10-15-mobile-plan-3-speakers.md

Spec: docs/superpowers/specs/2026-10-14-mobile-next-features-design.md Part C (approved 2026-10-14); owner's go-ahead 2026-10-15 (item 1 of his list).
Setup: Ruling: main working tree, no branch, no commits (owner commits at the end) — cost if wrong: all of 2b/2c-a/fixes/3 uncommitted together. BASE b1cd987.
Setup: the measurements behind the plan's numbers (PC, 2026-10-15, scratchpad spk/probe_spk.py): CAM++ zh_en advanced vs en_voxceleb on a David/Zira conversation (17 VAD phrases for 12 turns, some turns merged) and the owner's rec2/16/17 — zh_en: same voice ≥0.33, other ≤0.31, 100% of speech time at distance 0.6–0.7, owner-vs-owner ≥0.33 vs owner-vs-TTS ≤0.15; en_voxceleb: overlapping (97%).

## Pre-flight (shared interfaces)
| Producer → consumer | Found |
|---|---|
| T1 → T2/T4 `SpeechSetup.speakers`, `ModelId.speakers`, schema 5 | consistent (T2 adds its line columns in the same schema 5) |
| T2 → T3/T4 `VoicePiece`, `Phrase.voices`, print helpers | consistent |
| T3 → T4/T6 `groupSpeakers`, `SpeakerResult`, `SpeakerGroup`, `KnownVoice`, `Phrase.speaker/speakerGroup` | consistent |
| T4 → T5/T6/T7 `SpeakersRepository`, tables | consistent |
| T5 → T7 `VoiceTraining`, `myVoiceProvider` | consistent |
Pre-flight: Ruling: schema 5 is one migration covering T1's and T2's and T4's columns/tables (one version bump for the plan) — cost if wrong: none.
Task 1: Ruling: SpeechSetup.parse with no languages now still keeps the 'speakers' flag (it returned the englishOnly constant before) — cost if wrong: none. Four older tests turned speakers off (they test languages) or expect it on by default (the recorder test).
Task 1: complete (commits b1cd987..b1cd987, tests: bash -c 'cd mobile/backend && flutter test && flutter analyze && cd ../frontend && flutter test && flutter analyze' → No issues found! (ran in 5.1s))
Task 2: Ruling: printPieces works in ms (the engine converts to samples), and the plan's 4000 ms example had a 250 ms tail, under the 300 ms rule — the test uses 4200 ms for the tail case and 4000 ms for the no-tail case — cost if wrong: none.
Task 2: complete (commits b1cd987..b1cd987, tests: bash -c 'cd mobile/backend && flutter test && flutter analyze && cd ../frontend && flutter test && flutter analyze' → No issues found! (ran in 6.2s))
Task 3: complete (commits b1cd987..b1cd987, tests: bash -c 'cd mobile/backend && flutter test && flutter analyze && cd ../frontend && flutter test && flutter analyze' → No issues found! (ran in 5.0s))
Task 4: complete (commits b1cd987..b1cd987, tests: bash -c 'cd mobile/backend && flutter test && flutter analyze && cd ../frontend && flutter test && flutter analyze' → No issues found! (ran in 5.6s))
Task 3: Ruling: a speaker change inside a phrase is put halfway between the middles of the last window of one group and the first of the next; each word goes to the window whose middle is nearest its own (the plan's "A, A, B, B" example puts "four" with B) — cost if wrong: a word at a change can land on the other side.
Task 3: Ruling: lines too short for a print (< 400 ms) take the speaker nearest in time (desktop speaker_at), and don't count toward a group's speech time; groups under 1.5 s join the group nearest their voice (the desktop goes by time) — cost if wrong: a short reply ("Fine.") between the other person's lines gets their name (seen once in the two-voice test).
Task 3: Ruling: a line cut in two keeps its id on the first part; the parts after it are new lines — cost if wrong: none.
Task 4: Ruling: the speech engine is closed before the speakers step (frees its memory); grouping runs in Isolate.run — cost if wrong: none.
Task 4: Ruling: the processing line says "Finding who said what in “<title>”" during the step (not in the spec's wording list) — cost if wrong: one string.
Task 4: Real model (PC): the David/Zira conversation, 17 lines, 98.8% of 30.5 s right; the one miss is "Fine." (358 ms, no print).
Task 4: Process: dart format (the SDK's new tall style) re-laid untouched code in 9 files; rebuilt from the session log (pre-edit copies + replayed edits, tokens checked equal) — formatter no longer used (memory no-dart-format).
Task 5: complete (commits b1cd987..b1cd987, tests: bash -c 'cd mobile/backend && flutter test && flutter analyze && cd ../frontend && flutter test && flutter analyze' → No issues found! (ran in 5.9s))
Task 5: Ruling: the speakers model doesn't declare the VAD as a need (deleting it would then delete the VAD); the training screen downloads whichever of the two is missing — cost if wrong: none.
Task 5: Ruling: training checks the recorder is idle (the microphone is the recording's) and says "Stop the recording first…"; other non-spec strings: "Voice Desk learns your voice from a short reading, so your lines show as Me.", "Voice Desk needs the microphone to hear you. Allow it in Settings.", "Your voice couldn't be learned. Try again." — cost if wrong: strings.
Task 5: Ruling: the Settings row "Your voice" sits under the words card for now; Task 7's People screen puts it at the top there too — cost if wrong: none.
Task 5: Real model (PC): trained from rec2's first 25 s (11.96 s of speech); rec16's 4 lines all "Me"; the David/Zira conversation has no "Me".
Task 6: complete (commits b1cd987..b1cd987, tests: bash -c 'cd mobile/backend && flutter test && flutter analyze && cd ../frontend && flutter test && flutter analyze' → No issues found! (ran in 7.2s))
Task 6: Ruling: remembering takes the group's lines in time order until 30 s of line time (pieces weighted by their length); under 2 s → NotEnoughSpeech before anything changes. The sheet greys out "Recognise this voice…" with the 2 s message instead of failing after Rename — cost if wrong: none.
Task 6: Ruling: a remembered name merges by lowercase key and takes the newest spelling; speech times add up — cost if wrong: the name's case.
Task 6: Ruling: the rename sheet starts empty for "Person N" (else the current name); typing "Me" says "Me is you: type their name"; a done recording whose speakers step failed shows "Couldn't tell who said what in this recording." (both not in the spec's list) — cost if wrong: strings.
Task 7: complete (commits b1cd987..b1cd987, tests: bash -c 'cd mobile/backend && flutter test && flutter analyze && cd ../frontend && flutter test && flutter analyze' → No issues found! (ran in 7.4s))
Task 7: Ruling: "Said by…" shows on lines that have a speaker (recordings made with speaker detection); a remembered person or a typed name that matches one of the recording's speakers joins that group, otherwise the line gets the name with no group (so renaming a group doesn't touch it) — cost if wrong: a moved line not following a later rename.
Task 7: Ruling: Settings has one "People" row (subtitle "Your voice, and the voices recognised in recordings"); the People screen has Your voice at the top, then "Recognised in new recordings" with Rename/Forget; empty: "No one yet. Tap a speaker's name in a recording, rename them and tick …"; the Someone else dialog is titled "Said by" with Save — cost if wrong: strings.
Task 7: Ruling: renaming a person to a name already remembered makes them one (prints averaged by speech time), as remembering does — cost if wrong: none.
Final review (2026-10-15, one reviewer over all of Plan 3): 0 Critical, 3 Important, 5 Minor; all fixed:
- I1 the microphone stayed on when the training screen closed mid-reading (ref.read after dispose threw inside the swallowing catch) → the notifier keeps its AudioSource and checks ref.mounted after each await; test "closing the screen mid-reading turns the microphone off".
- I2 no Retry for a failed speakers step (spec C1) → "Try again" under the note calls retry(id); the job finds processedMs == total and reruns only the speakers step (processor test).
- I3 the screen's transcript query decoded every voice print on every change → watch() leaves voices out; linesForGrouping reads them.
- M4 Someone else… keeps the speaker's spelling when the typed name is one of them; M5 NotEnoughSpeech after Said-by moves → renamed without remembering, and said why; RecordingGone caught; M6 a remembered "Person N" no longer collides (numbers skip taken names); M7 spec wording restored: "Type a name" for "Me", and the training button itself reads "Keep reading…" until 8 s; M8 Back waits while the voice is worked out (PopScope).
- Tests added: re-run brings remembered voices back; deleted during the speakers step; every group under 1.5 s; one-word long line; three voices.
After fixes: backend 279 passed (+10 real-model skipped; those 3 speaker real-model tests pass with env), frontend 105, analyze clean.
Task 8: Step 1–2 NOT DONE: the phone dropped off Wi-Fi debugging before the install (release APK 48.1 MB built); the two-voice phone check needs the owner (audio played near the phone). Step 3 (docs) done.
Task 8 (2026-10-16, M31, release build over Wi-Fi debugging): the speaker model downloaded from the first-start setup (after the INTERNET fix, see the 2c-b ledger). Process again on the 14:56 stage clip (compressed): 78 s, lines named Person 1/2/3, a two-voice line split at the change. The David/Zira conversation played from the phone's own speaker (the PC's speakers were too far: only the last line was heard): every line went to the right voice except one word ("plan?") on the wrong side of a split; Rename → David / Zira with "Recognise this voice" both remembered; a second recording of it came out named David and Zira by itself, every line right. Training "Me" needs the owner's voice (checked on the PC with rec2). Speech side note: with Hindi ticked, short English words came out in Devanagari ("Great" → "क्वेट", "Okay" → "ओका", "Right" → "वाइट", "agreed" → "अकमेद") — a Plan 2b mixing matter, reported to the owner.
Task 8: complete (phone checks above; docs updated).
