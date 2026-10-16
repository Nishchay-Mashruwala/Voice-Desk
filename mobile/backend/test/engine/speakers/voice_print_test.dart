import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/speakers/voice_print.dart';

Float32List vec(List<double> xs) => Float32List.fromList(xs);

void main() {
  test('a short phrase is one piece, a long one 1.5 s windows, a tiny one none', () {
    expect(printPieces(1000, 3000), [(1000, 3000)]);
    expect(printPieces(0, 3000), [(0, 3000)]);
    expect(printPieces(0, 4200), [(0, 1500), (750, 2250), (1500, 3000), (2250, 3750), (2700, 4200)]);
    // 4000 ms: the last 250 ms aren't worth a window of their own.
    expect(printPieces(0, 4000), [(0, 1500), (750, 2250), (1500, 3000), (2250, 3750)]);
    expect(printPieces(500, 800), isEmpty);
  });

  test('prints round-trip through text', () {
    final p = vec([0.25, -0.5, 1e-7, 3.75]);
    expect(decodePrint(encodePrint(p)), p);
  });

  test('similarity and the weighted mean', () {
    final a = vec([1, 0]), b = vec([0, 1]);
    expect(similarity(a, a), closeTo(1, 1e-6));
    expect(similarity(a, b), closeTo(0, 1e-6));
    final m = meanPrint([(a, 3000), (b, 1000)]);
    expect(m[0], closeTo(3 / sqrt(10), 1e-6)); // (3, 1) normalised
    expect(m[1], closeTo(1 / sqrt(10), 1e-6));
  });
}
