import 'transcript.dart';

final _notWord = RegExp(r'[^\p{L}\p{N}\p{M}]', unicode: true);

/// A word as compared: lowercase, letters, digits and marks only (Gujarati
/// vowel signs and the virama are part of the word; punctuation isn't).
String norm(String w) => w.toLowerCase().replaceAll(_notWord, '');

/// Word timings for edited text (the desktop's `retime_words`, in ms). Words
/// that didn't change keep their exact times and confidence (matched in
/// order, ignoring case and punctuation); new or changed words share the time
/// between their unchanged neighbours, or [startMs] / [endMs].
List<Word> retimeWords(List<Word> old, String text, int startMs, int endMs) {
  final next = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final a = [for (final w in old) norm(w.text)];
  final b = [for (final w in next) norm(w)];
  // Longest common subsequence: which new words are old words.
  final lcs = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lcs[i][j] = a[i].isNotEmpty && a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] > lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final matched = List<int?>.filled(b.length, null);
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (a[i].isNotEmpty && a[i] == b[j]) {
      matched[j] = i;
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }

  final out = <Word>[];
  j = 0;
  while (j < next.length) {
    final m = matched[j];
    if (m != null) {
      out.add(Word(next[j], old[m].startMs, old[m].endMs, old[m].conf));
      j++;
      continue;
    }
    // A run of new words: spread them between the neighbouring kept words.
    var k = j;
    while (k < next.length && matched[k] == null) {
      k++;
    }
    final from = out.isEmpty ? startMs : out.last.endMs;
    final to = k < next.length ? old[matched[k]!].startMs : endMs;
    final step = (to - from < 0 ? 0 : to - from) / (k - j);
    for (var x = j; x < k; x++) {
      final s = (from + step * (x - j)).round();
      out.add(Word(next[x], s, (from + step * (x - j + 1)).round()));
    }
    j = k;
  }
  return out;
}
