import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// A voice print (192 numbers, length 1) of the audio from [startMs] to [endMs].
class VoicePiece {
  const VoicePiece(this.startMs, this.endMs, this.print);
  final int startMs;
  final int endMs;
  final Float32List print;

  int get ms => endMs - startMs;
}

/// Phrases shorter than this get no voice print (too little to go by).
const kMinPrintMs = 400;

/// A phrase up to this long is one piece; longer ones are cut in windows, so a
/// change of speaker inside it is found.
const kWholePrintMs = 3000;
const kWindowMs = 1500;
const kWindowStepMs = 750;

/// A last window ending at the phrase's end, when more than this would be left out.
const kTailMs = 300;

/// The stretches of a phrase to make voice prints of (ms).
List<(int, int)> printPieces(int startMs, int endMs) {
  final length = endMs - startMs;
  if (length < kMinPrintMs) return const [];
  if (length <= kWholePrintMs) return [(startMs, endMs)];
  final out = <(int, int)>[];
  var at = startMs;
  while (at + kWindowMs <= endMs) {
    out.add((at, at + kWindowMs));
    at += kWindowStepMs;
  }
  if (endMs - out.last.$2 > kTailMs) out.add((endMs - kWindowMs, endMs));
  return out;
}

/// Cosine similarity of two prints of length 1 (their dot product).
double similarity(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length && i < b.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

/// [v] scaled to length 1.
Float32List normalised(Float32List v) {
  final n = sqrt(v.fold(0.0, (s, x) => s + x * x));
  return n == 0 ? v : Float32List.fromList([for (final x in v) x / n]);
}

/// The mean of prints, each counted by its weight (its speech time), length 1.
Float32List meanPrint(List<(Float32List, int)> prints) {
  final sum = Float32List(prints.isEmpty ? 0 : prints.first.$1.length);
  for (final (p, w) in prints) {
    for (var i = 0; i < sum.length; i++) {
      sum[i] += p[i] * w;
    }
  }
  return normalised(sum);
}

/// A print as text (base64 of its float32 bytes, little-endian).
String encodePrint(Float32List p) {
  final bytes = ByteData(p.length * 4);
  for (var i = 0; i < p.length; i++) {
    bytes.setFloat32(i * 4, p[i], Endian.little);
  }
  return base64Encode(bytes.buffer.asUint8List());
}

Float32List decodePrint(String text) {
  final bytes = ByteData.sublistView(base64Decode(text));
  return Float32List.fromList([for (var i = 0; i < bytes.lengthInBytes ~/ 4; i++) bytes.getFloat32(i * 4, Endian.little)]);
}
