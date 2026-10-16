import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/engine/audio/wav.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late LocalRecordingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('recordings');
    repo = LocalRecordingsRepository(db, root);
  });
  tearDown(() => db.close());

  test('create uses the default title and status recording', () async {
    final r = await repo.create(startedAt: DateTime(2026, 10, 12, 14, 5));
    expect(r.title, 'Recording · Oct 12, 14:05');
    expect(r.status, RecordingStatus.recording);
    expect(Directory('${root.path}/${r.id}').existsSync(), isTrue);
  });

  test('watchAll lists newest first', () async {
    await repo.create(startedAt: DateTime(2026, 10, 12, 9), title: 'Older');
    await repo.create(startedAt: DateTime(2026, 10, 12, 10), title: 'Newer');
    expect((await repo.watchAll().first).map((r) => r.title), ['Newer', 'Older']);
  });

  test('finish sets queued and duration', () async {
    final r = await repo.create(startedAt: DateTime.now());
    await repo.finish(r.id, const Duration(seconds: 90));
    final got = (await repo.get(r.id))!;
    expect(got.status, RecordingStatus.queued);
    expect(got.duration, const Duration(seconds: 90));
  });

  test('rename blank uses default title', () async {
    final r = await repo.create(startedAt: DateTime(2026, 10, 12, 14, 5), title: 'Weekly');
    await repo.rename(r.id, '   ');
    expect((await repo.get(r.id))!.title, 'Recording · Oct 12, 14:05');
  });

  test('rename trims the title', () async {
    final r = await repo.create(startedAt: DateTime.now());
    await repo.rename(r.id, '  Weekly review ');
    expect((await repo.get(r.id))!.title, 'Weekly review');
  });

  test('delete removes the row and its audio', () async {
    final r = await repo.create(startedAt: DateTime.now());
    final dir = await repo.audioDir(r.id);
    File('${dir.path}/piece-000.wav').writeAsBytesSync(wavHeader(0));
    await repo.delete(r.id);
    expect(await repo.get(r.id), isNull);
    expect(dir.existsSync(), isFalse);
  });

  test('pieces are listed in order', () async {
    final r = await repo.create(startedAt: DateTime.now());
    final dir = await repo.audioDir(r.id);
    for (final n in ['piece-001.wav', 'piece-000.wav', 'notes.txt']) {
      File('${dir.path}/$n').writeAsBytesSync(wavHeader(0));
    }
    expect((await repo.pieces(r.id)).map((f) => f.uri.pathSegments.last), ['piece-000.wav', 'piece-001.wav']);
  });

  test('pieces are the FLAC once the pieces have gone (a half-written one never)', () async {
    final r = await repo.create(startedAt: DateTime.now());
    final dir = await repo.audioDir(r.id);
    for (final n in ['piece-000.wav', 'piece-001.wav', 'audio.flac.part']) {
      File('${dir.path}/$n').writeAsBytesSync(wavHeader(0));
    }
    expect((await repo.pieces(r.id)).map((f) => f.uri.pathSegments.last), ['piece-000.wav', 'piece-001.wav']);
    File('${dir.path}/audio.flac').writeAsBytesSync([1]);
    expect((await repo.pieces(r.id)).map((f) => f.uri.pathSegments.last), ['piece-000.wav', 'piece-001.wav'],
        reason: 'the pieces are the audio until they are deleted');
    for (final n in ['piece-000.wav', 'piece-001.wav']) {
      File('${dir.path}/$n').deleteSync();
    }
    expect((await repo.pieces(r.id)).map((f) => f.uri.pathSegments.last), ['audio.flac']);
  });

  test('audio sizes count the FLAC or the pieces, largest first', () async {
    final small = await repo.create(title: 'Small', startedAt: DateTime(2026, 10, 14));
    final big = await repo.create(title: 'Big', startedAt: DateTime(2026, 10, 15));
    final none = await repo.create(title: 'None', startedAt: DateTime(2026, 10, 15));
    File('${(await repo.audioDir(small.id)).path}/piece-000.wav').writeAsBytesSync(Uint8List(1000));
    File('${(await repo.audioDir(small.id)).path}/piece-001.wav').writeAsBytesSync(Uint8List(500));
    File('${(await repo.audioDir(big.id)).path}/audio.flac').writeAsBytesSync(Uint8List(4000));
    for (final r in [small, big, none]) {
      await repo.setStatus(r.id, RecordingStatus.done);
    }
    expect([for (final (r, bytes) in await repo.audioSizes()) (r.title, bytes)], [('Big', 4000), ('Small', 1500)]);
  });

  test('recoverInterrupted repairs pieces and keeps the recording', () async {
    final r = await repo.create(startedAt: DateTime.now());
    final dir = await repo.audioDir(r.id);
    File('${dir.path}/piece-000.wav').writeAsBytesSync([...wavHeader(0), ...List.filled(64000, 0)]);
    expect(await repo.recoverInterrupted(), 1);
    final got = (await repo.get(r.id))!;
    expect(got.status, RecordingStatus.queued);
    expect(got.duration, const Duration(seconds: 2));
  });

  test('recoverInterrupted drops recordings under 1 s', () async {
    final r = await repo.create(startedAt: DateTime.now());
    final dir = await repo.audioDir(r.id);
    File('${dir.path}/piece-000.wav').writeAsBytesSync([...wavHeader(0), ...List.filled(16000, 0)]);
    expect(await repo.recoverInterrupted(), 0);
    expect(await repo.get(r.id), isNull);
  });

  test('recoverInterrupted leaves finished recordings alone', () async {
    final r = await repo.create(startedAt: DateTime.now());
    await repo.finish(r.id, const Duration(seconds: 5));
    expect(await repo.recoverInterrupted(), 0);
    expect((await repo.get(r.id))!.duration, const Duration(seconds: 5));
  });

  test('status ids round-trip, waiting_charge included', () {
    expect(RecordingStatus.waitingCharge.id, 'waiting_charge');
    for (final s in RecordingStatus.values) {
      expect(RecordingStatus.fromId(s.id), s);
    }
  });

  test('a recording keeps the setup it was created with', () async {
    const setup = SpeechSetup(languages: {Lang.en, Lang.gu}, prefer: Lang.hi, english: EnglishModel.accurate);
    final r = await repo.create(startedAt: DateTime(2026, 10, 14, 9), setup: setup);
    expect((await repo.get(r.id))!.setup, setup);
    final plain = await repo.create(startedAt: DateTime(2026, 10, 14, 10));
    expect(plain.setup, SpeechSetup.englishOnly);
  });

  test('a recording keeps whether it was made with speakers', () async {
    const setup = SpeechSetup(languages: {Lang.en}, speakers: true);
    final r = await repo.create(startedAt: DateTime(2026, 10, 15, 9), setup: setup);
    expect((await repo.get(r.id))!.setup.speakers, isTrue);
  });
}
