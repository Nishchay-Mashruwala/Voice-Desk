import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/audio/pcm_reader.dart';
import 'package:mobile_backend/engine/audio/wav.dart';

/// A piece of [samples] 16-bit samples counting up from [first].
File piece(Directory dir, String name, int samples, int first) {
  final pcm = Int16List(samples);
  for (var i = 0; i < samples; i++) {
    pcm[i] = (first + i) % 30000;
  }
  final f = File('${dir.path}/$name')..writeAsBytesSync([...wavHeader(samples * 2), ...pcm.buffer.asUint8List()]);
  return f;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('pcm'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Float32List> all(Stream<Float32List> s) async {
    final out = <double>[];
    await for (final c in s) {
      out.addAll(c);
    }
    return Float32List.fromList(out);
  }

  test('reads from a point inside the second piece', () async {
    final pieces = [piece(dir, 'piece-000.wav', 16000, 0), piece(dir, 'piece-001.wav', 16000, 16000)];
    final got = await all(readSamples(pieces, fromMs: 1500));
    expect(got.length, 8000);
    expect(got.first, closeTo((16000 + 8000) / 32768, 1e-6));
  });

  test('stops at toMs', () async {
    final pieces = [piece(dir, 'piece-000.wav', 16000, 0), piece(dir, 'piece-001.wav', 16000, 16000)];
    expect((await all(readSamples(pieces, fromMs: 0, toMs: 1250))).length, 20000);
  });

  test('chunks are at most chunkMs long', () async {
    final pieces = [piece(dir, 'piece-000.wav', 48000, 0)];
    final chunks = await readSamples(pieces, fromMs: 0, chunkMs: 1000).map((c) => c.length).toList();
    expect(chunks, [16000, 16000, 16000]);
  });

  test('totalMs adds the pieces', () {
    final pieces = [piece(dir, 'piece-000.wav', 16000, 0), piece(dir, 'piece-001.wav', 8000, 0)];
    expect(totalMs(pieces), 1500);
  });
}
