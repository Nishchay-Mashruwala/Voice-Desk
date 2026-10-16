import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/data/retention.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/data/transcript_repository.dart';
import 'package:mobile_backend/engine/audio/flac.dart';
import 'package:mobile_backend/engine/audio/wav.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late LocalRecordingsRepository repo;
  final now = DateTime(2026, 10, 15, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('keep');
    repo = LocalRecordingsRepository(db, root);
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  /// A recording [daysOld] days old with [status], its audio as a FLAC or pieces, and one line.
  Future<int> recording(int daysOld, RecordingStatus status, {bool flac = true}) async {
    final r = await repo.create(startedAt: now.subtract(Duration(days: daysOld)));
    final dir = await repo.audioDir(r.id);
    File('${dir.path}/${flac ? kFlacName : 'piece-000.wav'}').writeAsBytesSync(wavHeader(0));
    await TranscriptRepository(db)
        .save(r.id, [const Phrase(startMs: 0, endMs: 900, text: 'hello', words: [])], processedMs: 900);
    await repo.setStatus(r.id, status);
    return r.id;
  }

  Future<List<String>> files(int id) async => [for (final f in (await repo.audioDir(id)).listSync()) f.uri.pathSegments.last];

  test('old finished recordings lose their audio, keep their text', () async {
    final old = await recording(31, RecordingStatus.done);
    final oldPieces = await recording(40, RecordingStatus.done, flac: false);
    final recent = await recording(29, RecordingStatus.done);
    expect(await applyRetention(repo, 30, now), 2);
    for (final id in [old, oldPieces]) {
      expect(await files(id), isEmpty);
      final r = (await repo.get(id))!;
      expect((r.audioDeleted, r.status), (true, RecordingStatus.done));
      expect(await TranscriptRepository(db).watch(id).first, hasLength(1));
    }
    expect(await files(recent), [kFlacName]);
    expect(await applyRetention(repo, 30, now), 0, reason: 'nothing left to delete');
  });

  test('retention never touches unfinished recordings', () async {
    final kept = [
      for (final s in [
        RecordingStatus.error,
        RecordingStatus.queued,
        RecordingStatus.processing,
        RecordingStatus.waitingCharge,
        RecordingStatus.recording,
      ])
        await recording(40, s, flac: false),
    ];
    expect(await applyRetention(repo, 7, now), 0);
    for (final id in kept) {
      expect(await files(id), ['piece-000.wav']);
      expect((await repo.get(id))!.audioDeleted, isFalse);
    }
  });

  test('Forever keeps everything', () async {
    final id = await recording(4000, RecordingStatus.done);
    expect(await applyRetention(repo, 0, now), 0);
    expect(await files(id), [kFlacName]);
  });

  test('how many a shorter period would delete', () async {
    await recording(10, RecordingStatus.done);
    await recording(100, RecordingStatus.done);
    await recording(100, RecordingStatus.error);
    expect(await repo.audioOlderThan(now.subtract(const Duration(days: 7))), hasLength(2));
    expect(await repo.audioOlderThan(now.subtract(const Duration(days: 90))), hasLength(1));
  });

  test('the setting is 30 days unless changed, and is kept', () async {
    final c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(c.dispose);
    expect(await c.read(keepAudioProvider.future), 30);
    await c.read(keepAudioProvider.notifier).set(7);
    expect(c.read(keepAudioProvider).value, 7);
    final again = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(again.dispose);
    expect(await again.read(keepAudioProvider.future), 7);
    await expectLater(c.read(keepAudioProvider.notifier).set(12), throwsArgumentError);
  });
}
