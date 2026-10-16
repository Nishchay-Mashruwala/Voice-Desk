import 'dart:math';

import '../../data/transcript.dart';

/// Turns a recognizer's tokens into timed words. [timestamps] are seconds from
/// the segment's start, one per token. A token starting with `▁` or a space
/// starts a word; any other (incl. punctuation) continues the word before. A
/// word lasts until the next word starts; the last one until [endMs].
///
/// With [logProbs] (one per token), a word's confidence is its weakest
/// token's probability; punctuation tokens don't count.
Phrase phraseFromTokens(List<String> tokens, List<double> timestamps,
    {required int startMs, required int endMs, List<double>? logProbs}) {
  final scored = logProbs != null && logProbs.length == tokens.length;
  final texts = <String>[];
  final starts = <int>[];
  final confs = <double?>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    final at = startMs + (timestamps[i] * 1000).round();
    final newWord = texts.isEmpty || t.startsWith('▁') || t.startsWith(' ');
    final piece = t.replaceFirst(RegExp('^[▁ ]+'), '');
    final p = scored && _spoken.hasMatch(piece) ? exp(logProbs[i]) : null;
    if (newWord) {
      texts.add(piece);
      starts.add(at);
      confs.add(p);
    } else {
      texts[texts.length - 1] += piece;
      final c = confs.last;
      if (p != null) confs[confs.length - 1] = c == null ? p : min(c, p);
    }
  }
  final words = <Word>[
    for (var i = 0; i < texts.length; i++)
      if (texts[i].isNotEmpty) Word(texts[i], starts[i], i + 1 < starts.length ? starts[i + 1] : endMs, confs[i]),
  ];
  return Phrase(startMs: startMs, endMs: endMs, text: words.map((w) => w.text).join(' '), words: words);
}

/// A letter or digit in any script: a token that is said, not punctuation.
final _spoken = RegExp(r'[\p{L}\p{N}]', unicode: true);
