import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/data/transcript_repository.dart';
import 'package:mobile_backend/engine/audio/compress.dart';
import 'package:mobile_backend/engine/audio/flac.dart';
import 'package:mobile_backend/engine/audio/pcm_reader.dart';
import 'package:mobile_backend/engine/audio/wav.dart';
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/downloader.dart';
import 'package:mobile_backend/engine/models/model_store.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/pipeline/conditions.dart';
import 'package:mobile_backend/engine/pipeline/processing_notice.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/pipeline/speed_book.dart';
import 'package:mobile_backend/engine/speakers/grouping.dart';
import 'package:mobile_backend/engine/speakers/voice_print.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/speech/speech_to_text.dart';
import 'package:mobile_backend/engine/speech/vocabulary.dart';
import 'package:mobile_backend/engine/speech/your_words.dart';
import 'package:mobile_backend/engine/tasks/llm_engine.dart';
import 'package:mobile_backend/engine/tasks/task_settings.dart';

/// Says one phrase per pushed chunk ("words 20000"), or nothing when [silent].
class FakeSpeech implements SpeechToText {
  FakeSpeech(this.startMs, this.threads, this.script);
  final int startMs;
  final int threads;
  final Script script;
  late int _at = startMs;
  int pushes = 0;
  final pushedFrom = <int>[];

  @override
  Future<Transcribed> push(Float32List samples) async {
    pushes++;
    pushedFrom.add(_at);
    await script.onPush?.call(this);
    if (script.failOnPush == pushes) throw Exception('engine crashed');
    final end = _at + samples.length * 1000 ~/ 16000;
    final text = script.say ?? 'words $_at';
    final print = script.voiceOf?.call(pushes);
    final phrases = script.silent
        ? <Phrase>[]
        : [
            Phrase(
              startMs: _at,
              endMs: end,
              text: text,
              words: [for (final w in text.split(' ')) Word(w, _at, end)],
              voices: [if (print != null) VoicePiece(_at, end, print)],
            ),
          ];
    _at = end;
    return Transcribed(phrases, end);
  }

  @override
  Future<Transcribed> finish() async => Transcribed(const [], _at);

  @override
  Future<void> close() async {}
}

class Script {
  bool silent = false;

  /// What each pushed chunk "says" (default: `words <ms>`).
  String? say;
  int? failOnPush;
  Future<void> Function(FakeSpeech s)? onPush;

  /// The voice print of each push's phrase (1, 2, …); none when null.
  Float32List? Function(int push)? voiceOf;

  /// The speakers step fails.
  bool failGrouping = false;

  /// Runs as the speakers step starts.
  Future<void> Function()? onGrouping;

  /// Runs as a recording's audio starts being compressed.
  Future<void> Function()? onCompress;
}

/// Two voices, far apart.
final voiceA = Float32List(8)..[0] = 1;
final voiceB = Float32List(8)..[1] = 1;
Float32List? aThenB(int push) => push.isOdd ? voiceA : voiceB;

const withSpeakers = SpeechSetup(languages: {Lang.en}, speakers: true);

class FakeDevice implements DeviceState {
  int level = 80;
  bool plugged = false;
  int heat = 0;
  final _changes = StreamController<void>.broadcast();
  void plugIn() {
    plugged = true;
    _changes.add(null);
  }

  @override
  Future<int> battery() async => level;
  @override
  Future<bool> charging() async => plugged;
  @override
  Future<int> thermal() async => heat;
  @override
  Stream<void> get changes => _changes.stream;
}

class FakeNotice implements ProcessingNotice {
  final calls = <String>[];
  @override
  Future<void> show(String title, double progress, Duration? left) async => calls.add('show:$title');
  @override
  Future<void> showWaiting(String title, String why) async => calls.add('wait:$title:$why');
  @override
  Future<void> hide() async => calls.add('hide');
}

/// A store whose readiness the test sets (every model, or all but [missing]).
class TestStore extends ModelStore {
  TestStore() : super(Directory.systemTemp, Downloader());
  bool isReady = true;
  final missing = <ModelId>{};
  @override
  bool ready(ModelId id) => isReady && !missing.contains(id);
}

/// What the fake task model does, set by a test before or during a step.
class TaskHooks {
  /// Runs as each answer is asked for.
  Future<void> Function(String prompt)? onGenerate;

  /// The answer instead of the usual one.
  String? answer;
}

/// A task model: every answer finds "Send the report" in the line said to
/// Nishchay (unless [TaskHooks.answer] says otherwise).
class FakeTaskEngine implements LlmEngine {
  FakeTaskEngine(this.log, this.hooks);
  final List<String> log;
  final TaskHooks hooks;
  bool closed = false;
  bool _stop = false;

  @override
  Future<int> countTokens(String text) async => (text.length / 4).ceil();

  @override
  Future<String> generate({required String prompt, required String grammar, int maxTokens = 1536, double temperature = 0.1, int seed = 1}) async {
    log.add(prompt.contains('partial results') ? 'merge' : RegExp(r'\(part \d+ of').firstMatch(prompt)?.group(0) ?? 'part');
    await hooks.onGenerate?.call(prompt);
    if (_stop) {
      _stop = false;
      throw const LlmFailed('stopped');
    }
    return hooks.answer ??
        '{"summary": "A review.", "tasks": [{"description": "Send the report", "assigned_by": null, "due": null, '
            '"quote": "Nishchay, please send the report."}]}';
  }

  @override
  void stop() => _stop = true;

  @override
  Future<void> close() async => closed = true;
}

/// Waits (up to 5 s) for [done].
Future<void> until(FutureOr<bool> Function() done) async {
  for (var i = 0; i < 500 && !await done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late Directory root;
  late ProviderContainer container;
  late RecordingsRepository repo;
  late TranscriptRepository transcripts;
  late FakeDevice device;
  late FakeNotice notice;
  late TestStore store;
  late Script script;
  late List<FakeSpeech> made;
  late List<SpeechSetup> setups;
  late List<FakeTaskEngine> engines;
  late List<String> asked;
  late TaskHooks hooks;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('proc');
    device = FakeDevice();
    notice = FakeNotice();
    store = TestStore();
    script = Script();
    made = [];
    setups = [];
    engines = [];
    asked = [];
    hooks = TaskHooks();
    container = ProviderContainer(overrides: [
      llmEngineFactoryProvider.overrideWithValue((model) async {
        final e = FakeTaskEngine(asked, hooks);
        engines.add(e);
        return e;
      }),
      databaseProvider.overrideWithValue(db),
      recordingsRootProvider.overrideWithValue(root),
      deviceStateProvider.overrideWithValue(device),
      processingNoticeProvider.overrideWithValue(notice),
      modelStoreProvider.overrideWithValue(store),
      commonWordsProvider.overrideWith((ref) async => CommonWords({'said', 'yes'})),
      speechToTextFactoryProvider.overrideWithValue(({required SpeechSetup setup, required int startMs, required int threads}) async {
        final s = FakeSpeech(startMs, threads, script);
        made.add(s);
        setups.add(setup);
        return s;
      }),
      audioCompressorProvider.overrideWithValue((pieces, dir) async {
        await script.onCompress?.call();
        return compressPieces(pieces, dir);
      }),
      speakerGrouperProvider.overrideWithValue((lines, {me, people = const []}) async {
        await script.onGrouping?.call();
        if (script.failGrouping) throw StateError('grouping failed');
        return groupInBackground(lines, me: me, people: people);
      }),
    ]);
    repo = container.read(recordingsRepositoryProvider);
    transcripts = container.read(transcriptRepositoryProvider);
    // Speech only, but in the tasks tests.
    await container.read(taskSettingsProvider.notifier).setFindTasks(false);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// A finished recording of [seconds] seconds, in 20-second pieces.
  Future<int> recording({int seconds = 60, DateTime? at, SpeechSetup setup = SpeechSetup.englishOnly}) async {
    final r = await repo.create(title: 'Weekly', startedAt: at ?? DateTime(2026, 10, 13, 9), setup: setup);
    final dir = await repo.audioDir(r.id);
    for (var i = 0; i * 20 < seconds; i++) {
      final len = (seconds - i * 20).clamp(0, 20) * kBytesPerSecond;
      File('${dir.path}/piece-${i.toString().padLeft(3, '0')}.wav').writeAsBytesSync([...wavHeader(len), ...Uint8List(len)]);
    }
    await repo.finish(r.id, Duration(seconds: seconds));
    return r.id;
  }

  Future<Recording> get(int id) async => (await repo.get(id))!;
  Processor start() => container.read(processorProvider.notifier);

  /// Until [id] has [status] and the processor's loop has stopped.
  Future<void> reaches(int id, RecordingStatus status) async {
    await until(() async => (await repo.get(id))?.status == status);
    await until(() => !start().busy);
  }

  test('processes a queued recording to done and saves its lines', () async {
    final id = await recording();
    start();
    await reaches(id, RecordingStatus.done);
    final r = await get(id);
    expect(r.status, RecordingStatus.done);
    expect(r.processedMs, 60000);
    expect(await transcripts.watch(id).first, hasLength(6)); // 10-second chunks
  });

  test('resumes after the last saved line without repeating it', () async {
    final id = await recording();
    await transcripts.save(id, [const Phrase(startMs: 0, endMs: 20000, text: 'old', words: [])], processedMs: 20000);
    start();
    await reaches(id, RecordingStatus.done);
    expect(made.single.startMs, 20000);
    expect(made.single.pushedFrom.first, 20000);
    final lines = await transcripts.watch(id).first;
    expect(lines.where((l) => l.text == 'old'), hasLength(1));
    expect(lines, hasLength(1 + 4));
    expect((await get(id)).status, RecordingStatus.done);
  });

  test('one recording at a time, oldest first', () async {
    final newer = await recording(at: DateTime(2026, 10, 13, 11));
    final older = await recording(at: DateTime(2026, 10, 13, 10));
    start();
    await reaches(newer, RecordingStatus.done);
    final rows = await db.select(db.transcriptLines).get();
    final olderIds = rows.where((l) => l.meetingId == older).map((l) => l.id);
    final newerIds = rows.where((l) => l.meetingId == newer).map((l) => l.id);
    expect(olderIds.reduce((a, b) => a > b ? a : b), lessThan(newerIds.reduce((a, b) => a < b ? a : b)));
    expect((await get(newer)).status, RecordingStatus.done);
  });

  test('silence only ends done with no lines', () async {
    script.silent = true;
    final id = await recording();
    start();
    await reaches(id, RecordingStatus.done);
    expect((await get(id)).status, RecordingStatus.done);
    expect(await transcripts.watch(id).first, isEmpty);
  });

  test('a speech error marks it failed and retry finishes it', () async {
    script.failOnPush = 2;
    final id = await recording();
    start();
    await reaches(id, RecordingStatus.error);
    var r = await get(id);
    expect(r.status, RecordingStatus.error);
    expect(r.error, 'speech_failed');
    script.failOnPush = null;
    await start().retry(id);
    await reaches(id, RecordingStatus.done);
    r = await get(id);
    expect(r.status, RecordingStatus.done);
    expect(r.processedMs, 60000);
  });

  test('a recording deleted mid-job is dropped', () async {
    final gone = await recording(at: DateTime(2026, 10, 13, 9));
    final next = await recording(at: DateTime(2026, 10, 13, 10));
    script.onPush = (s) async {
      if (s.pushes == 2 && made.length == 1) {
        await (db.delete(db.meetings)..where((m) => m.id.equals(gone))).go();
      }
    };
    start();
    await reaches(next, RecordingStatus.done);
    expect(await repo.get(gone), isNull);
    expect(await transcripts.watch(gone).first, isEmpty);
    expect((await get(next)).status, RecordingStatus.done);
  });

  test('low battery waits, charging resumes', () async {
    device.level = 15;
    final id = await recording();
    start();
    await reaches(id, RecordingStatus.waitingCharge);
    expect((await get(id)).status, RecordingStatus.waitingCharge);
    expect(container.read(processorProvider).waiting, 'charge');
    expect(made, isEmpty);
    device.plugIn();
    await reaches(id, RecordingStatus.done);
    expect((await get(id)).status, RecordingStatus.done);
  });

  test('no speech model: waits with waiting model', () async {
    store.isReady = false;
    final id = await recording();
    start();
    await until(() => container.read(processorProvider).waiting == 'model');
    await until(() => !start().busy);
    expect(container.read(processorProvider).waiting, 'model');
    expect((await get(id)).status, RecordingStatus.queued);
    expect(made, isEmpty);
  });

  test('progress and time left move as it goes', () async {
    final seen = <ProcessingState>[];
    container.listen(processorProvider, (_, s) => seen.add(s), fireImmediately: true);
    final id = await recording();
    start().kick(); // a recording that just stopped wakes the processor
    await reaches(id, RecordingStatus.done);
    final working = seen.where((s) => s.recordingId == id).toList();
    expect(working.map((s) => s.progress), contains(predicate<double>((p) => p > 0 && p < 1)));
    expect(working.any((s) => s.left != null), isTrue);
    expect(working.first.title, 'Weekly');
    expect(container.read(processorProvider).recordingId, isNull);
  });

  test('a job that was cut off twice stops with speech_crashed', () async {
    final id = await recording();
    await repo.startAttempt(id);
    await repo.startAttempt(id);
    start();
    await reaches(id, RecordingStatus.error);
    var r = await get(id);
    expect(r.status, RecordingStatus.error);
    expect(r.error, 'speech_crashed');
    expect(made, isEmpty);
    await start().retry(id);
    await reaches(id, RecordingStatus.done);
    r = await get(id);
    expect(r.status, RecordingStatus.done);
  });

  test('the processing notice shows while working and hides at the end', () async {
    final id = await recording();
    start();
    await reaches(id, RecordingStatus.done);
    expect(notice.calls.first, 'show:Weekly');
    expect(notice.calls.last, 'hide');
  });

  test('threads: 4 after Stop, 2 when the phone is warm', () async {
    final first = await recording(at: DateTime(2026, 10, 13, 9));
    start();
    await reaches(first, RecordingStatus.done);
    expect(made.single.threads, 4);
    device.heat = 2;
    final second = await recording(at: DateTime(2026, 10, 13, 10));
    start().kick();
    await reaches(second, RecordingStatus.done);
    expect(made.last.threads, 2);
  });

  test('the only-while-charging setting is saved and applies at once', () async {
    final id = await recording();
    store.isReady = false; // nothing runs until the setting is on
    start();
    await until(() => !start().busy);
    store.isReady = true;
    await container.read(onlyWhileChargingProvider.notifier).set(true);
    await reaches(id, RecordingStatus.waitingCharge);
    expect(await container.read(onlyWhileChargingProvider.future), isTrue);
    expect(await container.read(settingsRepositoryProvider).getBool(kOnlyWhileChargingKey), isTrue);
  });

  test('closing the app mid-job leaves no errors behind', () async {
    final gate = Completer<void>();
    script.onPush = (_) => gate.future;
    await recording();
    start();
    await until(() => made.isNotEmpty);
    container.dispose(); // the app goes away while a chunk is being worked on
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    container = ProviderContainer(); // tearDown disposes this one instead
  });

  test('an engine that fails to start marks the recording failed and the next one still runs', () async {
    final broken = await recording(at: DateTime(2026, 10, 13, 9));
    final next = await recording(at: DateTime(2026, 10, 13, 10));
    var first = true;
    container.dispose();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      recordingsRootProvider.overrideWithValue(root),
      deviceStateProvider.overrideWithValue(device),
      processingNoticeProvider.overrideWithValue(notice),
      modelStoreProvider.overrideWithValue(store),
      speechToTextFactoryProvider.overrideWithValue(({required SpeechSetup setup, required int startMs, required int threads}) async {
        if (first) {
          first = false;
          throw StateError('model file unreadable'); // an Error, as a broken engine reports it
        }
        final s = FakeSpeech(startMs, threads, script);
        made.add(s);
        return s;
      }),
    ]);
    repo = container.read(recordingsRepositoryProvider);
    start();
    await reaches(next, RecordingStatus.done);
    final r = await get(broken);
    expect(r.status, RecordingStatus.error);
    expect(r.error, 'speech_failed');
    expect(notice.calls.last, 'hide');
  });

  test('the battery dropping mid-job pauses it, and charging resumes from there', () async {
    script.onPush = (s) async {
      if (s.pushes == 2) device.level = 15;
    };
    final id = await recording();
    start();
    await reaches(id, RecordingStatus.waitingCharge);
    final paused = await transcripts.processedMs(id);
    expect(paused, inInclusiveRange(10000, 50000));
    script.onPush = null;
    device.plugIn();
    await reaches(id, RecordingStatus.done);
    expect(made.last.startMs, paused);
    expect(await transcripts.watch(id).first, hasLength(6)); // nothing saved twice
  });

  test('a phone getting warm mid-job carries on with 2 threads', () async {
    script.onPush = (s) async {
      if (s.pushes == 2) device.heat = 2;
    };
    final id = await recording();
    start();
    await reaches(id, RecordingStatus.done);
    expect(made.map((s) => s.threads), [4, 2]);
    expect(await transcripts.watch(id).first, hasLength(6));
  });

  test('waiting for charge keeps a Plug in to continue notification up', () async {
    device.level = 15;
    final id = await recording();
    start();
    await reaches(id, RecordingStatus.waitingCharge);
    expect(notice.calls, contains('wait:Weekly:charge'));
    expect(notice.calls.last, isNot('hide'));
  });

  test('new lines get your name, vocabulary and Leave out', () async {
    await container.read(yourWordsProvider.notifier).set(name: 'Nishchay', leaveOut: 'umm');
    script.say = 'umm Nishher said yes';
    final id = await recording();
    start().kick();
    await reaches(id, RecordingStatus.done);
    final lines = await transcripts.watch(id).first;
    expect(lines.map((l) => l.text).toSet(), {'Nishchay said yes'});
  });

  const gujarati = SpeechSetup(languages: {Lang.en, Lang.gu});

  test('a recording waits for the models of its own setup', () async {
    store.missing.add(ModelId.gujarati);
    final id = await recording(setup: gujarati);
    start();
    await until(() => container.read(processorProvider).waiting == 'model');
    await until(() => !start().busy);
    expect((await get(id)).status, RecordingStatus.queued);
    expect(made, isEmpty);
    // The Gujarati model arrives: processed, with its own setup.
    store.missing.clear();
    container.invalidate(modelsProvider);
    await reaches(id, RecordingStatus.done);
    expect(setups, [gujarati]);
  });

  test("a recording waiting for its models doesn't hold up the others", () async {
    store.missing.add(ModelId.gujarati);
    final older = await recording(at: DateTime(2026, 10, 13, 9), setup: gujarati);
    final newer = await recording(at: DateTime(2026, 10, 13, 10));
    start();
    await reaches(newer, RecordingStatus.done);
    expect((await get(older)).status, RecordingStatus.queued);
    expect(setups, [SpeechSetup.englishOnly]);
    expect(container.read(processorProvider).waiting, 'model');
  });

  test('a job after Stop on 4 threads remembers how fast this phone was', () async {
    final book = container.read(speedBookProvider);
    expect(await book.rtf(SpeechSetup.englishOnly), 0.17); // the speed test's figure until measured
    final id = await recording(seconds: 60);
    start();
    await reaches(id, RecordingStatus.done);
    expect(made.single.threads, 4);
    expect(await book.rtf(SpeechSetup.englishOnly), lessThan(0.17)); // the fake engine is instant
  });

  group('process again', () {
    Future<int> doneWithOldLines() async {
      final id = await recording();
      start();
      await reaches(id, RecordingStatus.done);
      expect((await transcripts.watch(id).first).every((l) => l.text.startsWith('words')), isTrue);
      return id;
    }

    test('keeps the old lines until the new ones are complete, then shows only the new', () async {
      final id = await doneWithOldLines();
      final seen = <String>[];
      script.say = 'new words';
      script.onPush = (s) async => seen.addAll((await transcripts.watch(id).first).map((l) => l.text));
      await start().processAgain(id, SpeechSetup.englishOnly);
      await reaches(id, RecordingStatus.done);
      expect(seen.every((t) => t.startsWith('words')), isTrue, reason: 'only the old text shows during the run');
      final lines = await transcripts.watch(id).first;
      expect(lines.map((l) => l.text).toSet(), {'new words'});
      expect(lines, hasLength(6));
      expect((await get(id)).reprocessing, isFalse);
    });

    test('uses the setup chosen for it', () async {
      final id = await doneWithOldLines();
      const chosen = SpeechSetup(languages: {Lang.en, Lang.gu}, english: EnglishModel.accurate);
      await start().processAgain(id, chosen);
      await reaches(id, RecordingStatus.done);
      expect(setups.last, chosen);
      expect((await get(id)).setup, chosen);
    });

    test('a re-run waiting for a model can be started again with other choices', () async {
      final id = await doneWithOldLines();
      store.missing.add(ModelId.englishAccurate);
      await start().processAgain(id, const SpeechSetup(languages: {Lang.en}, english: EnglishModel.accurate));
      await until(() => container.read(processorProvider).waiting == 'model');
      script.say = 'new words';
      await start().processAgain(id, SpeechSetup.englishOnly);
      await reaches(id, RecordingStatus.done);
      expect(setups.last, SpeechSetup.englishOnly);
      expect((await transcripts.watch(id).first).map((l) => l.text).toSet(), {'new words'});
    });

    test('with a missing model it waits and keeps the old text', () async {
      final id = await doneWithOldLines();
      store.missing.add(ModelId.gujarati);
      await start().processAgain(id, const SpeechSetup(languages: {Lang.en, Lang.gu}));
      await until(() => container.read(processorProvider).waiting == 'model');
      expect((await get(id)).status, RecordingStatus.queued);
      expect((await transcripts.watch(id).first).every((l) => l.text.startsWith('words')), isTrue);
    });

    test('a re-run cut off resumes without repeating its new lines', () async {
      final id = await doneWithOldLines();
      script.say = 'new words';
      script.onPush = (s) async {
        if (s.pushes == 2) device.level = 15; // the battery drops: the run stops at its last saved line
      };
      await start().processAgain(id, SpeechSetup.englishOnly);
      await reaches(id, RecordingStatus.waitingCharge);
      final paused = await transcripts.processedMs(id);
      expect((await transcripts.watch(id).first).every((l) => l.text.startsWith('words')), isTrue);
      script.onPush = null;
      device.plugIn();
      await reaches(id, RecordingStatus.done);
      expect(made.last.startMs, paused);
      final lines = await transcripts.watch(id).first;
      expect(lines.map((l) => l.text).toSet(), {'new words'});
      expect(lines, hasLength(6)); // nothing saved twice
    });

    test('a failed re-run keeps the old lines, and Try again continues it', () async {
      final id = await doneWithOldLines();
      script.say = 'new words';
      script.failOnPush = 3; // the re-run's engine fails on its third push
      await start().processAgain(id, SpeechSetup.englishOnly);
      await reaches(id, RecordingStatus.error);
      expect((await transcripts.watch(id).first).every((l) => l.text.startsWith('words')), isTrue);
      final failedAt = await transcripts.processedMs(id);
      expect(failedAt, greaterThan(0));
      script.failOnPush = null;
      await start().retry(id);
      await reaches(id, RecordingStatus.done);
      expect(made.last.startMs, failedAt); // continued, not started over
      expect((await transcripts.watch(id).first).map((l) => l.text).toSet(), {'new words'});
    });
  });

  group('speakers', () {
    List<(String, String?)> said(List<Phrase> lines) => [for (final l in lines) (l.text, l.speaker)];

    test('after the text, lines get their speakers', () async {
      script.voiceOf = aThenB;
      final id = await recording(seconds: 40, setup: withSpeakers);
      final steps = <String?>[];
      container.listen(processorProvider, (_, s) => steps.add(s.step));
      start();
      await reaches(id, RecordingStatus.done);
      expect(said(await transcripts.watch(id).first), [
        ('words 0', 'Person 1'),
        ('words 10000', 'Person 2'),
        ('words 20000', 'Person 1'),
        ('words 30000', 'Person 2'),
      ]);
      final groups = await container.read(speakersRepositoryProvider).groups(id);
      expect([for (final g in groups) (g.label, g.speechMs)], [('Person 1', 20000), ('Person 2', 20000)]);
      expect(steps, contains('speakers'));
      expect((await get(id)).error, isNull);
    });

    test('with speakers off nothing is named', () async {
      script.voiceOf = aThenB;
      final id = await recording(seconds: 40);
      start();
      await reaches(id, RecordingStatus.done);
      expect((await transcripts.watch(id).first).every((l) => l.speaker == null), isTrue);
      expect(await container.read(speakersRepositoryProvider).groups(id), isEmpty);
    });

    test('a re-run names groups afresh', () async {
      script.voiceOf = aThenB;
      final id = await recording(seconds: 40, setup: withSpeakers);
      start();
      await reaches(id, RecordingStatus.done);
      // The old lines renamed by hand.
      final speakers = container.read(speakersRepositoryProvider);
      final old = await transcripts.linesForGrouping(id, draft: false);
      await speakers.saveGroups(id, SpeakerResult([for (final l in old) l.withSpeaker('Kiran', 7)], const []),
          draft: false);
      script.say = 'new words';
      await start().processAgain(id, withSpeakers);
      await reaches(id, RecordingStatus.done);
      expect((await transcripts.watch(id).first).map((l) => l.speaker), ['Person 1', 'Person 2', 'Person 1', 'Person 2']);
      expect([for (final g in await speakers.groups(id)) g.label], ['Person 1', 'Person 2']);
      expect(await speakers.groups(id, draft: true), isEmpty);
    });

    test('the trained voice and remembered people name groups', () async {
      script.voiceOf = aThenB;
      final speakers = container.read(speakersRepositoryProvider);
      await speakers.saveMyVoice(voiceA, at: DateTime(2026, 10, 15));
      await db.into(db.people).insert(PeopleCompanion.insert(
          name: 'Kiran', nameKey: 'kiran', printB64: encodePrint(voiceB), speechMs: 5000, updatedAt: DateTime(2026)));
      final id = await recording(seconds: 40, setup: withSpeakers);
      start();
      await reaches(id, RecordingStatus.done);
      expect((await transcripts.watch(id).first).map((l) => l.speaker), ['Me', 'Kiran', 'Me', 'Kiran']);
    });

    test('a re-run brings remembered voices back', () async {
      script.voiceOf = aThenB;
      final id = await recording(seconds: 40, setup: withSpeakers);
      start();
      await reaches(id, RecordingStatus.done);
      await db.into(db.people).insert(PeopleCompanion.insert(
          name: 'Kiran', nameKey: 'kiran', printB64: encodePrint(voiceB), speechMs: 5000, updatedAt: DateTime(2026)));
      await start().processAgain(id, withSpeakers);
      await reaches(id, RecordingStatus.done);
      expect((await transcripts.watch(id).first).map((l) => l.speaker), ['Person 1', 'Kiran', 'Person 1', 'Kiran']);
    });

    test('a recording deleted during the speakers step is dropped', () async {
      script.voiceOf = aThenB;
      final id = await recording(seconds: 40, setup: withSpeakers);
      script.onGrouping = () => repo.delete(id);
      start();
      await until(() async => await repo.get(id) == null);
      await until(() => !start().busy);
      expect(await repo.get(id), isNull);
      expect(container.read(processorProvider).recordingId, isNull);
    });

    test('Try again after a failed speakers step names the speakers, keeping the text', () async {
      script.voiceOf = aThenB;
      script.failGrouping = true;
      final id = await recording(seconds: 40, setup: withSpeakers);
      start();
      await reaches(id, RecordingStatus.done);
      expect((await get(id)).error, 'speakers_failed');
      script.failGrouping = false;
      await start().retry(id);
      await reaches(id, RecordingStatus.done);
      expect((await get(id)).error, isNull);
      final lines = await transcripts.watch(id).first;
      expect(lines.map((l) => l.speaker), ['Person 1', 'Person 2', 'Person 1', 'Person 2']);
      expect(lines, hasLength(4), reason: 'the text is not read again');
    });

    test('a speakers step that fails keeps the text', () async {
      script.voiceOf = aThenB;
      script.failGrouping = true;
      final id = await recording(seconds: 40, setup: withSpeakers);
      start();
      await reaches(id, RecordingStatus.done);
      final r = await get(id);
      expect((r.status, r.error), (RecordingStatus.done, 'speakers_failed'));
      final lines = await transcripts.watch(id).first;
      expect(lines, hasLength(4));
      expect(lines.every((l) => l.speaker == null), isTrue);
    });
  });

  group('upkeep', () {
    test('a finished recording becomes one FLAC, and its pieces go', () async {
      final id = await recording(seconds: 40);
      start();
      await reaches(id, RecordingStatus.done);
      await until(() async => (await repo.wavPieces(id)).isEmpty);
      await until(() => !start().busy);
      expect((await repo.pieces(id)).single.path, endsWith(kFlacName));
      expect(await transcripts.watch(id).first, hasLength(4));
    });

    test('upkeep and speech jobs take turns', () async {
      final id = await recording(seconds: 40);
      final gate = Completer<void>();
      var compressing = false;
      script.onCompress = () async {
        compressing = true;
        await gate.future;
      };
      start();
      await until(() => compressing);
      // Processed again while its audio is being compressed: it waits its turn.
      await start().processAgain(id, SpeechSetup.englishOnly);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(made, hasLength(1));
      script.onCompress = null;
      final read = <String>[];
      script.onPush = (s) async => read.addAll([for (final f in await repo.pieces(id)) f.path]);
      gate.complete();
      await reaches(id, RecordingStatus.done);
      expect(made, hasLength(2));
      expect(read, isNotEmpty);
      expect(read.every((p) => p.endsWith('.wav')), isTrue, reason: 'it read the pieces, kept for it');
      await until(() async => (await repo.wavPieces(id)).isEmpty);
      expect(await repo.wavPieces(id), isEmpty);
    });

    test('after a job, audio older than the setting goes and its text stays', () async {
      final old = await recording(seconds: 40, at: DateTime.now().subtract(const Duration(days: 45)));
      start();
      await reaches(old, RecordingStatus.done);
      await until(() async => (await get(old)).audioDeleted);
      await until(() => !start().busy);
      expect(await repo.pieces(old), isEmpty);
      expect(await transcripts.watch(old).first, hasLength(4));
    });

    test('Try again on a failed, compressed recording goes on from where it stopped', () async {
      script.failOnPush = 3;
      final id = await recording(seconds: 60);
      start();
      await reaches(id, RecordingStatus.error);
      await until(() async => (await repo.wavPieces(id)).isEmpty);
      await until(() => !start().busy);
      final failedAt = await transcripts.processedMs(id);
      expect(failedAt, greaterThan(0));
      script.failOnPush = null;
      await start().retry(id);
      await reaches(id, RecordingStatus.done);
      expect(made.last.pushedFrom.first, failedAt);
      expect(await transcripts.watch(id).first, hasLength(6));
    });

    test('a re-run that finds no audio keeps the old text', () async {
      final id = await recording(seconds: 40);
      start();
      await reaches(id, RecordingStatus.done);
      await until(() async => (await repo.wavPieces(id)).isEmpty);
      await until(() => !start().busy);
      // Its audio went (Keep recordings for) just after Process again was asked for.
      await repo.processAgain(id, SpeechSetup.englishOnly);
      for (final f in await repo.pieces(id)) {
        f.deleteSync();
      }
      start().kick();
      await reaches(id, RecordingStatus.done);
      final r = await get(id);
      expect(r.reprocessing, isFalse);
      expect(await transcripts.watch(id).first, hasLength(4));
    });

    test('an existing FLAC is checked before the pieces go', () async {
      final id = await recording(seconds: 40);
      final dir = await repo.audioDir(id);
      File('${dir.path}/$kFlacName').writeAsBytesSync([1, 2, 3]); // a FLAC a power cut cut short
      start();
      await reaches(id, RecordingStatus.done);
      await until(() async => (await repo.wavPieces(id)).isEmpty);
      await until(() => !start().busy);
      expect(totalMs(await repo.pieces(id)), 40000);
    });

    test('no upkeep while a recording is being made', () async {
      final id = await recording(seconds: 40);
      start();
      await reaches(id, RecordingStatus.done);
      // (it was compressed after its job; another finished one is waiting)
      final waiting = await recording(seconds: 20);
      await repo.setStatus(waiting, RecordingStatus.done);
      await repo.create(title: 'Now', startedAt: DateTime(2026, 10, 15, 11)); // status recording
      start().kick();
      await until(() => !start().busy);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await repo.wavPieces(waiting), hasLength(1));
    });

    test('a recording still waiting is not compressed', () async {
      store.missing.add(ModelId.gujarati);
      final id = await recording(seconds: 40, setup: const SpeechSetup(languages: {Lang.en, Lang.gu}));
      start();
      await until(() => container.read(processorProvider).waiting == 'model');
      await until(() => !start().busy);
      expect(await repo.wavPieces(id), hasLength(2));
    });
  });

  group('tasks', () {
    setUp(() async {
      await container.read(taskSettingsProvider.notifier).setFindTasks(true);
      await container.read(yourWordsProvider.notifier).set(name: 'Nishchay');
      script.say = 'Nishchay, please send the report.';
    });

    Future<void> found(int id) async {
      await until(() async => (await repo.get(id))?.tasksStatus == TasksStatus.found);
      await until(() => !start().busy);
    }

    Future<List<String>> tasksOf(int id) async =>
        [for (final t in await container.read(tasksRepositoryProvider).watchFor(id).first) t.description];

    /// A recording long enough for three parts (one token per 4 characters).
    Future<int> long() async {
      script.say = 'Nishchay, please send the report. ${'word ' * 700}';
      return recording(seconds: 90);
    }

    test('after the text, tasks are found and saved', () async {
      final id = await recording();
      start();
      await found(id);
      expect(await tasksOf(id), ['Send the report']);
      final r = await get(id);
      expect((r.summary, r.status, r.tasksPart, r.tasksWork), ('A review.', RecordingStatus.done, 0, ''));
      final t = (await container.read(tasksRepositoryProvider).watchFor(id).first).single;
      expect(t.quoteMs, 0, reason: 'where the quoted line starts');
    });

    test('with Find tasks off nothing is found', () async {
      await container.read(taskSettingsProvider.notifier).setFindTasks(false);
      final id = await recording();
      start();
      await reaches(id, RecordingStatus.done);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect((await get(id)).tasksStatus, TasksStatus.none);
      expect(engines, isEmpty);
    });

    test('several parts are saved one by one, then merged', () async {
      final id = await long();
      final saved = <int>[];
      hooks.onGenerate = (_) async => saved.add((await get(id)).tasksPart);
      start();
      await found(id);
      expect(asked, ['(part 1 of', '(part 2 of', '(part 3 of', 'merge']);
      expect(saved.skip(1), [1, 2, 3], reason: 'saved after each part');
      expect(await tasksOf(id), ['Send the report']);
    });

    test('a step cut off continues from the next part', () async {
      await container.read(taskSettingsProvider.notifier).setFindTasks(false);
      final id = await long();
      start();
      await reaches(id, RecordingStatus.done);
      // As an app killed after part 1 of 3 left it.
      await repo.saveTasksPart(id, 1, '{"summaries": ["Part one."], "tasks": []}');
      start().kick();
      await found(id);
      expect(asked, ['(part 2 of', '(part 3 of', 'merge']);
    });

    test('a recording made meanwhile goes first', () async {
      final first = await long();
      int? second;
      hooks.onGenerate = (prompt) async {
        if (second != null) return;
        second = await recording(seconds: 20, at: DateTime(2026, 10, 13, 12));
        start().kick();
      };
      start();
      await until(() async => second != null && (await repo.get(second!))?.status == RecordingStatus.done);
      expect((await get(first)).tasksStatus, TasksStatus.finding,
          reason: "the new recording's text came before the rest of the tasks");
      await found(first);
      await found(second!);
      expect(await tasksOf(first), ['Send the report']);
    });

    test('a recording being made stops the answer being written; the step goes on later', () async {
      final id = await long();
      var made = false;
      hooks.onGenerate = (_) async {
        if (made) return;
        made = true;
        await repo.create(title: 'Now', startedAt: DateTime(2026, 10, 13, 13)); // status recording
        start().pieceFinished(99, 1);
      };
      start();
      await until(() => made);
      await until(() => !start().busy);
      expect((await get(id)).tasksStatus, isIn([TasksStatus.waiting, TasksStatus.finding]), reason: 'given way, not failed');
      expect(engines.single.closed, isTrue);
      // The recording ends (here: it goes); the step goes on.
      await (db.delete(db.meetings)..where((m) => m.title.equals('Now'))).go();
      start().kick();
      await found(id);
    });

    test('without the task model the step waits and speech goes on', () async {
      store.missing.add(ModelId.taskFaster);
      final a = await recording();
      final b = await recording(at: DateTime(2026, 10, 13, 10));
      start();
      await reaches(b, RecordingStatus.done);
      await reaches(a, RecordingStatus.done);
      expect((await get(a)).tasksStatus, TasksStatus.waiting);
      expect(container.read(processorProvider).waiting, 'task_model');
      expect(engines, isEmpty);
      store.missing.clear();
      start().kick();
      await found(a);
      await found(b);
    });

    test('a recording deleted mid-step leaves nothing behind', () async {
      final id = await long();
      hooks.onGenerate = (_) async => repo.delete(id);
      start();
      await until(() async => await repo.get(id) == null);
      await until(() => !start().busy);
      expect(await db.select(db.tasks).get(), isEmpty);
      expect(engines.single.closed, isTrue);
    });

    test('a failed step can be tried again', () async {
      final id = await recording();
      hooks.answer = '{"summary": "cut';
      start();
      await until(() async => (await repo.get(id))?.tasksStatus == TasksStatus.failed);
      await until(() => !start().busy);
      expect((await get(id)).tasksWork, 'invalid_json');
      expect((await get(id)).status, RecordingStatus.done, reason: 'the text stays');
      hooks.answer = null;
      await start().findTasks(id);
      await found(id);
      expect(await tasksOf(id), ['Send the report']);
    });

    test('Find tasks on an old recording runs only this step', () async {
      await container.read(taskSettingsProvider.notifier).setFindTasks(false);
      final id = await recording();
      start();
      await reaches(id, RecordingStatus.done);
      final speechJobs = made.length;
      await start().findTasks(id);
      await found(id);
      expect(made, hasLength(speechJobs));
      expect(await tasksOf(id), ['Send the report']);
    });

    test('a whole step over a minute of audio remembers how fast this phone was', () async {
      final id = await recording();
      start();
      await found(id);
      expect(await container.read(speedBookProvider).tasksRtf(TaskAi.faster), lessThan(0.5));
    });

    test('a step that went on from a saved part is not timed', () async {
      await container.read(taskSettingsProvider.notifier).setFindTasks(false);
      final id = await long();
      start();
      await reaches(id, RecordingStatus.done);
      await repo.saveTasksPart(id, 1, '{"summaries": ["Part one."], "tasks": []}');
      start().kick();
      await found(id);
      expect(await container.read(speedBookProvider).tasksRtf(TaskAi.faster), 0.8);
    });

    test('an engine that is gone is started again for the next recording', () async {
      var asked = 0;
      hooks.onGenerate = (_) async {
        if (++asked == 1) throw const LlmFailed('gone');
      };
      final a = await recording();
      final b = await recording(at: DateTime(2026, 10, 13, 10));
      start();
      await until(() async => (await repo.get(a))?.tasksStatus == TasksStatus.failed);
      await found(b);
      expect(engines, hasLength(2), reason: 'a dead engine is not used again');
      expect(engines.first.closed, isTrue);
    });

    test('the notice stays up from the text to the tasks, and goes at the end', () async {
      final id = await recording();
      start();
      await found(id);
      expect(notice.calls.where((c) => c == 'hide'), hasLength(1));
      expect(notice.calls.last, 'hide');
    });

    test('the engine is closed after the pass, and the notice goes', () async {
      final id = await recording();
      start();
      await found(id);
      expect(engines.single.closed, isTrue);
      expect(notice.calls.last, 'hide');
    });

    test('the step waits for charging under 20%, and goes on when plugged in', () async {
      await container.read(taskSettingsProvider.notifier).setFindTasks(false);
      final id = await recording();
      start();
      await reaches(id, RecordingStatus.done);
      device.level = 15;
      await start().findTasks(id);
      await until(() => container.read(processorProvider).waiting == 'charge');
      await until(() => !start().busy);
      expect(engines, isEmpty);
      expect((await get(id)).tasksStatus, TasksStatus.waiting);
      device.plugIn();
      await found(id);
    });

    test('Process again finds the tasks again afterwards', () async {
      final id = await recording();
      start();
      await found(id);
      await start().processAgain(id, SpeechSetup.englishOnly);
      await until(() async => (await repo.get(id))?.tasksStatus != TasksStatus.found);
      await found(id);
      expect(engines, hasLength(2));
      expect(await tasksOf(id), ['Send the report']);
    });
  });
}
