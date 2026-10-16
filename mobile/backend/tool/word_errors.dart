/// Counting words wrong against the right words (for measuring speech
/// recognition on the owner's test set; not part of the app).
library;

final _notWord = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);

/// The words of [text], lowercased, punctuation dropped.
List<String> wordsOf(String text) => [
      for (final w in text.toLowerCase().split(_notWord))
        if (w.isNotEmpty) w,
    ];

/// Words substituted, missing or extra in [heard] compared with [reference]
/// (edit distance over words).
int wordErrors(String reference, String heard) {
  final a = wordsOf(reference), b = wordsOf(heard);
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = [i];
    for (var j = 1; j <= b.length; j++) {
      final sub = prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final del = prev[j] + 1, ins = cur[j - 1] + 1;
      cur.add(sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins));
    }
    prev = cur;
  }
  return prev.last;
}
