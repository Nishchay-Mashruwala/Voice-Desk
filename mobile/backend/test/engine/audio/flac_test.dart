import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/audio/flac.dart';
import 'package:mobile_backend/engine/audio/wav.dart';

final _rng = Random(1);
Int16List silence(int n) => Int16List(n);
Int16List tone(int n, {int noise = 0}) => Int16List.fromList([
      for (var i = 0; i < n; i++)
        (8000 * sin(2 * pi * 440 * i / 16000) + (noise == 0 ? 0 : _rng.nextInt(2 * noise + 1) - noise)).round(),
    ]);
Int16List noise(int n) => Int16List.fromList([for (var i = 0; i < n; i++) _rng.nextInt(40001) - 20000]);

/// [samples] in chunks of about 1 s, as the pieces are read.
Stream<Int16List> chunks(Int16List samples) async* {
  for (var at = 0; at < samples.length; at += 16000) {
    yield Int16List.sublistView(samples, at, min(at + 16000, samples.length));
  }
}

Future<Int16List> readAll(File f, {int fromSample = 0}) async {
  final out = <int>[];
  await for (final frame in readFlac(f, fromSample: fromSample)) {
    out.addAll(frame);
  }
  return Int16List.fromList(out);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('flac'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<File> write(Int16List samples, [String name = 'a.flac']) async {
    final f = File('${dir.path}/$name');
    await writeFlac(chunks(samples), f, totalSamples: samples.length);
    return f;
  }

  test('silence, a tone and noise come back exactly', () async {
    for (final (name, s) in [
      ('silence', silence(160000)),
      ('tone', tone(160000)),
      ('noise', noise(160000)),
      ('short last frame', tone(4096 * 3 + 17, noise: 300)),
      ('under one frame', noise(1000)),
    ]) {
      final f = await write(s, '$name.flac');
      expect(await readAll(f), s, reason: name);
      expect((await readFlacInfo(f)).totalSamples, s.length, reason: name);
      expect(flacDuration(f), Duration(microseconds: s.length * 1000000 ~/ 16000), reason: name);
    }
  });

  test('speech is smaller than the WAV', () async {
    final s = tone(20 * 16000, noise: 200);
    final f = await write(s);
    expect(f.lengthSync(), lessThan(0.75 * 20 * kBytesPerSecond));
  });

  test('the seek table has a point at the frame of every 10 s mark from the start', () async {
    final s = tone(35 * 16000, noise: 100);
    final f = await write(s);
    final info = await readFlacInfo(f);
    expect([for (final (sample, _) in info.seekPoints) sample], [0, 159744, 319488, 479232]);
    // Each offset is where that frame starts: reading from there gives its samples.
    for (final (sample, offset) in info.seekPoints) {
      expect(offset, sample ~/ kFlacBlock == 0 ? 0 : greaterThan(0));
      expect((await readAll(f, fromSample: sample)).take(5).toList(), s.sublist(sample, sample + 5));
    }
  });

  test('reading from a sample gives the samples from there', () async {
    final s = tone(30 * 16000, noise: 500);
    final f = await write(s);
    expect(await readAll(f, fromSample: 170001), s.sublist(170001));
    expect(await readAll(f, fromSample: s.length - 3), s.sublist(s.length - 3));
  });

  test('a damaged frame is noticed', () async {
    final s = tone(3 * 16000, noise: 500);
    final f = await write(s);
    final bytes = f.readAsBytesSync();
    final info = await readFlacInfo(f);
    bytes[info.firstFrameOffset + 4000] ^= 0x10;
    f.writeAsBytesSync(bytes);
    await expectLater(readAll(f), throwsA(isA<FormatException>()));
  });

  test("a file that isn't ours is refused", () async {
    final f = File('${dir.path}/x.flac')..writeAsBytesSync([for (var i = 0; i < 500; i++) _rng.nextInt(256)]);
    await expectLater(readFlacInfo(f), throwsA(isA<FormatException>()));
  });

  test('a stream of another length than promised is an error', () async {
    final f = File('${dir.path}/b.flac');
    await expectLater(writeFlac(chunks(tone(1000)), f, totalSamples: 2000), throwsStateError);
  });

  // VOICEDESK_TEST_AUDIO: the owner's recordings; VOICEDESK_FLAC_DIR: where to
  // leave the FLAC for tool/flac_check.py (libsndfile) to read.
  final audio = Platform.environment['VOICEDESK_TEST_AUDIO'];
  test('real speech round-trips', () async {
    final wav = File('$audio/rec17.wav').readAsBytesSync();
    final pcm = Int16List.fromList(wav.buffer.asInt16List(kWavHeaderBytes, (wav.length - kWavHeaderBytes) ~/ 2));
    final out = Platform.environment['VOICEDESK_FLAC_DIR'] ?? dir.path;
    final f = await write(pcm, 'x.flac');
    expect(await readAll(f), pcm);
    f.copySync('$out/rec17.flac');
    // ignore: avoid_print
    print('rec17: FLAC ${(100 * f.lengthSync() / wav.length).round()}% of the WAV');
  }, skip: audio == null ? 'set VOICEDESK_TEST_AUDIO' : false);

  test('2,100 frames of full-scale sound come back exactly (frame numbers past 0x7FF)', () async {
    final n = 2100 * kFlacBlock + 1234;
    final s = Int16List(n);
    for (var i = 0; i < n; i++) {
      s[i] = switch (i ~/ 160000 % 3) {
        0 => i.isEven ? 32767 : -32768,
        1 => _rng.nextInt(65536) - 32768,
        _ => (32767 * sin(i / 3)).round(),
      };
    }
    final f = await write(s);
    expect(await readAll(f), s);
    expect(await readAll(f, fromSample: 2048 * kFlacBlock + 5), s.sublist(2048 * kFlacBlock + 5));
  });

  test("its CRCs are FLAC's (check values of RFC 9639's polynomials)", () {
    final digits = Uint8List.fromList('123456789'.codeUnits);
    expect(flacCrc8(digits), 0xF4);
    expect(flacCrc16(digits), 0xFEE8);
  });
}
