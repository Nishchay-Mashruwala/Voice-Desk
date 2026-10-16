import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/speech/sherpa_speech.dart';

void main() {
  test('padding stays within the audio and never overlaps the phrase before', () {
    // 300 ms = 4800 samples, before the phrase only.
    expect(paddedRange(start: 20000, end: 90000, floor: 0, fed: 200000), (15200, 90000));
    expect(paddedRange(start: 2000, end: 9000, floor: 0, fed: 20000), (0, 9000));
    // The phrase before ended at 16000: this one starts no earlier.
    expect(paddedRange(start: 20000, end: 90000, floor: 16000, fed: 200000), (16000, 90000));
    // Only 80000 samples given so far: the end stops there.
    expect(paddedRange(start: 20000, end: 90000, floor: 0, fed: 80000), (15200, 80000));
  });

  test("a resumed job's first phrase is padded only from its own audio", () {
    // The engine's audio starts at its sample 0 (the recording's processedMs).
    expect(paddedRange(start: 1600, end: 30000, floor: 0, fed: 50000), (0, 30000));
  });

  Phrase heard(List<double?> confs) => Phrase(
        startMs: 0,
        endMs: 1000,
        text: List.filled(confs.length, 'w').join(' '),
        words: [for (final (i, c) in confs.indexed) Word('w', i * 100, i * 100 + 100, c)],
      );

  test('a phrase is read again with padding only when the first reading is unsure', () {
    expect(readAgainPadded(heard([0.95, 0.93])), isFalse);
    expect(readAgainPadded(heard([0.88])), isFalse); // "…task then we will complete it" stays as heard
    expect(readAgainPadded(heard([0.95, 0.6])), isTrue); // mean 0.775
    expect(readAgainPadded(heard([])), isTrue); // heard nothing ("fine" cut off)
    expect(readAgainPadded(null), isTrue);
  });

  test('the surer reading is kept, the first one on a tie', () {
    final plain = heard([0.93, 0.93]);
    final padded = heard([0.6]);
    expect(moreSure(plain, padded), same(plain)); // "Good, good." 0.93 over "Day." 0.57
    expect(moreSure(heard([]), heard([0.86])).words.single.conf, 0.86); // "" over "Fine." 0.86
    final tie = heard([0.9]);
    expect(moreSure(tie, heard([0.9])), same(tie));
  });

  test('the history keeps the last seconds and cuts by sample number', () {
    final h = SampleHistory(maxSamples: 10);
    h.add(Float32List.fromList([for (var i = 0; i < 6; i++) i.toDouble()]));
    h.add(Float32List.fromList([for (var i = 6; i < 15; i++) i.toDouble()]));
    // Samples 0..14 were added; the last 10 (5..14) are kept.
    expect(h.start, 5);
    expect(h.end, 15);
    expect(h.slice(7, 10), [7.0, 8.0, 9.0]);
    // Asking for more than is kept gives what is there.
    expect(h.slice(2, 7), [5.0, 6.0]);
    expect(h.slice(14, 20), [14.0]);
  });

  test('the history keeps its samples right across many small adds, without copying all it holds each time', () {
    final h = SampleHistory(maxSamples: 71 * 16000);
    final clock = Stopwatch()..start();
    // 90 s of audio in the VAD's 512-sample windows, each sample numbered by its position.
    for (var at = 0; at < 90 * 16000; at += 512) {
      h.add(Float32List.fromList([for (var i = 0; i < 512; i++) (at + i).toDouble()]));
    }
    clock.stop();
    expect(h.end, (90 * 16000 + 511) ~/ 512 * 512); // whole windows
    expect(h.start, h.end - 71 * 16000);
    expect(h.slice(50 * 16000, 50 * 16000 + 3), [800000.0, 800001.0, 800002.0]);
    expect(h.slice(h.end - 2, h.end + 5), [(h.end - 2).toDouble(), (h.end - 1).toDouble()]);
    // Copying the whole buffer per window took seconds; a ring buffer takes milliseconds.
    expect(clock.elapsedMilliseconds, lessThan(500));
  });
}
