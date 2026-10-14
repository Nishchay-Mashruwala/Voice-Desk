import '../../data/transcript.dart';

/// Turns a recognizer's tokens into timed words. [timestamps] are seconds from
/// the segment's start, one per token. A token starting with `▁` or a space
/// starts a word; any other (incl. punctuation) continues the word before. A
/// word lasts until the next word starts; the last one until [endMs].
Phrase phraseFromTokens(List<String> tokens, List<double> timestamps, {required int startMs, required int endMs}) {
  final texts = <String>[];
  final starts = <int>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    final at = startMs + (timestamps[i] * 1000).round();
    final newWord = texts.isEmpty || t.startsWith('▁') || t.startsWith(' ');
    final piece = t.replaceFirst(RegExp('^[▁ ]+'), '');
    if (newWord) {
      texts.add(piece);
      starts.add(at);
    } else {
      texts[texts.length - 1] += piece;
    }
  }
  final words = <Word>[
    for (var i = 0; i < texts.length; i++)
      if (texts[i].isNotEmpty) Word(texts[i], starts[i], i + 1 < starts.length ? starts[i + 1] : endMs),
  ];
  return Phrase(startMs: startMs, endMs: endMs, text: words.map((w) => w.text).join(' '), words: words);
}
