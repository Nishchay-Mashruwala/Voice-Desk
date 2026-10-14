import '../../data/transcript.dart';

/// Words and phrases the user never wants in a transcript (Settings → "Leave
/// out": "umm, uh, the the"), as on the desktop (desktop/backend/core/src/omit.rs).
///
/// An entry matches whole words, ignoring case and the punctuation around them
/// ("Umm," matches "umm"); a phrase matches those words in a row. A repeated
/// word ("the the") is a stutter: it becomes one "the". A phrase's text and
/// its word timings lose the same words, so playback highlighting stays in step.
class LeaveOut {
  /// From the setting: entries separated by commas or new lines.
  LeaveOut(String setting) {
    final phrases = setting
        .split(RegExp(r'[,\n]'))
        .map((entry) => entry.split(RegExp(r'\s+')).map(_norm).where((w) => w.isNotEmpty).toList())
        .where((p) => p.isNotEmpty)
        .toList()
      // Longest first, so "the the" wins over "the".
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final p in phrases) {
      if (!_phrases.any((q) => _same(p, q))) _phrases.add(p);
    }
  }

  final _phrases = <List<String>>[];

  bool get isEmpty => _phrases.isEmpty;

  /// Text with the words left out (words are separated by spaces again).
  String text(String text) {
    if (isEmpty) return text;
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final (keep, fixed) = _apply(words);
    return [
      for (var i = 0; i < words.length; i++)
        if (keep[i]) fixed[i],
    ].join(' ');
  }

  /// The phrase with the words left out, or null when nothing is left.
  Phrase? phrase(Phrase p) {
    if (isEmpty) return p;
    if (p.words.isEmpty) {
      final text = this.text(p.text);
      return text.isEmpty ? null : Phrase(startMs: p.startMs, endMs: p.endMs, text: text, words: const []);
    }
    final (keep, fixed) = _apply([for (final w in p.words) w.text]);
    final words = [
      for (var i = 0; i < p.words.length; i++)
        if (keep[i]) Word(fixed[i], p.words[i].startMs, p.words[i].endMs),
    ];
    if (words.isEmpty) return null;
    return Phrase(startMs: p.startMs, endMs: p.endMs, text: words.map((w) => w.text).join(' '), words: words);
  }

  /// Which words stay, and each word as it should read. A sentence that ended
  /// on a removed word still ends ("ready, umm." → "ready."), and one that
  /// started on it starts with a capital ("Umm, the report" → "The report").
  (List<bool>, List<String>) _apply(List<String> words) {
    final fixed = List.of(words);
    if (words.isEmpty) return (<bool>[], fixed);
    final keep = _keep(words.map(_norm).toList());
    String? mark; // the sentence end among words being left out ("umm.")
    var capitalize = false; // a sentence started on a word left out ("Uh, next")
    int? last; // the last word kept

    void endWith(String mark) {
      final prev = last;
      if (prev == null || _endsSentence(fixed[prev])) return;
      fixed[prev] = fixed[prev].replaceFirst(RegExp(r'''[^\p{L}\p{N}'")]+$''', unicode: true), '') + mark;
    }

    for (var i = 0; i < words.length; i++) {
      final startsSentence = i == 0 || _endsSentence(words[i - 1]);
      if (!keep[i]) {
        if (startsSentence && words[i].isNotEmpty && _isUpper(words[i][0])) capitalize = true;
        if (_endsSentence(words[i])) {
          final w = words[i].replaceFirst(RegExp(r'''["')]+$'''), '');
          mark = w.substring(w.replaceFirst(RegExp(r'[.?!…]+$'), '').length);
          capitalize = false;
        }
        continue;
      }
      if (mark != null) {
        endWith(mark);
        mark = null;
      }
      if (capitalize) {
        capitalize = false;
        final s = fixed[i];
        if (s.isNotEmpty && _isLower(s[0])) fixed[i] = s[0].toUpperCase() + s.substring(1);
      }
      last = i;
    }
    if (mark != null) endWith(mark);
    return (keep, fixed);
  }

  /// For each word: keep it, or leave it out. A repeated word ("the the") is a
  /// stutter: one stays, however many times it was said.
  List<bool> _keep(List<String> words) {
    final keep = List.filled(words.length, true);
    var i = 0;
    while (i < words.length) {
      final p = _phrases.where((p) => words.length - i >= p.length && _same(words.sublist(i, i + p.length), p)).firstOrNull;
      if (p == null) {
        i++;
        continue;
      }
      final stutter = p.length > 1 && p.every((w) => w == p[0]);
      var end = i + p.length;
      if (stutter) {
        while (end < words.length && words[end] == p[0]) {
          end++;
        }
        i++; // the first one stays
      }
      for (var k = i; k < end; k++) {
        keep[k] = false;
      }
      i = end;
    }
    return keep;
  }
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A word as it's compared: lowercase, without the punctuation around it.
String _norm(String word) =>
    word.replaceAll(RegExp(r"^[^\p{L}\p{N}']+|[^\p{L}\p{N}']+$", unicode: true), '').toLowerCase();

/// Ends a sentence ("ready." "ready?" "ready!").
bool _endsSentence(String word) => RegExp(r'''[.?!…]["')]*$''').hasMatch(word);

bool _isUpper(String c) => c != c.toLowerCase() && c == c.toUpperCase();
bool _isLower(String c) => c != c.toUpperCase() && c == c.toLowerCase();
