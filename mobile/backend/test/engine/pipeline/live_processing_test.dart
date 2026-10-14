import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/data/transcript_repository.dart';
import 'package:mobile_backend/engine/audio/wav.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/pipeline/conditions.dart';
import 'package:mobile_backend/engine/pipeline/processing_notice.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/speech/speech_to_text.dart';

import 'processor_test.dart' show FakeSpeech, Script, FakeDevice, FakeNotice, TestStore, until;
import 'dart:async';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late RecordingsRepository repo;
  late TranscriptRepository transcripts;
  late FakeDevice device;
  late Script script;
  late List<FakeSpeech> made;
  late FakeNotice notice;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    device = FakeDevice();
    script = Script();
    made = [];
    notice = FakeNotice();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      recordingsRootProvider.overrideWithValue(Directory.systemTemp.createTempSync('live')),
      deviceStateProvider.overrideWithValue(device),
      processingNoticeProvider.overrideWithValue(notice),
      speechModelStoreProvider.overrideWithValue(TestStore()),
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

  Processor processor() => container.read(processorProvider.notifier);

  Future<void> addPieces(int id, int from, int count) async {
    final dir = await repo.audioDir(id);
    const len = 20 * kBytesPerSecond;
    for (var i = from; i < from + count; i++) {
      File('${dir.path}/piece-${i.toString().padLeft(3, '0')}.wav').writeAsBytesSync([...wavHeader(len), ...Uint8List(len)]);
    }
  }

  /// A recording still going, with [pieces] 20-second pieces on disk.
  Future<int> live(int pieces) async {
    final r = await repo.create(title: 'Standup', startedAt: DateTime(2026, 10, 13, 9));
    await addPieces(r.id, 0, pieces);
    return r.id;
  }

  test('lines appear during the recording, a minute at a time', () async {
    final id = await live(3); // two finished, the third still being written
    processor().pieceFinished(id, 2);
    await until(() async => await transcripts.processedMs(id) >= 40000);
    expect(await transcripts.processedMs(id), 40000);
    expect(await transcripts.watch(id).first, hasLength(4)); // 10-second chunks of two pieces
    expect((await repo.get(id))!.status, RecordingStatus.recording);
  });

  test('after Stop only the rest is done', () async {
    final id = await live(3);
    processor().pieceFinished(id, 2);
    await until(() async => await transcripts.processedMs(id) >= 40000);
    await repo.finish(id, const Duration(seconds: 60));
    processor().kick();
    await until(() async => (await repo.get(id))!.status == RecordingStatus.done);
    expect(made, hasLength(2));
    expect(made.last.startMs, 40000);
    expect(made.last.pushedFrom.first, 40000);
    expect(await transcripts.watch(id).first, hasLength(6));
  });

  test('while recording it uses 2 threads, after Stop 4', () async {
    final id = await live(2);
    processor().pieceFinished(id, 1);
    await until(() async => await transcripts.processedMs(id) >= 20000);
    await repo.finish(id, const Duration(seconds: 40));
    processor().kick();
    await until(() async => (await repo.get(id))!.status == RecordingStatus.done);
    expect(made.map((s) => s.threads), [2, 4]);
  });

  test('a waiting gate skips live work and the whole recording is done after Stop', () async {
    device.level = 15;
    final id = await live(3);
    processor().pieceFinished(id, 2);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(made, isEmpty);
    device.level = 80;
    await repo.finish(id, const Duration(seconds: 60));
    processor().kick();
    await until(() async => (await repo.get(id))!.status == RecordingStatus.done);
    expect(made.single.startMs, 0);
  });

  test('the next piece continues where the last left off', () async {
    final id = await live(2);
    processor().pieceFinished(id, 1);
    await until(() async => await transcripts.processedMs(id) >= 20000);
    await addPieces(id, 2, 1);
    processor().pieceFinished(id, 2);
    await until(() async => await transcripts.processedMs(id) >= 40000);
    expect(made, hasLength(1)); // one engine for the whole recording
    expect(made.single.pushedFrom, [0, 10000, 20000, 30000]);
  });

  test('a stopped recording shows the processing notice at once', () async {
    final gate = Completer<void>();
    script.onPush = (_) => gate.future; // live work still busy with the last minute
    final id = await live(2);
    processor().pieceFinished(id, 1);
    await until(() => made.isNotEmpty);
    processor().recordingStopped('Standup');
    await Future<void>.delayed(Duration.zero);
    expect(notice.calls, contains('show:Standup'));
    gate.complete();
  });
}
