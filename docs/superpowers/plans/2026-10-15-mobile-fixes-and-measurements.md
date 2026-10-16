# Mobile: fixes, smaller app, phone measurements (2026-10-15)

The owner's list of 2026-10-15, items 4–10, done first because they are small
(items 1–3 are speakers, summary and tasks, and the everyday tools; each gets
its own plan). Nothing committed: the owner commits at the end. Each fix had
a test that failed first.

## Fixes (items 5–9)

| Item | What was wrong | Fix | Test (RED → GREEN) |
|---|---|---|---|
| 5 | A shared download (the Hindi/Gujarati tokens) that failed in its own run was marked done by a model waiting on it; "done" came from the screen state, not the files | Download skips only when the files are on the phone; a waited-on part that isn't on the phone fails the download | `a shared part that failed in another download is not marked done`, `Download works again when the files are gone though it showed as done` |
| 6 | Storage checked "in use" only before the Delete question | Checked again after Delete is pressed | `processing that starts while Delete is being confirmed stops the delete` |
| 7 | A failed Process again said "Couldn't turn this into text." above the full earlier text | "Processing it again didn't finish. The text below is the earlier one; Try again continues where it stopped." | `a failed re-run says the text shown is the earlier one` |
| 8 | Storage's free space wasn't read again after a delete | Read again after each delete | `the free space shown is read again after a delete` |
| 9 | Process again's Faster / More accurate stayed active with English unticked | Off when English is unticked | `the accuracy choice is off when English is unticked` |

## Smaller app (item 10)

`flutter build apk --release --split-per-abi`: the phone's file
(`app-arm64-v8a-release.apk`) is **47.8 MB** (the debug build: 265 MB);
armeabi-v7a 37.5 MB, x86_64 52.9 MB.
- Release builds are still signed with the development key (Flutter's
  template). This lets them install over the test builds and keep the
  data.
- Publishing needs the owner's own key: a later step.
- **Found on 2026-10-16:** these release builds had no INTERNET permission. It
  was only in the debug and profile manifests, so no model could be downloaded.
  It is now in the main manifest, guarded by a test
  (`frontend/test/android_manifest_test.dart`).
- Split builds number versions per processor (arm64 = 2001…), so a debug
  build installs over a release one only with `pm install -r -d`.

## Measurements on the Galaxy M31 (item 4)

Release build, after Stop, 4 threads. The run is "Process again" on the
92 s Gujarati Test recording (recorded from the PC's speakers). Times
include loading the models (~8–10 s).

| Setup | Time | Peak memory (PSS) | Memory after |
|---|---|---|---|
| Faster, English + Gujarati | 58 s | 0.79 GB | 0.19 GB |
| More accurate, English + Gujarati | 93 s | 1.38 GB | 0.20 GB |
| More accurate, English + Hindi + Gujarati | 94 s | 1.33 GB | 0.20 GB |

On this phone, then:
- English + Gujarati runs at about 0.55× real time with Faster (~16 min
  for 30 min of audio) and about 1× with More accurate.
- Live processing during the meeting does part of it before Stop.
- Both above the speed book's starting estimates (0.37× / 1.1×); the app
  learns the real figure after the first job over a minute.

## Two bugs found while measuring

1. **The models' memory stayed with the app after every job.**
   - First measurements read 2.0 and 3.3 GB, and 2.7 GB with the app idle,
     much of it swapped.
   - Cause one: `SherpaSpeech.close()` sent "close" and killed the isolate
     at once, often before it freed the models.
   - Cause two: once freed, the allocator kept the memory (Native Heap
     822 MB, 40 MB in use).
   - Fixed:
     - the isolate frees its models and answers "closed" before it ends;
     - the app then asks the allocator (bionic `mallopt(M_PURGE)`) to hand
       freed memory back.
   - Checked on the M31: idle 0.19–0.20 GB after each job. A real-model
     test on the PC: 4 jobs in a row add 1 MB.
2. **A black screen when the app was opened after an update (and likely
   after a phone restart).**
   - flutter_foreground_task's RebootReceiver (BOOT_COMPLETED,
     MY_PACKAGE_REPLACED) starts the app's process in the background. Our
     Application then starts the Flutter engine, which runs `main()` with
     no window.
   - `keepPortrait()` (SystemChrome) is never answered without a window,
     and `main()` awaited it, so `runApp` never ran.
   - Fixed: start-up moved to `startApp()`, which doesn't wait for the
     portrait lock (the manifest keeps portrait). Test
     `the app starts even when the portrait lock is never answered`
     (timed out → passes).
   - Checked on the M31: updated while running (process restarted in the
     background), then opened: the screen shows.

Suites after all of this: backend 235 (real models included), frontend 81;
analyze clean.
