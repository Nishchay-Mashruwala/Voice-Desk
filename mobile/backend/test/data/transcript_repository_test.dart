import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/data/transcript_repository.dart';

Phrase phrase(int start, int end, String text) => Phrase(
      startMs: start,
      endMs: end,
      text: text,
      words: [for (final (i, w) in text.split(' ').indexed) Word(w, start + i * 100, start + i * 100 + 100)],
    );

void main() {
  late AppDatabase db;
  late LocalRecordingsRepository recordings;
  late TranscriptRepository transcript;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    recordings = LocalRecordingsRepository(db, Directory.systemTemp.createTempSync('tr'));
    transcript = TranscriptRepository(db);
  });
  tearDown(() => db.close());

  Future<int> newRecording({DateTime? at, RecordingStatus? status}) async {
    final r = await recordings.create(startedAt: at ?? DateTime(2026, 10, 13, 9));
    if (status != null) await recordings.setStatus(r.id, status);
    return r.id;
  }

  test('save then watch returns the lines in time order with their words', () async {
    final id = await newRecording();
    await transcript.save(id, [phrase(5000, 6000, 'second line'), phrase(1000, 2000, 'first line')], processedMs: 6000);
    final lines = await transcript.watch(id).first;
    expect(lines.map((l) => l.text), ['first line', 'second line']);
    expect(lines.first.words, [const Word('first', 1000, 1100), const Word('line', 1100, 1200)]);
  });

  test('save moves processedMs forward and never back', () async {
    final id = await newRecording();
    await transcript.save(id, [], processedMs: 60000);
    await transcript.save(id, [], processedMs: 30000);
    expect(await transcript.processedMs(id), 60000);
  });

  test('save for a deleted recording throws RecordingGone and stores nothing', () async {
    final id = await newRecording();
    await recordings.delete(id);
    await expectLater(transcript.save(id, [phrase(0, 500, 'hi')], processedMs: 500), throwsA(isA<RecordingGone>()));
    expect(await db.select(db.transcriptLines).get(), isEmpty);
  });

  test('deleting a recording deletes its lines', () async {
    final id = await newRecording();
    await transcript.save(id, [phrase(0, 500, 'hi')], processedMs: 500);
    await recordings.delete(id);
    expect(await db.select(db.transcriptLines).get(), isEmpty);
  });

  test('nextToProcess takes the oldest waiting recording', () async {
    await newRecording(at: DateTime(2026, 10, 13, 8), status: RecordingStatus.done);
    await newRecording(at: DateTime(2026, 10, 13, 8, 30), status: RecordingStatus.error);
    await newRecording(at: DateTime(2026, 10, 13, 8, 45)); // still recording
    final queued = await newRecording(at: DateTime(2026, 10, 13, 10), status: RecordingStatus.queued);
    final processing = await newRecording(at: DateTime(2026, 10, 13, 9), status: RecordingStatus.processing);
    expect((await recordings.nextToProcess())!.id, processing);
    await recordings.setStatus(processing, RecordingStatus.done);
    expect((await recordings.nextToProcess())!.id, queued);
    await recordings.setStatus(queued, RecordingStatus.waitingCharge);
    expect((await recordings.nextToProcess())!.id, queued);
  });

  test('attempts count up and clear', () async {
    final id = await newRecording();
    expect(await recordings.startAttempt(id), 1);
    expect(await recordings.startAttempt(id), 2);
    await recordings.clearAttempts(id);
    expect(await recordings.startAttempt(id), 1);
  });

  test('progress is processedMs over the duration', () async {
    final id = await newRecording();
    await recordings.finish(id, const Duration(seconds: 120));
    await transcript.save(id, [], processedMs: 30000);
    expect((await recordings.get(id))!.progress, 0.25);
    final other = await newRecording();
    expect((await recordings.get(other))!.progress, 0);
  });
}
