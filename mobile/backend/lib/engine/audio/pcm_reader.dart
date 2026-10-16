import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'flac.dart';
import 'wav.dart';

const _bytesPerMs = kBytesPerSecond ~/ 1000;

/// The recording's length in ms, from its pieces (or its FLAC).
int totalMs(List<File> pieces) => pieces.fold(0, (sum, p) => sum + audioDuration(p).inMilliseconds);

/// The pieces' (or the FLAC's) 16-bit samples as floats (-1..1), from [fromMs]
/// to [toMs] (or the end), in chunks of at most [chunkMs]. Reads a chunk at a
/// time, never the whole recording.
Stream<Float32List> readSamples(List<File> pieces, {required int fromMs, int? toMs, int chunkMs = 10000}) async* {
  var pieceStart = 0; // ms where the current piece starts
  final end = toMs ?? totalMs(pieces);
  for (final piece in pieces) {
    final pieceMs = audioDuration(piece).inMilliseconds;
    final pieceEnd = pieceStart + pieceMs;
    final from = max(fromMs, pieceStart);
    final to = min(end, pieceEnd);
    if (from < to && piece.path.endsWith('.flac')) {
      yield* _flacSamples(piece, (from - pieceStart) * _samplesPerMs, (to - pieceStart) * _samplesPerMs,
          chunkMs * _samplesPerMs);
    } else if (from < to) {
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

const _samplesPerMs = kSampleRate ~/ 1000;

/// A FLAC's samples [from] ≤ i < [to], as floats, in chunks of [chunk].
Stream<Float32List> _flacSamples(File flac, int from, int to, int chunk) async* {
  var out = Float32List(min(chunk, to - from));
  var filled = 0, at = from;
  await for (final frame in readFlac(flac, fromSample: from)) {
    for (var i = 0; i < frame.length && at < to; i++, at++) {
      out[filled++] = frame[i] / 32768;
      if (filled == out.length) {
        yield out;
        filled = 0;
        out = Float32List(min(chunk, to - at - 1));
      }
    }
    if (at >= to) break;
  }
  if (filled > 0) yield Float32List.sublistView(out, 0, filled);
}
