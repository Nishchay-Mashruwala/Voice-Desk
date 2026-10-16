import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/data/transcript_repository.dart';
import 'package:mobile_backend/engine/audio/wav.dart';
import 'package:mobile_backend/engine/speakers/voice_print.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'dart:typed_data';

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

  /// A recording with a second of audio.
  Future<int> newRecording({DateTime? at, RecordingStatus? status}) async {
    final r = await recordings.create(startedAt: at ?? DateTime(2026, 10, 13, 9));
    File('${(await recordings.audioDir(r.id)).path}/piece-000.wav')
        .writeAsBytesSync([...wavHeader(32000), ...Uint8List(32000)]);
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

  test("a word's confidence round-trips, and old rows read without one", () async {
    final id = await newRecording();
    await transcript.save(
      id,
      [const Phrase(startMs: 0, endMs: 900, text: 'fine thanks', words: [Word('fine', 0, 400, 0.947), Word('thanks', 400, 900)])],
      processedMs: 900,
    );
    await db.into(db.transcriptLines).insert(
        TranscriptLinesCompanion.insert(meetingId: id, startMs: 1000, endMs: 1010, content: 'a', wordsJson: '[["a",1000,1010]]'));
    final lines = await transcript.watch(id).first;
    expect(lines[0].words, [const Word('fine', 0, 400, 0.95), const Word('thanks', 400, 900)]);
    expect(lines[1].words.single.conf, isNull);
  });

  test('lines read back carry their id', () async {
    final id = await newRecording();
    await transcript.save(id, [phrase(0, 1000, 'one'), phrase(2000, 3000, 'two')], processedMs: 3000);
    final lines = await transcript.watch(id).first;
    expect(lines.every((l) => l.id != null), isTrue);
    expect(lines[0].id, isNot(lines[1].id));
  });

  test('editing a line changes its text and words, nothing else', () async {
    final id = await newRecording();
    await transcript.save(id, [phrase(1000, 2000, 'I am by thanks'), phrase(3000, 4000, 'next line')], processedMs: 4000);
    final line = (await transcript.watch(id).first).first;
    await transcript.editLine(line.id!, '  I am fine thanks  ');
    final after = await transcript.watch(id).first;
    expect(after[0].text, 'I am fine thanks');
    expect((after[0].id, after[0].startMs, after[0].endMs), (line.id, 1000, 2000));
    expect(after[0].words.map((w) => w.text), ['I', 'am', 'fine', 'thanks']);
    expect(after[0].words[0], line.words[0]); // an unchanged word keeps its time
    expect(after[1].text, 'next line');
  });

  test('an empty line is refused', () async {
    final id = await newRecording();
    await transcript.save(id, [phrase(0, 1000, 'hello')], processedMs: 1000);
    final line = (await transcript.watch(id).first).single;
    await expectLater(transcript.editLine(line.id!, '   '), throwsArgumentError);
    expect((await transcript.watch(id).first).single.text, 'hello');
  });

  test('editing a line that is gone throws LineGone', () async {
    await expectLater(transcript.editLine(999, 'hello'), throwsA(isA<LineGone>()));
  });

  test('draft lines stay hidden until committed, then replace the old ones', () async {
    final id = await newRecording(status: RecordingStatus.done);
    await transcript.save(id, [phrase(0, 1000, 'old words')], processedMs: 1000);
    const setup = SpeechSetup(languages: {Lang.en, Lang.gu}, english: EnglishModel.accurate);
    await recordings.processAgain(id, setup);
    var r = (await recordings.get(id))!;
    expect((r.status, r.processedMs, r.reprocessing, r.setup), (RecordingStatus.queued, 0, true, setup));
    await transcript.save(id, [phrase(0, 1000, 'new words')], processedMs: 1000, draft: true);
    expect((await transcript.watch(id).first).map((l) => l.text), ['old words']);
    await transcript.commitDraft(id);
    expect((await transcript.watch(id).first).map((l) => l.text), ['new words']);
    r = (await recordings.get(id))!;
    expect(r.reprocessing, isFalse);
  });

  test('processing again drops the drafts of an earlier unfinished re-run', () async {
    final id = await newRecording(status: RecordingStatus.done);
    await transcript.save(id, [phrase(0, 1000, 'old')], processedMs: 1000);
    await recordings.processAgain(id, SpeechSetup.englishOnly);
    await transcript.save(id, [phrase(0, 500, 'half')], processedMs: 500, draft: true);
    await recordings.processAgain(id, SpeechSetup.englishOnly);
    await transcript.commitDraft(id);
    expect(await transcript.watch(id).first, isEmpty); // the half-done drafts went; nothing new yet
  });

  test('voice pieces are saved with their line', () async {
    final id = await newRecording();
    final print = Float32List.fromList([0.5, -0.5, 0.25]);
    await transcript.save(id, [phrase(0, 2000, 'hello there').withVoices([VoicePiece(0, 2000, print)])], processedMs: 2000);
    final line = (await transcript.linesForGrouping(id, draft: false)).single;
    expect(line.voices.single.startMs, 0);
    expect(line.voices.single.print, print);
    // The screen's lines leave them out (an hour's prints are megabytes of text).
    expect((await transcript.watch(id).first).single.voices, isEmpty);
  });
}
