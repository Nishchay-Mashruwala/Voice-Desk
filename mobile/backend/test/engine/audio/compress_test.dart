import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/engine/audio/compress.dart';
import 'package:mobile_backend/engine/audio/flac.dart';
import 'package:mobile_backend/engine/audio/pcm_reader.dart';
import 'package:mobile_backend/engine/audio/wav.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';

/// A WAV piece of [seconds] of a sound counting up from [first].
File piece(Directory dir, String name, double seconds, int first) {
  final n = (seconds * 16000).round();
  final pcm = Int16List.fromList([for (var i = 0; i < n; i++) (first + i * 7) % 20000 - 10000]);
  return File('${dir.path}/$name')..writeAsBytesSync([...wavHeader(n * 2), ...pcm.buffer.asUint8List()]);
}

Future<List<double>> samples(List<File> files) async => [await for (final c in readSamples(files, fromMs: 0)) ...c];

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('compress'));
  tearDown(() => dir.deleteSync(recursive: true));

  List<File> threePieces() =>
      [piece(dir, 'piece-000.wav', 1, 0), piece(dir, 'piece-001.wav', 1.5, 3), piece(dir, 'piece-002.wav', 0.4, 9)];

  test("the pieces become one FLAC with the same samples; the pieces aren't touched", () async {
    final pieces = threePieces();
    expect(await compressPieces(pieces, dir), isTrue);
    final flac = File('${dir.path}/$kFlacName');
    expect(await samples([flac]), await samples(pieces));
    expect(pieces.every((p) => p.existsSync()), isTrue);
    expect(File('${dir.path}/$kFlacName.part').existsSync(), isFalse);
  });

  test("a FLAC that doesn't match is not kept", () async {
    final pieces = threePieces();
    // A writer that gets one sample wrong.
    Future<void> wrong(Stream<Int16List> s, File out, {required int totalSamples}) => writeFlac(
        s.map((c) => Int16List.fromList(c)..[0] = c[0] + 1), out, totalSamples: totalSamples);
    expect(await compressPieces(pieces, dir, write: wrong), isFalse);
    expect(File('${dir.path}/$kFlacName').existsSync(), isFalse);
    expect(File('${dir.path}/$kFlacName.part').existsSync(), isFalse);
    expect(pieces.every((p) => p.existsSync()), isTrue);
  });

  test('an existing FLAC that matches is kept; one that does not is made again', () async {
    final pieces = threePieces();
    expect(await compressPieces(pieces, dir), isTrue);
    final flac = File('${dir.path}/$kFlacName');
    final before = flac.lastModifiedSync();
    expect(await compressPieces(pieces, dir), isTrue);
    expect(flac.lastModifiedSync(), before, reason: 'checked, not written again');
    flac.writeAsBytesSync(flac.readAsBytesSync().sublist(0, 200)); // cut short (a power cut)
    expect(await compressPieces(pieces, dir), isTrue);
    expect(await samples([flac]), await samples(pieces));
  });

  test('a half-written FLAC from a killed app is redone', () async {
    final pieces = threePieces();
    File('${dir.path}/$kFlacName.part').writeAsBytesSync([1, 2, 3]);
    expect(await compressPieces(pieces, dir), isTrue);
    expect(await samples([File('${dir.path}/$kFlacName')]), await samples(pieces));
  });

  group('the repository', () {
    late AppDatabase db;
    late LocalRecordingsRepository repo;
    late Directory root;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      root = Directory.systemTemp.createTempSync('rec');
      repo = LocalRecordingsRepository(db, root);
    });
    tearDown(() async {
      await db.close();
      root.deleteSync(recursive: true);
    });

    Future<int> withPieces(RecordingStatus status) async {
      final r = await repo.create(startedAt: DateTime(2026, 10, 15));
      final d = await repo.audioDir(r.id);
      piece(d, 'piece-000.wav', 1, 0);
      await repo.setStatus(r.id, status);
      return r.id;
    }

    test('recordings still to be processed are not compressed', () async {
      final done = await withPieces(RecordingStatus.done);
      final failed = await withPieces(RecordingStatus.error);
      for (final s in [RecordingStatus.queued, RecordingStatus.processing, RecordingStatus.waitingCharge, RecordingStatus.recording]) {
        await withPieces(s);
      }
      expect([for (final r in await repo.toCompress()) r.id], [done, failed]);
    });

    test('once compressed the pieces go and the FLAC is its audio', () async {
      final id = await withPieces(RecordingStatus.done);
      final d = await repo.audioDir(id);
      expect(await compressPieces(await repo.wavPieces(id), d), isTrue);
      await repo.compressed(id);
      expect(d.listSync().map((f) => f.uri.pathSegments.last), [kFlacName]);
      expect(await repo.toCompress(), isEmpty);
    });

    test('a recording processed again meanwhile keeps its pieces until it is done', () async {
      final id = await withPieces(RecordingStatus.done);
      final d = await repo.audioDir(id);
      expect(await compressPieces(await repo.wavPieces(id), d), isTrue);
      await repo.setStatus(id, RecordingStatus.queued);
      await repo.compressed(id);
      expect(await repo.wavPieces(id), hasLength(1));
      expect([for (final f in await repo.pieces(id)) f.path], [for (final f in await repo.wavPieces(id)) f.path],
          reason: 'the job reads the pieces while they are there');
    });

    test('Process again is refused without audio, and the text stays', () async {
      final id = await withPieces(RecordingStatus.done);
      await repo.deleteAudio(id);
      await expectLater(repo.processAgain(id, SpeechSetup.englishOnly), throwsA(isA<NoAudio>()));
      final r = (await repo.get(id))!;
      expect((r.status, r.reprocessing), (RecordingStatus.done, false));
    });

    test('audio is deleted only from a done recording', () async {
      final id = await withPieces(RecordingStatus.queued);
      await repo.deleteAudio(id);
      expect(await repo.wavPieces(id), hasLength(1));
      expect((await repo.get(id))!.audioDeleted, isFalse);
    });

    test('folders left without a recording are removed at start', () async {
      final kept = await withPieces(RecordingStatus.done);
      final orphan = Directory('${root.path}/999')..createSync();
      File('${orphan.path}/piece-000.wav').writeAsBytesSync(wavHeader(0));
      Directory('${root.path}/not-a-recording').createSync();
      await repo.removeOrphanFolders();
      expect(orphan.existsSync(), isFalse);
      expect(Directory('${root.path}/$kept').existsSync(), isTrue);
      expect(Directory('${root.path}/not-a-recording').existsSync(), isTrue, reason: 'only numbered folders');
    });

    test('after three failures it says so and stops trying', () async {
      final id = await withPieces(RecordingStatus.done);
      for (var i = 0; i < 3; i++) {
        expect((await repo.get(id))!.compressFailed, isFalse);
        await repo.countCompressFailure(id);
      }
      expect((await repo.get(id))!.compressFailed, isTrue);
      expect(await repo.toCompress(), isEmpty);
    });
  });
}
