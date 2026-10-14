import 'dart:io';
import 'dart:typed_data';

/// The models' input format: 16 kHz, mono, 16-bit PCM.
const kSampleRate = 16000;
const kBytesPerSecond = kSampleRate * 2;
const kWavHeaderBytes = 44;

/// A WAV header for [dataBytes] of 16 kHz mono 16-bit PCM.
Uint8List wavHeader(int dataBytes) {
  final b = ByteData(kWavHeaderBytes);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // fmt chunk size
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, kSampleRate, Endian.little);
  b.setUint32(28, kBytesPerSecond, Endian.little); // byte rate
  b.setUint16(32, 2, Endian.little); // block align
  b.setUint16(34, 16, Endian.little); // bits per sample
  tag(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  return b.buffer.asUint8List();
}

/// Make the header match the file's length: a piece cut off by a crash still
/// says "0 bytes". A file too short for a header becomes an empty WAV.
Future<void> finalizeWav(File f) async {
  final length = await f.length();
  final raf = await f.open(mode: FileMode.append);
  try {
    if (length < kWavHeaderBytes) {
      await raf.truncate(0);
      await raf.setPosition(0);
      await raf.writeFrom(wavHeader(0));
      return;
    }
    await raf.setPosition(0);
    await raf.writeFrom(wavHeader(length - kWavHeaderBytes));
  } finally {
    await raf.close();
  }
}

/// How long a 16 kHz mono 16-bit WAV file plays.
Duration wavDuration(File f) {
  final data = f.lengthSync() - kWavHeaderBytes;
  if (data <= 0) return Duration.zero;
  return Duration(microseconds: data * Duration.microsecondsPerSecond ~/ kBytesPerSecond);
}
