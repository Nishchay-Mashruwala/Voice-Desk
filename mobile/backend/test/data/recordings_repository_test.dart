import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/engine/audio/wav.dart';

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
}
