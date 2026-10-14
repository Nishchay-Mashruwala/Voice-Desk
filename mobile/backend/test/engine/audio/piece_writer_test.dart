import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/audio/piece_writer.dart';
import 'package:path/path.dart' as p;

void main() {
  test('splits at pieceBytes and names pieces in order', () async {
    final dir = Directory.systemTemp.createTempSync();
    final w = PieceWriter(dir, pieceBytes: 1000);
    await w.add(Uint8List(700));
    await w.add(Uint8List(700)); // crosses into piece 2 mid-chunk
    await w.add(Uint8List(700)); // crosses into piece 3
    final pieces = await w.close();
    expect(pieces.map((f) => p.basename(f.path)), ['piece-000.wav', 'piece-001.wav', 'piece-002.wav']);
    expect(pieces.map((f) => f.lengthSync() - 44), [1000, 1000, 100]);
    expect(w.dataBytes, 2100);
  });

  test('every closed piece has a valid header', () async {
    final dir = Directory.systemTemp.createTempSync();
    final w = PieceWriter(dir, pieceBytes: 1000);
    await w.add(Uint8List(1500));
    for (final f in await w.close()) {
      expect(ByteData.sublistView(f.readAsBytesSync()).getUint32(40, Endian.little), f.lengthSync() - 44);
    }
  });

  test('a piece is on disk before close (crash-safe)', () async {
    final dir = Directory.systemTemp.createTempSync();
    final w = PieceWriter(dir, pieceBytes: 1000);
    await w.add(Uint8List(1200));
    expect(File('${dir.path}/piece-000.wav').lengthSync(), 1044);
  });

  test('onPieceFinished reports each finished piece', () async {
    final dir = Directory.systemTemp.createTempSync();
    final finished = <int>[];
    final w = PieceWriter(dir, pieceBytes: 16000)..onPieceFinished = finished.add;
    await w.add(Uint8List(48000)); // three full pieces; the last is still open
    expect(finished, [1, 2]);
    final firstTwo = (await w.close()).take(2);
    expect(firstTwo.every((f) => f.lengthSync() == 16044), isTrue);
  });
}
