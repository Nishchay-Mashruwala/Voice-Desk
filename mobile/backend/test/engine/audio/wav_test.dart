import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/audio/wav.dart';

void main() {
  test('header describes 16 kHz mono 16-bit PCM', () {
    final h = ByteData.sublistView(wavHeader(32000));
    expect(String.fromCharCodes(wavHeader(0).sublist(0, 4)), 'RIFF');
    expect(h.getUint32(4, Endian.little), 36 + 32000);
    expect(h.getUint16(22, Endian.little), 1); // channels
    expect(h.getUint32(24, Endian.little), 16000); // sample rate
    expect(h.getUint16(34, Endian.little), 16); // bits
    expect(h.getUint32(40, Endian.little), 32000); // data bytes
  });

  test('finalizeWav repairs a piece cut off by a crash', () async {
    final f = File('${Directory.systemTemp.createTempSync().path}/p.wav');
    await f.writeAsBytes([...wavHeader(0), ...List.filled(64000, 1)]); // header says 0 data bytes
    await finalizeWav(f);
    final h = ByteData.sublistView(await f.readAsBytes());
    expect(h.getUint32(40, Endian.little), 64000);
    expect(wavDuration(f), const Duration(seconds: 2));
  });

  test('finalizeWav turns a truncated header into an empty WAV', () async {
    final f = File('${Directory.systemTemp.createTempSync().path}/p.wav')..writeAsBytesSync([1, 2, 3]);
    await finalizeWav(f);
    expect(f.lengthSync(), 44);
    expect(wavDuration(f), Duration.zero);
  });
}
