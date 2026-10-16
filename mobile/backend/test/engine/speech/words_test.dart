import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/speech/words.dart';

void main() {
  test('joins pieces into words with times', () {
    final p = phraseFromTokens(['▁hel', 'lo', '▁world'], [0.0, 0.2, 0.48], startMs: 1000, endMs: 2000);
    expect(p.words, [const Word('hello', 1000, 1480), const Word('world', 1480, 2000)]);
    expect(p.text, 'hello world');
    expect((p.startMs, p.endMs), (1000, 2000));
  });

  test('punctuation stays on its word', () {
    final p = phraseFromTokens(['▁Yes', ',', '▁sure', '.'], [0.0, 0.3, 0.5, 0.9], startMs: 0, endMs: 1200);
    expect(p.text, 'Yes, sure.');
    expect(p.words.map((w) => w.text), ['Yes,', 'sure.']);
  });

  test('a space mark works like ▁', () {
    final p = phraseFromTokens([' Hi', ' there'], [0.0, 0.4], startMs: 0, endMs: 900);
    expect(p.text, 'Hi there');
  });

  test('no tokens gives an empty phrase over the segment', () {
    final p = phraseFromTokens([], [], startMs: 300, endMs: 800);
    expect(p.text, '');
    expect(p.words, isEmpty);
    expect((p.startMs, p.endMs), (300, 800));
  });

  test("a word's confidence is its weakest token's", () {
    final p = phraseFromTokens(['▁N', 'est', 'e', '.'], [0.0, 0.1, 0.2, 0.3],
        startMs: 0, endMs: 500, logProbs: [log(0.92), log(0.43), log(0.16), log(0.67)]);
    expect(p.words.single.text, 'Neste.');
    expect(p.words.single.conf, closeTo(0.16, 1e-9));
  });

  test("punctuation tokens don't lower a word's confidence", () {
    final p = phraseFromTokens(['▁it', '.'], [0.0, 0.2], startMs: 0, endMs: 400, logProbs: [log(0.93), log(0.49)]);
    expect(p.words.single.conf, closeTo(0.93, 1e-9));
  });

  test('no log probs gives no confidence', () {
    expect(phraseFromTokens(['▁hi'], [0.0], startMs: 0, endMs: 300).words.single.conf, isNull);
    expect(phraseFromTokens(['▁hi'], [0.0], startMs: 0, endMs: 300, logProbs: []).words.single.conf, isNull);
  });
}
