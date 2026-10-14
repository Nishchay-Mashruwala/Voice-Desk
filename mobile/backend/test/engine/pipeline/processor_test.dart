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
import 'package:mobile_backend/engine/audio/wav.dart';
import 'package:mobile_backend/engine/models/downloader.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/pipeline/conditions.dart';
import 'package:mobile_backend/engine/pipeline/processing_notice.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/speech/speech_to_text.dart';
import 'package:mobile_backend/engine/speech/vocabulary.dart';
import 'package:mobile_backend/engine/speech/your_words.dart';

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
    final phrases = script.silent
        ? <Phrase>[]
        : [Phrase(startMs: _at, endMs: end, text: text, words: [for (final w in text.split(' ')) Word(w, _at, end)])];
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
}

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

/// A store whose readiness the test sets.
class TestStore extends SpeechModelStore {
  TestStore() : super(Directory.systemTemp, Downloader());
  bool isReady = true;
  @override
  bool get ready => isReady;
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

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('proc');
    device = FakeDevice();
    notice = FakeNotice();
    store = TestStore();
    script = Script();
    made = [];
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      recordingsRootProvider.overrideWithValue(root),
      deviceStateProvider.overrideWithValue(device),
      processingNoticeProvider.overrideWithValue(notice),
      speechModelStoreProvider.overrideWithValue(store),
      commonWordsProvider.overrideWith((ref) async => CommonWords({'said', 'yes'})),
      speechToTextFactoryProvider.overrideWithValue(({required int startMs, required int threads}) async {
        final s = FakeSpeech(startMs, threads, script);
        made.add(s);
        return s;
      }),
    ]);
    repo = container.read(recordingsRepositoryProvider);
    transcripts = container.read(transcriptRepositoryProvider);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// A finished recording of [seconds] seconds, in 20-second pieces.
  Future<int> recording({int seconds = 60, DateTime? at}) async {
    final r = await repo.create(title: 'Weekly', startedAt: at ?? DateTime(2026, 10, 13, 9));
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
      speechModelStoreProvider.overrideWithValue(store),
      speechToTextFactoryProvider.overrideWithValue(({required int startMs, required int threads}) async {
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
}
