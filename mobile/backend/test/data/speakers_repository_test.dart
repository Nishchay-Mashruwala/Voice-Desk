import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/data/speakers_repository.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/data/transcript_repository.dart';
import 'package:mobile_backend/engine/speakers/grouping.dart';
import 'package:mobile_backend/engine/speakers/voice_print.dart';

Float32List voice(int axis) => Float32List(8)..[axis] = 1;

/// A line from [start] to [end] (ms), its words evenly, with [voices] (one
/// print of [axis] for the whole line when not given).
Phrase line(int start, int end, String text, {int? axis, List<VoicePiece>? voices}) {
  final ws = text.split(' ');
  final step = (end - start) ~/ ws.length;
  return Phrase(
    startMs: start,
    endMs: end,
    text: text,
    words: [for (final (i, w) in ws.indexed) Word(w, start + i * step, i == ws.length - 1 ? end : start + (i + 1) * step)],
    voices: voices ?? [if (axis != null) VoicePiece(start, end, voice(axis))],
  );
}

void main() {
  late AppDatabase db;
  late LocalRecordingsRepository recordings;
  late TranscriptRepository transcript;
  late SpeakersRepository speakers;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    recordings = LocalRecordingsRepository(db, Directory.systemTemp.createTempSync('spk'));
    transcript = TranscriptRepository(db);
    speakers = SpeakersRepository(db);
  });
  tearDown(() => db.close());

  test('groups are saved and replace the old ones', () async {
    final id = (await recordings.create(startedAt: DateTime(2026, 10, 15, 9))).id;
    await transcript.save(
        id,
        [
          line(0, 3000, 'hello there friend', axis: 0),
          line(3500, 7700, 'one two three four five six seven', voices: [
            VoicePiece(3500, 5000, voice(1)),
            VoicePiece(4250, 5750, voice(1)),
            VoicePiece(5000, 6500, voice(0)),
            VoicePiece(5750, 7250, voice(0)),
            VoicePiece(6200, 7700, voice(0)),
          ]),
          line(8000, 11000, 'second voice talking', axis: 1),
        ],
        processedMs: 11000);

    final lines = await transcript.linesForGrouping(id, draft: false);
    expect(lines.map((l) => l.voices.length), [1, 5, 1]);
    await speakers.saveGroups(id, groupSpeakers(lines), draft: false);
    final named = await transcript.watch(id).first;
    expect([for (final l in named) (l.text, l.speaker)], [
      ('hello there friend', 'Person 1'),
      ('one two three', 'Person 2'),
      ('four five six seven', 'Person 1'),
      ('second voice talking', 'Person 2'),
    ]);
    expect(named[1].id, lines[1].id, reason: 'the first part is the line, updated');
    expect((await transcript.linesForGrouping(id, draft: false))[2].voices, isNotEmpty);
    expect([for (final g in await speakers.groups(id)) (g.id, g.label)], [(1, 'Person 1'), (2, 'Person 2')]);

    // A second run (one voice now) replaces the groups; drafts are their own.
    final again = await transcript.linesForGrouping(id, draft: false);
    final one = SpeakerResult([for (final l in again) l.withSpeaker('Person 1', 1)],
        [SpeakerGroup(id: 1, label: 'Person 1', print: voice(0), speechMs: 11000)]);
    await speakers.saveGroups(id, one, draft: false);
    expect((await transcript.watch(id).first).map((l) => l.speaker).toSet(), {'Person 1'});
    expect(await speakers.groups(id), hasLength(1));
    expect(await speakers.groups(id, draft: true), isEmpty);
  });

  test('a recording deleted before its groups are saved is gone', () async {
    final id = (await recordings.create(startedAt: DateTime(2026, 10, 15, 9))).id;
    await recordings.delete(id);
    await expectLater(speakers.saveGroups(id, const SpeakerResult([], []), draft: false), throwsA(isA<RecordingGone>()));
  });

  test('your voice and remembered people', () async {
    expect(await speakers.myVoice(), isNull);
    await speakers.saveMyVoice(voice(2), at: DateTime(2026, 10, 15));
    expect(await speakers.myVoice(), voice(2));
    expect(await speakers.myVoiceSavedAt(), DateTime(2026, 10, 15));
    await db.into(db.people).insert(PeopleCompanion.insert(
        name: 'Kiran', nameKey: 'kiran', printB64: encodePrint(voice(3)), speechMs: 5000, updatedAt: DateTime(2026)));
    final people = await speakers.people();
    expect(people.map((p) => p.name), ['Kiran']);
    expect(people.single.print, voice(3));
  });

  group('rename', () {
    /// A recording of A (Person 1, 6 s) and B (Person 2, [bMs]), grouped.
    Future<int> named({int bMs = 3000}) async {
      final id = (await recordings.create(startedAt: DateTime(2026, 10, 15, 9))).id;
      await transcript.save(
          id,
          [
            line(0, 3000, 'first from a', axis: 0),
            line(3500, 3500 + bMs, 'from b', axis: 1),
            line(7000, 10000, 'second from a', axis: 0),
          ],
          processedMs: 10000);
      await speakers.saveGroups(id, groupSpeakers(await transcript.linesForGrouping(id, draft: false)), draft: false);
      return id;
    }

    test('rename changes every line of the group', () async {
      final id = await named();
      await speakers.rename(id, 1, '  Asha ', remember: false);
      expect([for (final l in await transcript.watch(id).first) l.speaker], ['Asha', 'Person 2', 'Asha']);
      expect([for (final g in await speakers.groups(id)) g.label], ['Asha', 'Person 2']);
      expect(await speakers.people(), isEmpty);
    });

    test('a remembered voice is kept, and a name already known merges the voices', () async {
      final id = await named();
      await speakers.rename(id, 2, 'Kiran', remember: true);
      var kiran = (await db.select(db.people).get()).single;
      expect((kiran.name, kiran.speechMs), ('Kiran', 3000));
      expect(decodePrint(kiran.printB64), voice(1));
      // Kiran again, in another recording, with a voice a little different.
      final other = (await recordings.create(startedAt: DateTime(2026, 10, 16, 9))).id;
      final near = normalised(Float32List(8)
        ..[1] = 1
        ..[2] = 1);
      await transcript.save(other, [line(0, 3000, 'kiran again', voices: [VoicePiece(0, 3000, near)])],
          processedMs: 3000);
      await speakers.saveGroups(other, groupSpeakers(await transcript.linesForGrouping(other, draft: false)),
          draft: false);
      await speakers.rename(other, 1, 'kiran', remember: true);
      kiran = (await db.select(db.people).get()).single;
      expect((kiran.name, kiran.speechMs), ('kiran', 6000));
      final merged = decodePrint(kiran.printB64);
      expect(similarity(merged, voice(1)), closeTo(similarity(merged, near), 0.01)); // the two, evenly
    });

    test("under 2 s of speech can't be remembered", () async {
      final id = await named(bMs: 1600);
      await expectLater(speakers.rename(id, 2, 'Kiran', remember: true), throwsA(isA<NotEnoughSpeech>()));
      expect(await speakers.people(), isEmpty);
      expect((await transcript.watch(id).first)[1].speaker, 'Person 2', reason: 'nothing changed');
    });

    test('remembering uses up to 30 s of their speech', () async {
      final id = (await recordings.create(startedAt: DateTime(2026, 10, 15, 9))).id;
      await transcript.save(
          id, [for (var i = 0; i < 15; i++) line(i * 3000, i * 3000 + 2500, 'line $i', axis: 0)], processedMs: 45000);
      await speakers.saveGroups(id, groupSpeakers(await transcript.linesForGrouping(id, draft: false)), draft: false);
      await speakers.rename(id, 1, 'Asha', remember: true);
      expect((await db.select(db.people).get()).single.speechMs, 30000);
    });

    test("Me can't be renamed, and a name is needed", () async {
      final id = await named();
      await speakers.saveMyVoice(voice(0), at: DateTime(2026, 10, 15));
      await speakers.saveGroups(
          id,
          groupSpeakers(await transcript.linesForGrouping(id, draft: false), me: await speakers.myVoice()),
          draft: false);
      expect([for (final g in await speakers.groups(id)) g.label], ['Me', 'Person 1']);
      await expectLater(speakers.rename(id, 1, 'Asha', remember: false), throwsA(isA<CantRenameMe>()));
      await expectLater(speakers.rename(id, 2, '  ', remember: false), throwsArgumentError);
      await expectLater(speakers.rename(id, 2, 'me', remember: false), throwsArgumentError);
    });
  });

  group('Said by and People', () {
    Future<int> twoPeople() async {
      final id = (await recordings.create(startedAt: DateTime(2026, 10, 15, 9))).id;
      await transcript.save(
          id,
          [
            line(0, 3000, 'first from a', axis: 0),
            line(3500, 6500, 'from b', axis: 1),
            line(7000, 10000, 'second from a', axis: 0),
          ],
          processedMs: 10000);
      await speakers.saveGroups(id, groupSpeakers(await transcript.linesForGrouping(id, draft: false)), draft: false);
      return id;
    }

    test('Said by moves only that line', () async {
      final id = await twoPeople();
      final before = await speakers.groups(id);
      final third = (await transcript.watch(id).first)[2];
      await speakers.moveLine(third.id!, groupId: 2, label: 'Person 2');
      expect([for (final l in await transcript.watch(id).first) (l.speaker, l.speakerGroup)],
          [('Person 1', 1), ('Person 2', 2), ('Person 2', 2)]);
      final after = await speakers.groups(id);
      expect([for (final g in after) (g.label, g.speechMs)], [for (final g in before) (g.label, g.speechMs)]);
      for (final (k, g) in after.indexed) {
        expect(g.print, before[k].print, reason: 'no voice print changes');
      }
      // To someone who isn't one of its groups.
      await speakers.moveLine(third.id!, label: 'Asha');
      final moved = (await transcript.watch(id).first)[2];
      expect((moved.speaker, moved.speakerGroup), ('Asha', null));
      await expectLater(speakers.moveLine(third.id!, label: ' '), throwsArgumentError);
    });

    test('a remembered person can be renamed and forgotten; past recordings keep their names', () async {
      final id = await twoPeople();
      await speakers.rename(id, 2, 'Kiran', remember: true);
      final kiran = (await speakers.watchPeople().first).single;
      expect((kiran.name, kiran.speechMs), ('Kiran', 3000));
      await speakers.renamePerson(kiran.id, 'Kiran Shah');
      expect([for (final p in await speakers.watchPeople().first) p.name], ['Kiran Shah']);
      await speakers.forgetPerson(kiran.id);
      expect(await speakers.watchPeople().first, isEmpty);
      expect((await transcript.watch(id).first)[1].speaker, 'Kiran');
    });

    test('renaming a person to a name already remembered makes them one', () async {
      final id = await twoPeople();
      await speakers.rename(id, 1, 'Asha', remember: true);
      await speakers.rename(id, 2, 'Kiran', remember: true);
      final people = await speakers.watchPeople().first;
      await speakers.renamePerson(people.firstWhere((p) => p.name == 'Kiran').id, 'asha');
      final one = (await speakers.watchPeople().first).single;
      expect((one.name, one.speechMs), ('asha', 9000));
    });

    test('forgetting your voice keeps past Me lines', () async {
      final id = await twoPeople();
      await speakers.saveMyVoice(voice(0), at: DateTime(2026, 10, 15));
      await speakers.saveGroups(
          id,
          groupSpeakers(await transcript.linesForGrouping(id, draft: false), me: await speakers.myVoice()),
          draft: false);
      await speakers.forgetMyVoice();
      expect(await speakers.myVoice(), isNull);
      expect(await speakers.myVoiceSavedAt(), isNull);
      expect([for (final l in await transcript.watch(id).first) l.speaker], ['Me', 'Person 1', 'Me']);
    });
  });
}
