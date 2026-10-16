# Mobile Plan 2c-a — progress ledger

Plan: [2026-10-14-mobile-plan-2c-transcript-tools.md](2026-10-14-mobile-plan-2c-transcript-tools.md). One line per decision ("Ruling") and per finished task. **Plan 2c-a is complete** (2026-10-14): 7 tasks, final review, fix pass. "commits b1cd987..b1cd987" means nothing was committed (the owner commits later).

Spec: docs/superpowers/specs/2026-10-14-mobile-next-features-design.md (B1, B3, B6 models part, B9), owner's go-ahead 2026-10-14 ("complete 1-4 first and add 5 in future plans").

Setup: Ruling: built in the main working tree, no branch, no commits (owner's standing rule; Plan 2b's changes are uncommitted in the same tree) — cost if wrong: 2b and 2c-a changes sit together uncommitted. BASE b1cd987.

## Pre-flight (shared interfaces)
| Producer → consumer | Produces / consumes | Found |
|---|---|---|
| T1 → (none) | `YourWords.aliases`, `Vocabulary.fromSettings(aliases:)` | self-contained |
| T2 → T3 | `Phrase.id`, `editLine(lineId, text)`, `LineGone` | consistent |
| T4 → T5 | `Processor.processAgain(int id, SpeechSetup setup)`, `Recording.reprocessing` | consistent |
| 2b → T6 | `modelsProvider`, `neededModelIdsProvider`, `Models.bytesToDownload`; T6 adds `Models.bytesOnDisk` | consistent |
Pre-flight: no conflicts.
Task 1: complete (commits b1cd987..b1cd987, tests: bash -c 'cd mobile/backend && flutter test && flutter analyze && cd ../frontend && flutter test && flutter analyze' → No issues found! (ran in 3.1s))
Task 2: complete (commits b1cd987..b1cd987, tests: bash -c 'cd mobile/backend && flutter test && flutter analyze && cd ../frontend && flutter test && flutter analyze' → No issues found! (ran in 2.6s))
Task 3: Ruling: saving a line whose text is unchanged does nothing (no write) — nothing to fix — cost if wrong: none. Task 3: the dialog owns its text controller (_FixWordsDialog): disposing it when showDialog returned crashed while the dialog was still closing.
Task 3: complete (commits b1cd987..b1cd987, tests: bash -c 'cd mobile/frontend && flutter test && flutter analyze' → No issues found! (ran in 2.6s))
Task 4: found by the old version-1 migration test: from version 1 the lines table is created with the current columns, so adding `draft` again failed (duplicate column) — the column is added only when upgrading from version 2 or later.
Task 4: complete (commits b1cd987..b1cd987, tests: bash -c 'cd mobile/backend && flutter test && flutter analyze && cd ../frontend && flutter test && flutter analyze' → No issues found! (ran in 2.7s))
Task 5: complete (commits b1cd987..b1cd987, tests: bash -c 'cd mobile/frontend && flutter test && flutter analyze' → No issues found! (ran in 2.6s))
Task 6: Ruling: "in use right now" = a recording with status `recording` in the list, or the processor working on a recording — read from `recordingsProvider` and `processorProvider` rather than `recorderProvider` (whose real notifier the Storage screen would otherwise build) — cost if wrong: none (the same two conditions).
Task 6: Ruling: the size freed is the model's own files (`bytesOnDisk`); deleting the last Indian model also removes the 68 kB shared tokens, not counted in the message — cost if wrong: the message is 0.07 MB low.
Task 6: note: the speech-card green-tag test ran in the same RED run as the Storage tests, whose file didn't compile; it pins the tag kind and that only the downloaded model shows it.
Task 6: complete (commits b1cd987..b1cd987, tests: bash -c 'cd mobile/backend && flutter test && flutter analyze && cd ../frontend && flutter test && flutter analyze' → No issues found! (ran in 2.7s))
Task 7: Step 1: the app's foreground service was not running (no recording/processing) → debug build installed on the M31 (pm install -r: Success).
Task 7: Step 2 by screenshots: Settings shows "Other names people call you"; Speech → Accuracy rows show green "Downloaded" tags (the owner had already chosen More accurate and downloaded it and Hindi); Settings → Storage lists the 5 models, all with green "Downloaded" tags (1194 MB, 28.0 GB free); a recording: long-press → "Fix the words" → its dialog (cancelled); the ↻ button → the Process again dialog with More accurate and the recording's languages pre-set (cancelled). Nothing of the owner's was changed: no line edited, no re-run started (the owner's recordings, not test data).
Final review (fresh reviewer, opus): With fixes — I1 a re-run waiting for a missing model can't be changed or cancelled (↻ only for done/error; the dialog doesn't say a download is needed); I2 Storage rows lack the spec's "Not used by your settings" note; minors 3–10.
Final: Ruling: minor #4 (the delete dialog says a model "downloads again by itself" / "before then", but nothing downloads by itself — the banner waits for a tap) re-graded Important: it misinforms the owner about what deleting does — enters the fix pass with new wording (the plan's exact strings change).
Final: fixed I1 (a re-run waiting for a missing model could be neither changed nor restarted): ↻ is offered for done, failed, queued and waiting-for-charge recordings that aren't the one being processed, and the dialog names what the chosen run must download ("Downloads 482 MB first.") — tests `Process again names what it must download first` and `a recording waiting to be processed can be processed again with other choices` RED → GREEN; backend `a re-run waiting for a model can be started again with other choices` passed before the fix (the backend always allowed it; only the screen blocked it); suites backend 226/226 (+6 skipped), frontend 76/76.
Final: fixed I2 (Storage rows lacked the spec's "Not used by your settings"): a downloaded model that neither the settings nor a waiting recording need shows "X MB · Not used by your settings" — test `a model the settings don't use says so` RED → GREEN. Ruling: a note in the subtitle rather than a second badge beside the green "Downloaded" tag (narrow phone rows) — cost if wrong: none.
Final: fixed #4 (the delete dialog promised downloads that don't happen by themselves): "Frees X MB. You can download it again here." / "Frees X MB, but the speech settings or a recording waiting to be processed need it: they wait until it is downloaded again." — the two Delete tests updated first (RED) → GREEN.
Final: the screen now watches processorProvider; two older recording-screen tests gained the IdleProcessor override, and the screen tests build a fresh FakeModels per test (a notifier instance can't be shared between scopes).
Final: minor (deferred): #3 Storage's in-use check runs before the confirm dialog, not again after Delete is pressed.
Final: minor (deferred): #5 a failed re-run shows "Couldn't turn this into text." above the complete old transcript; fixes made after the failure are replaced when Try again succeeds.
Final: minor (deferred): #6 an edited line can keep newlines in its text (the words don't).
Final: minor (deferred): #7 Storage's free-space header isn't refreshed after a delete/download.
Final: minor (deferred): #8 Process again's Faster/More accurate choice stays active with English unticked.
Final: minor (deferred): #9 test gaps: the Settings → Storage tile, long-press on a word, deleting while a recording is in progress.
Final: minor (deferred): #10 the spec's `transcript_lines.edited` column isn't in schema 4 (nothing needs it yet).
Final: note for Plan 2c-b (FLAC, keep N days): a re-run of a recording with no audio would commit an empty transcript — refuse to commit with no audio and disable Process again for text-only recordings; consider ordering re-runs after first runs in the queue.
Final: Ruling (declined-to-judge list): Plan 2a/2b behaviour (threads during a new recording, Leave out dropping confidences, transcriptProvider lifetime), the plan's excluded items, plan-vs-desktop wording, the phone screenshots, onnxruntime file handling on delete — all stand as set aside — cost if wrong: none now.
