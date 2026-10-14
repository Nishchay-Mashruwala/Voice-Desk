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
}
