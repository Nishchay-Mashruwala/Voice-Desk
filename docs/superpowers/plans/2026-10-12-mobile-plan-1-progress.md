# Mobile Plan 1 — progress ledger

Plan: [2026-10-12-mobile-plan-1-recording.md](2026-10-12-mobile-plan-1-recording.md). One line per decision ("Ruling") and per finished task, written while building. **Plan 1 is complete** (2026-10-13): all 10 tasks, final review, fix pass.

Since 2026-10-13 the code is split: `mobile/lib/data` and `mobile/lib/engine` are in `mobile/backend/lib/`, `mobile/lib/ui` and `android/` are in `mobile/frontend/`. Paths in the early lines are the old ones. "commits 8f0f01d..8f0f01d" means nothing was committed (the owner commits later).

Setup: Ruling: no new worktree; work in the current tree on branch restructure-frontend-backend — owner forbids commits and mobile/ is untracked, so a worktree (cut from a commit) would not contain it — cost if wrong: none, nothing is committed.
Setup: Ruling: plan "commit" steps are checkpoints (flutter analyze + flutter test) — owner's standing rule "don't commit until asked" — cost if wrong: owner commits later.
Setup: spec read: docs/superpowers/specs/2026-10-12-mobile-app-design.md
Pre-flight: T2→T3 wavHeader/finalizeWav/kBytesPerSecond: consistent.
Pre-flight: T2→T4 finalizeWav/wavDuration used by recoverInterrupted: consistent.
Pre-flight: T3→T6 PieceWriter(dir,{pieceBytes}).add/close/dataBytes: consistent.
Pre-flight: T4→T6 RecordingsRepository.create/audioDir/finish/delete: consistent.
Pre-flight: T5→T6 FreeSpace.bytesFree, canStartRecording, mustStopRecording: consistent.
Pre-flight: T4,T6→T7 recordingsProvider, RecordingStatus, recorderProvider/RecorderState, settingsRepositoryProvider: consistent.
Pre-flight: T4→T8 get/pieces/rename/delete: consistent.
Pre-flight: T4→T9 recoverInterrupted: consistent.
Task 1: Ruling: permission_handler ^12.0.1 instead of 13.0.2 — 13.x needs compileSdk 37, beyond this Flutter/AGP 9.1 setup (max 36) — cost if wrong: upgrade later when Flutter moves to SDK 37.
Task 1: complete (commits 8f0f01d..8f0f01d, tests: flutter test → 00:01 +1: All tests passed!)
Task 2: complete (commits 8f0f01d..8f0f01d, tests: flutter test → 00:02 +4: All tests passed!)
Task 3: complete (commits 8f0f01d..8f0f01d, tests: flutter test → 00:02 +7: All tests passed!)
Task 4: complete (commits 8f0f01d..8f0f01d, tests: flutter test → 00:02 +18: All tests passed!)
Task 5: complete (commits 8f0f01d..8f0f01d, tests: flutter test → 00:03 +21: All tests passed!)
Task 6: Ruling: stop() waits at most 2 s for the microphone stream to end — guards against a device whose record stream never closes; not unit-tested (fake closes) — cost if wrong: a few trailing ms of audio lost on such devices; Task 10 checks the real plugin.
Task 6: Ruling: app label set to "Voice Desk" in the manifest (was "mobile") — spec's app name — cost if wrong: none.
Task 6: Ruling: added tests 'elapsed follows the audio written' and 'a second start while recording is ignored' beyond the brief — behaviours the controller has to get right — cost if wrong: none.
Task 6: complete (commits 8f0f01d..8f0f01d, tests: flutter test → 00:02 +29: All tests passed!)
Task 7: Ruling: PermissionsStatus (Task 9's interface) created in Task 7 at lib/engine/permissions.dart, plus openSettings() — the battery dialog and "Open settings" need it now; Task 9 reuses it — cost if wrong: none (same interface).
Task 7: Ruling: placeholder RecordingDetailScreen so the list's tap compiles; Task 8 replaces it — cost if wrong: none.
Task 7: Ruling: SnackBar persist:false — Flutter 3.47 keeps SnackBars with an action until tapped, so swipe-deletes would never complete (caught by the 'without Undo' test) — cost if wrong: none.
Task 7: Ruling: notifications permission requested before the first recording if not granted (Android 13+) — spec: permissions asked when first needed — cost if wrong: one extra prompt.
Task 7: complete (commits 8f0f01d..8f0f01d, tests: flutter test → 00:05 +36: All tests passed!)
Task 8: Ruling: player position across pieces = start of current piece (from wavDuration) + position in it; seek maps back to (piece, offset) — just_audio reports per-item positions — cost if wrong: seek bar off at piece edges; checked on device in Task 10.
Task 8: Ruling: status shown as its own Chip next to the date — test finds the status text on its own — cost if wrong: none.
Task 8: complete (commits 8f0f01d..8f0f01d, tests: flutter test → 00:05 +39: All tests passed!)
Task 9: Ruling: added package_info_plus (10.2.2) for the About row's version — the plan's "app version" needs it — cost if wrong: one small dependency.
Task 9: Ruling: main() stops a leftover recording notification at start — a killed app can leave the foreground service's notification behind while nothing records — cost if wrong: none.
Task 9: complete (commits 8f0f01d..8f0f01d, tests: flutter test → 00:06 +40: All tests passed!)
Extra (owner request 2026-10-12): app icon — adaptive launcher icon from the desktop icon (gradient background + mic foreground in the safe zone), legacy PNGs, white status-bar mic (res/drawable/ic_notification.xml, meta-data com.rajvee.mobile.NOTIFICATION_ICON); checked on the phone. flutter test 40/40, analyze clean.
Task 10: IN PROGRESS — done on the M31: screen-off recording, notification icon/text, Pause/Resume/Stop from the notification, pieces on disk (1,920,044 B each), kill/reinstall recovery (5:13 kept). Open: playback (Play + seek left 00:00, no app logs — investigate player.dart / tap), rename + blank rename, delete + Undo on the phone. Finding: title field not cleared when stopping from the notification (RecordScreen).
Resume: Ruling: workspace re-created from docs/superpowers/plans/2026-10-12-mobile-plan-1-progress.md (owner had .superpowers/ deleted) — the skill's scripts need it; copied back to docs and deleted again at the end — cost if wrong: none.
Resume: Ruling: code moved 2026-10-13 — tests run in both mobile/backend and mobile/frontend; task-done runs both — cost if wrong: none.
Task 10: fixed playback dead on the phone — playerProvider is autoDispose and the detail screen only read it, so its player was disposed at once and each tap made a new one (seen in logcat); screen now holds it with ref.listenManual — test 'one player lives as long as the screen and its position is shown' RED→GREEN.
Task 10: fixed Pause button staying after the end (just_audio keeps playing=true when completed) — JustAudioPlayer pauses and seeks to the start at the end — test 'at the end it stops and goes back to the start, so Play plays it again' RED→GREEN.
Task 10: fixed time after a seek into another piece (just_audio reports the new position with the old index; its position stream drops repeats) — position computed in JustAudioPlayer from position + index, using the seek's target piece while seeking — tests 'seeking into the second piece shows the time within the whole recording' RED→GREEN, 'a seek that finishes after the screen closed is ignored' RED→GREEN. Closes Task 8's ruling (seek bar at piece edges).
Task 10: fixed title not cleared when stopped from the notification — RecordScreen clears it whenever the recorder goes back to idle — test 'the title is cleared when the recording stops from the notification' RED→GREEN.
Task 10: Ruling: just_audio_platform_interface added as a dev dependency of mobile/backend — the player tests replace the Android plugin with a fake — cost if wrong: none (test only).
Task 10: Ruling: delete checks used recordings made during the test (Delete me 1/2 and two untitled 00:02 ones); the owner's recordings (16:25, 16:29 Meeting, 16:32) untouched; 16:52 renamed and blank-renamed back to its default title — cost if wrong: none.
Task 10: on the M31 — playback across pieces (01:32 shown in piece 2), end resets to Play 00:00, paused seek shows 01:29, rename, blank rename → default title, notification Stop clears the title, swipe delete + Undo keeps it, swipe delete without Undo deletes it, detail delete removes its folder.
Task 10: Ruling: end-of-playback test waits until the fake platform has received play (and the reset seek) instead of a fixed event-queue pump — it raced under the parallel full run (calls were load, pause, seek); still fails without the fix (checked) — cost if wrong: none (test only).
Task 10: complete (commits 8f0f01d..8f0f01d, tests: bash C:/Users/Rajvee/AppData/Local/Temp/claude/c--Users-Rajvee-Desktop-Coding-Voice-Desk-Project/028f0d1a-d65f-4f78-b791-a71b741fab38/scratchpad/mobile-tests.sh → 00:03 +14: All tests passed!)
Final: Ruling: review package built from the working tree (review-working-tree.md: all Plan 1 sources, tests, pubspecs, Android files) instead of review-package — nothing is committed (owner's rule), so there is no commit range — cost if wrong: none.
Final: review by a fresh reviewer (opus) on the working-tree package: 1 Critical, 4 Important, 12 Minor; verdict "with fixes".
Final: Ruling: M8 (Android Auto Backup on) re-graded Minor → Important — recordings and the database would be copied to the user's Google Drive, against the spec's "entirely on the phone"; fixed with android:allowBackup="false" (moving to a new phone by cable/Smart Switch still works) — cost if wrong: a user restoring from a Google backup gets no Voice Desk data back.
Final: Ruling: M7 (openBackend has no error handling) stays Minor — app-private files can't realistically become unreadable on Android, and a database fault breaks the app either way; recovery per recording would be the fix — cost if wrong: one corrupt recording could keep the app from opening until its data is cleared.
Final: fixed C1 (Back / swiping from Recents stopped the recording while the notification kept saying Recording; confirmed on the M31: 8 s of audio, notification frozen) — engine created in VoiceDeskApplication and cached, MainActivity uses it; allowAutoRestart false; a service restarted by Android stops itself — tests 'Android does not bring the service back after killing the app', 'a service restarted by Android stops instead of claiming to record' RED→GREEN, manifest test; on the M31: Back → still recording 45 s later, reopen shows the live recording, swiped from Recents → still recording (04:17→04:23), suite 43/43 + 24/24.
Final: fixed I1 (double tap while starting: mic left on or two rows) — RecorderPhase.starting set before the first await, Stop waits for a running start — tests 'Stop pressed while starting stops it once started…', 'two quick taps on Record make one recording' RED→GREEN, suite 43/43.
Final: fixed I2 (any audio-focus loss paused the recording for good; seen live on the M31 at 13:11:04, notification frozen at 00:47) — micConfig audioInterruption none — test 'other sounds … do not pause the recording' RED→GREEN; on the M31: playing another recording during a recording, it kept going (01:48→01:56).
Final: fixed I3 (a failed write/start left an unstoppable "Recording") — _write catches and stops with recording_failed; start undoes notification/mic/row and says start_failed; stream onError stops; stop() is best-effort and always ends idle; the real notification throws when the service doesn't start — tests 'the microphone failing to start…', 'the notification failing to start…', 'a failed write stops the recording and keeps what was saved' (also checked to fail without the fix), 'a microphone error stops the recording and keeps it', 'a notification service that does not start is reported' RED→GREEN, suite 43/43.
Final: fixed I4 (a live recording could be deleted/played from its detail screen) — Delete and Play disabled while status is recording — test 'a recording still in progress can be neither deleted nor played here' RED→GREEN, suite 24/24.
Final: Ruling: the Record screen clears the title only after a recording ran (recording/paused → idle), not after a start that didn't happen — the new starting phase would otherwise wipe the title when the microphone is refused — test 'the title stays when the recording could not start' RED→GREEN — cost if wrong: none.
Final: Ruling: pieceWriterProvider added (a seam) so a test can give a writer that fails — deleting the folder to make writes fail doesn't work on Windows (file locked) — cost if wrong: none.
Final: Ruling: stop() now also cancels the microphone subscription after the 2 s wait and guards the done-completer (part of M6) — it sits in the code I3 rewrote — cost if wrong: none.
Final: Ruling (declined: calls pause/resume, another app taking the mic) — Plan 5 as planned; with I2 fixed, a call no longer ends the recording (Android silences the mic during it) — cost if wrong: silence recorded during calls until Plan 5.
Final: Ruling (declined: processing line, transcript, speakers, summary, Share, Retry, Tasks tab, other Settings, first start, FLAC, delete after N days) — Plans 2–5 — cost if wrong: none, not built yet.
Final: Ruling (declined: Play policy for REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, release signing, R8) — distribution is later; run a release build on the M31 before relying on it — cost if wrong: a release build may need keep rules.
Final: Ruling (declined: iOS) — Android first per spec — cost if wrong: none.
Final: Ruling (declined: database migrations) — schema version 1; Plan 2 adds a MigrationStrategy when it moves to version 2 — cost if wrong: none now.
Final: Ruling (declined: TalkBack with the timed Undo SnackBar, localisation) — stands for version 1: Undo shows 5 s for everyone — cost if wrong: TalkBack users may miss Undo.
Final: Ruling (declined: Samsung sleeping-apps lists beyond Unrestricted, Doze over long recordings; battery/flash cost of flushing each chunk) — a 30-minute screen-off recording on the M31 is the check, to do with Plan 2's first long test — cost if wrong: long recordings cut off on some Samsung settings.
Final: Ruling (declined: visual design; files added during the review) — the PC-style look is the owner's approved next step, built after Plan 1 — cost if wrong: none.
Final: minor (deferred): M1 Settings "Allow" does nothing for a permanently refused permission (should open app settings).
Final: minor (deferred): M2 recorder messages never clear (e.g. "needs the microphone" after allowing it).
Final: minor (deferred): M3 microphone and notification permissions go straight to the system prompt without an explanation (spec: each explained).
Final: minor (deferred): M4 the whole Record screen rebuilds on every audio chunk and level poll.
Final: minor (deferred): M5 the slider seeks on every drag frame; seek on release instead.
Final: minor (deferred): M6 (rest) the old microphone/level subscriptions aren't cancelled at the next start.
Final: minor (deferred): M7 openBackend has no per-recording error handling (see ruling above).
Final: minor (deferred): M9 piece names sort as text after ~16.7 hours (piece-1000 before piece-101).
Final: minor (deferred): M10 some decisions still in screens (_askOnce, the detail screen loading pieces into the player, appVersionProvider in the UI, clock() in the notification file).
Final: minor (deferred): M11 a storage-full stop with the screen off leaves no notification saying so.
Final: minor (deferred): M12 some tests leave temporary folders behind.
Final: on the M31 after the fix pass — Back, reopen, play during recording, swipe from Recents all keep recording; a recording stopped normally afterwards. Test recordings left on the phone: 13:02 (00:08), 13:07 (00:06), 13:10 (00:47), 13:22 (04:34), 13:27 (short).
