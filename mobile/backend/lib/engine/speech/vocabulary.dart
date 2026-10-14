import 'dart:math';

import '../../data/transcript.dart';

/// Ordinary English words (the desktop's bundled list: lowercase stems;
/// capitalised entries are names and don't count). An ordinary word is never
/// "corrected" into a vocabulary word: "prize" stays "prize" even with "Priya"
/// in the vocabulary.
class CommonWords {
  CommonWords(this._words);

  /// From the list's text: one word per line, `#` comments.
  factory CommonWords.parse(String text) => CommonWords({
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty && !line.startsWith('#') && line.trim() == line.trim().toLowerCase())
            line.trim(),
      });

  final Set<String> _words;

  static const _suffixes = ['ing', 'ies', 'ied', 'ers', 'es', 'ed', 'er', 'ly', 's', 'd'];

  /// Whether [word] (any case, punctuation ignored) is ordinary, also as an
  /// inflected form ("prizes", "finished").
  bool contains(String word) {
    final w = _letters(word);
    if (w.isEmpty || _words.contains(w)) return w.isNotEmpty;
    for (final s in _suffixes) {
      if (w.length - s.length >= 3 && w.endsWith(s)) {
        final stem = w.substring(0, w.length - s.length);
        if (_words.contains(stem) || ((s == 'ies' || s == 'ied') && _words.contains('${stem}y'))) return true;
      }
    }
    return false;
  }
}

/// The user's name and vocabulary: a heard word (or a few in a row) that
/// sounds very much like an entry becomes the entry as written. Cautious by
/// the owner's choice — it would rather miss a fix than change a right word:
/// - an exact match (letters only, any case or spacing) always counts;
/// - a sound-alike only for words that aren't ordinary English, of similar
///   length (within 25%), the same first two letters, and close spelling
///   (at most 40% of the letters different);
/// - entries under 4 letters only match exactly.
class Vocabulary {
  Vocabulary(List<String> entries, this._common)
      : _entries = [
          for (final e in {for (final e in entries) _letters(e): e.trim()}.entries)
            if (e.key.isNotEmpty) _Entry(e.value, e.key, e.value.split(RegExp(r'\s+')).length),
        ]..sort((a, b) => b.letters.length.compareTo(a.letters.length));

  /// Settings: the name (whole and each part of 3+ letters) and the vocabulary
  /// (entries separated by commas or new lines).
  factory Vocabulary.fromSettings({required String name, required String vocabulary, required CommonWords common}) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => _letters(p).length >= 3);
    return Vocabulary([
      ...vocabulary.split(RegExp(r'[,\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty),
      if (name.trim().isNotEmpty) name.trim(),
      if (parts.length > 1) ...parts,
    ], common);
  }

  final List<_Entry> _entries;
  final CommonWords _common;

  bool get isEmpty => _entries.isEmpty;

  Phrase apply(Phrase p) {
    if (isEmpty || p.words.isEmpty) return p;
    final out = <Word>[];
    var changed = false;
    var i = 0;
    while (i < p.words.length) {
      final match = _matchAt(p.words, i);
      if (match == null) {
        out.add(p.words[i]);
        i++;
        continue;
      }
      final (entry, n) = match;
      final first = p.words[i], last = p.words[i + n - 1];
      final lead = RegExp(r'^[^\p{L}\p{N}]*', unicode: true).firstMatch(first.text)!.group(0)!;
      final trail = RegExp(r'[^\p{L}\p{N}]*$', unicode: true).firstMatch(last.text)!.group(0)!;
      final text = '$lead${entry.text}$trail';
      if (n != 1 || text != first.text) changed = true;
      out.add(Word(text, first.startMs, last.endMs));
      i += n;
    }
    if (!changed) return p;
    return Phrase(startMs: p.startMs, endMs: p.endMs, text: out.map((w) => w.text).join(' '), words: out);
  }

  /// The entry the words from [i] are, and how many words it takes.
  (_Entry, int)? _matchAt(List<Word> words, int i) {
    for (final e in _entries) {
      for (final n in {e.words, e.words + 1, if (e.words > 1) e.words - 1}) {
        if (n < 1 || i + n > words.length) continue;
        final run = words.sublist(i, i + n);
        // Words aren't joined across a pause in the sentence ("Nish, chay").
        if (run.take(n - 1).any((w) => RegExp(r'[^\p{L}\p{N}]$', unicode: true).hasMatch(w.text))) continue;
        final heard = run.map((w) => _letters(w.text)).join();
        if (heard == e.letters) return (e, n);
        if (_soundsLike(heard, e.letters) && !run.any((w) => _common.contains(w.text))) return (e, n);
      }
    }
    return null;
  }

  static bool _soundsLike(String heard, String entry) {
    if (entry.length < 4 || heard.length < 4) return false;
    if (min(heard.length, entry.length) / max(heard.length, entry.length) < 0.75) return false;
    if (heard.substring(0, 2) != entry.substring(0, 2)) return false;
    return 1 - _distance(heard, entry) / max(heard.length, entry.length) >= 0.6;
  }
}

class _Entry {
  const _Entry(this.text, this.letters, this.words);
  final String text;
  final String letters;
  final int words;
}

/// Lowercase letters and digits only ("Voice Desk," → "voicedesk").
String _letters(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// Edit distance (insertions, deletions, substitutions).
int _distance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      cur[j] = min(min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return prev[b.length];
}
