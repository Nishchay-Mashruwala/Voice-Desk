import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'wav.dart';

const _bytesPerMs = kBytesPerSecond ~/ 1000;

/// The recording's length in ms, from its pieces.
int totalMs(List<File> pieces) => pieces.fold(0, (sum, p) => sum + wavDuration(p).inMilliseconds);

/// The pieces' 16-bit samples as floats (-1..1), from [fromMs] to [toMs] (or
/// the end), in chunks of at most [chunkMs]. Reads a chunk at a time, never the
/// whole recording.
Stream<Float32List> readSamples(List<File> pieces, {required int fromMs, int? toMs, int chunkMs = 10000}) async* {
  var pieceStart = 0; // ms where the current piece starts
  final end = toMs ?? totalMs(pieces);
  for (final piece in pieces) {
    final pieceMs = wavDuration(piece).inMilliseconds;
    final pieceEnd = pieceStart + pieceMs;
    final from = max(fromMs, pieceStart);
    final to = min(end, pieceEnd);
    if (from < to) {
      final raf = await piece.open();
      try {
        var at = from;
        while (at < to) {
          final n = min(chunkMs, to - at);
          await raf.setPosition(kWavHeaderBytes + (at - pieceStart) * _bytesPerMs);
          final bytes = await raf.read(n * _bytesPerMs);
          final pcm = bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.length ~/ 2);
          final out = Float32List(pcm.length);
          for (var i = 0; i < pcm.length; i++) {
            out[i] = pcm[i] / 32768;
          }
          yield out;
          at += n;
        }
      } finally {
        await raf.close();
      }
    }
    pieceStart = pieceEnd;
    if (pieceStart >= end) break;
  }
}
