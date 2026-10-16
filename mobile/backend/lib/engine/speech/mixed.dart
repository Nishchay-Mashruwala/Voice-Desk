/// English inside Hindi/Gujarati speech, written in English: a line-for-line
/// port of the desktop's `desktop/backend/engine/mixed.py` (times in ms).
///
/// The Indian model writes everything in its script, so English said in the
/// middle of Gujarati comes out spelled by sound ("અફકોર્સ" for "of course"),
/// and whole English sentences come out garbled or are dropped. The English
/// reader, on the same audio, writes those English parts right, but it
/// translates the Gujarati parts (and sometimes writes them in Latin letters).
///
/// So the two are combined by time and by sound:
/// - a Gujarati word is replaced by the English heard at the same moment when
///   they sound alike and the English words are real English words (a
///   Gujarati word and its translation don't sound alike: "ભૂખ" / "hungry");
/// - English the Indian model dropped (no words of its own at that time) is
///   put back when the English reader was confident about a run of real words.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A word of either reader. [p] is the English reader's confidence (1 when
/// unknown); [j] is, on English words placed in a line, their index among
/// the English reader's words.
@immutable
class MixWord {
  const MixWord(this.w, this.s, this.e, {this.lang = 'indic', this.p = 1.0, this.j});
  final String w;
  final int s;
  final int e;

  /// `en` or `indic`.
  final String lang;
  final double p;
  final int? j;

  MixWord copyWith({String? w, int? s, int? e, String? lang, int? j, bool dropJ = false}) =>
      MixWord(w ?? this.w, s ?? this.s, e ?? this.e, lang: lang ?? this.lang, p: p, j: dropJ ? null : (j ?? this.j));

  @override
  String toString() => 'MixWord($w, $s–$e, $lang)';
}

// --------------------------------------------------------------------------
// Sounds
// --------------------------------------------------------------------------

/// Gujarati's block mirrors Devanagari's layout (both from ISCII): same offsets.
const gujaratiToDevanagari = 0x0A80 - 0x0900;

/// Devanagari letters → rough sound classes (aspirated = plain, retroflex = dental).
const _consonants = {
  'क': 'k', 'ख': 'k', 'ग': 'g', 'घ': 'g', 'ङ': 'n', 'च': 'c', 'छ': 'c', 'ज': 'j', 'झ': 'j', 'ञ': 'n', //
  'ट': 't', 'ठ': 't', 'ड': 'd', 'ढ': 'd', 'ण': 'n', 'त': 't', 'थ': 't', 'द': 'd', 'ध': 'd', 'न': 'n', //
  'प': 'p', 'फ': 'p', 'ब': 'b', 'भ': 'b', 'म': 'm', 'य': 'y', 'र': 'r', 'ल': 'l', 'ळ': 'l', 'व': 'v', //
  'श': 's', 'ष': 's', 'स': 's', 'ह': 'h',
};

/// Independent vowels and vowel signs.
const _vowels = {
  'अ': 'a', 'आ': 'a', 'इ': 'i', 'ई': 'i', 'उ': 'u', 'ऊ': 'u', 'ऋ': 'r', 'ए': 'e', 'ऐ': 'e', 'ओ': 'o', 'औ': 'o', //
  'ऍ': 'e', 'ऑ': 'o', 'ा': 'a', 'ि': 'i', 'ी': 'i', 'ु': 'u', 'ू': 'u', 'ृ': 'r', 'े': 'e', 'ै': 'e', //
  'ो': 'o', 'ौ': 'o', 'ॅ': 'e', 'ॉ': 'o',
};
const _nasals = {'ं', 'ँ'};

/// Rough sounds of a Hindi/Gujarati word: consonant classes and spoken vowels
/// (the unwritten "a" after a consonant is left out, as speech often drops it).
String indicSounds(String word) {
  final out = StringBuffer();
  for (var cp in word.runes) {
    if (cp >= 0x0A80 && cp <= 0x0AFF) cp -= gujaratiToDevanagari;
    final ch = String.fromCharCode(cp);
    final c = _consonants[ch];
    if (c != null) {
      out.write(c);
    } else if (_vowels[ch] case final v?) {
      out.write(v);
    } else if (_nasals.contains(ch)) {
      out.write('n');
    } else if (ch == 'ः') {
      out.write('h');
    }
  }
  return out.toString();
}

/// English spelling → the same sound classes, most specific rules first.
/// Capitals are finished sounds later rules must not touch ("C": the ch sound).
final _enRules = [
  (r'tion|sion', 'san'), (r'ture', 'Car'), (r'ctu', 'kCu'), (r'd?ge$', 'J'), (r'ough', 'o'), (r'augh', 'a'), //
  (r'igh', 'i'), (r'gh', ''), (r'^kn', 'n'), (r'^wr', 'r'), (r'mb$', 'm'), (r'ck', 'k'), (r'ph', 'p'), //
  (r'tch|sh|ch', 'C'), (r'th', 't'), (r'wh', 'v'), (r'qu', 'kv'), (r'x', 'ks'), (r'c(?=[eiy])', 's'), (r'c', 'k'), //
  (r'q', 'k'), (r'z', 'j'), (r'ee|ea|ie', 'i'), (r'oo|ou|ow', 'u'), (r'ai|ay|ey', 'e'), (r'au|aw', 'o'), //
  (r'w', 'v'), (r'f', 'p'), (r'^y', 'Y'), (r'y', 'i'),
].map((r) => (RegExp(r.$1), r.$2)).toList();

final _notLower = RegExp('[^a-z]');
final _doubled = RegExp(r'(.)\1+');

String englishSounds(String word) {
  var w = word.toLowerCase().replaceAll(_notLower, '');
  if (w == 'i') return 'ai';
  // A silent final e ("stage", "home").
  if (w.length > 3 && w.endsWith('e') && !'aeiouy'.contains(w[w.length - 2])) {
    if (!w.endsWith('ge')) w = w.substring(0, w.length - 1);
  }
  for (final (pattern, sound) in _enRules) {
    w = w.replaceAll(pattern, sound);
  }
  // Doubled letters sound once ("Y": a leading y stays y). "sh"/"ch" both
  // became "c"; Gujarati writes "sh" with શ (s), so either matches below.
  return w.toLowerCase().replaceAllMapped(_doubled, (m) => m[1]!);
}

const _vowelSet = {'a', 'e', 'i', 'o', 'u'};

/// Sounds spelled differently across the two but often the same sound.
const _close = [
  {'t', 'd'}, {'k', 'g'}, {'p', 'b'}, {'s', 'c'}, {'c', 'j'}, {'s', 'j'}, {'v', 'b'}, {'n', 'm'}, {'r', 'l'}, //
];

bool _isClose(String a, String b) => _close.any((c) => c.contains(a) && c.contains(b));

double _cost(String a, String b) {
  if (a == b) return 0.0;
  if (_vowelSet.contains(a) && _vowelSet.contains(b)) return 0.3;
  if (_vowelSet.contains(a) || _vowelSet.contains(b)) return 1.0;
  return _isClose(a, b) ? 0.5 : 1.0;
}

double _weight(String ch) => _vowelSet.contains(ch) ? 0.4 : 1.0;

double _sum(String s) => s.split('').fold(0.0, (t, ch) => t + _weight(ch));

/// 0..1: how alike two sound strings are (vowels count less than consonants).
double soundSimilarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0.0;
  var prev = <double>[0.0];
  for (final ch in b.split('')) {
    prev.add(prev.last + _weight(ch));
  }
  for (final ca in a.split('')) {
    final cur = <double>[prev[0] + _weight(ca)];
    for (var j = 1; j <= b.length; j++) {
      final cb = b[j - 1];
      final options = [prev[j] + _weight(ca), cur[j - 1] + _weight(cb), prev[j - 1] + _cost(ca, cb)];
      cur.add(options.reduce((x, y) => x < y ? x : y));
    }
    prev = cur;
  }
  final total = _sum(a) > _sum(b) ? _sum(a) : _sum(b);
  final s = 1.0 - prev.last / total;
  return s > 0 ? s : 0.0;
}

/// Alignment score of two sounds: positive when alike.
double _score(String a, String b) {
  if (a == b) return _vowelSet.contains(a) ? 0.5 : 1.0;
  if (_vowelSet.contains(a) && _vowelSet.contains(b)) return 0.1;
  if (_vowelSet.contains(a) || _vowelSet.contains(b)) return -1.0;
  return _isClose(a, b) ? 0.4 : -1.0;
}

/// The best-matching stretches of two sound strings (Smith-Waterman):
/// (score, aStart, aEnd, bStart, bEnd), ends exclusive. Finds an English
/// sentence spelled in Gujarati letters inside a longer Gujarati line, and the
/// part of the English reader's sentence that was really said in English.
(double, int, int, int, int) localMatch(String a, String b) {
  var best = (0.0, 0, 0, 0, 0);
  var prev = List<double>.filled(b.length + 1, 0.0);
  var prevFrom = List<(int, int)>.filled(b.length + 1, (0, 0)); // where each cell's stretch started
  for (var i = 1; i <= a.length; i++) {
    final cur = <double>[0.0];
    final curFrom = <(int, int)>[(i, 0)];
    for (var j = 1; j <= b.length; j++) {
      final gapA = _vowelSet.contains(a[i - 1]) ? 0.3 : 0.7;
      final gapB = _vowelSet.contains(b[j - 1]) ? 0.3 : 0.7;
      final options = [
        (0.0, (i, j)),
        (prev[j - 1] + _score(a[i - 1], b[j - 1]), prevFrom[j - 1]),
        (prev[j] - gapA, prevFrom[j]),
        (cur[j - 1] - gapB, curFrom[j - 1]),
      ];
      // Python's max(): the first of equal scores wins.
      var pick = options[0];
      for (final o in options.skip(1)) {
        if (o.$1 > pick.$1) pick = o;
      }
      var (score, start) = pick;
      if (score == 0.0) start = (i, j);
      cur.add(score);
      curFrom.add(start);
      if (score > best.$1) best = (score, start.$1, i, start.$2, j);
    }
    prev = cur;
    prevFrom = curFrom;
  }
  return best;
}

// --------------------------------------------------------------------------
// Which words are English
// --------------------------------------------------------------------------

/// Real English words that are also how the English reader writes common
/// Hindi/Gujarati words in Latin letters, or how it translates them
/// ("મમ્મી" → "mom"). Inside an English phrase they're fine ("I want to go").
const _notEnglishAlone = {
  'na', 'se', 'jo', 'to', 'so', 'ha', 'ho', 'mana', 'kari', 'karen', 'mummy', 'mommy', 'mom', 'papa', 'mama', //
  'dada', 'nana', 'bhai', 'hai', 'ka', 'ki', 'ke', 're', 'are', 'bas', 'ali', 'kya', 'at', 'is', 'a', 'an', 'the', //
  // Gujarati words that sound like their English translation (અને/and, ફૂલ/full)
  // or like an unrelated English word (ગોરી "fair" / gory).
  'and', 'full', 'gory', 'gori',
};

/// Indian names said as Gujarati words in Gujarati ("તમે ગુજરાતી છો"): only
/// written in English inside an English phrase ("do a Gujarati film").
const _nativeNames = {
  'gujarati', 'gujarat', 'hindi', 'india', 'indian', 'bombay', 'mumbai', 'ahmedabad', 'surat', 'baroda', 'vadodara', //
  'rajkot', 'delhi', 'krishna', 'ram', 'rama', 'shiva', 'ganesh', 'diwali', 'holi', 'navratri', 'jai', 'shri',
};
const _suffixes = ["'s", 's', 'es', 'ed', 'd', 'ing', 'ly', 'er', 'ers', 'est', 'ies', 'ied', 'ness', 'ment', 'ally'];

final _notWordChars = RegExp(r"[^a-z']");

String _key(String word) {
  var w = word.toLowerCase().replaceAll(_notWordChars, '');
  while (w.startsWith("'")) {
    w = w.substring(1);
  }
  while (w.endsWith("'")) {
    w = w.substring(0, w.length - 1);
  }
  return w;
}

/// The bundled English word list, every entry lowercased (names count: the
/// question here is "is it English?", not "is it an ordinary word?").
class EnglishWords {
  EnglishWords(this._words);

  factory EnglishWords.parse(String text) => EnglishWords({
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty && !line.startsWith('#')) line.trim().toLowerCase(),
      });

  final Set<String> _words;

  /// A real English word (the dictionary, with common endings).
  bool isEnglish(String word) {
    final w = _key(word);
    if (w.isEmpty) return false;
    if (_words.contains(w)) return true;
    for (final suf in _suffixes) {
      if (w.endsWith(suf) && w.length - suf.length >= 3) {
        final stem = w.substring(0, w.length - suf.length);
        if (_words.contains(stem) || _words.contains('${stem}e') || ((suf == 'ies' || suf == 'ied') && _words.contains('${stem}y'))) {
          return true;
        }
        // "stopped"
        if (stem.length > 3 && stem[stem.length - 1] == stem[stem.length - 2] && _words.contains(stem.substring(0, stem.length - 1))) {
          return true;
        }
      }
    }
    return false;
  }
}

/// The bundled list (the same file as the desktop's).
final englishWordsTextProvider =
    FutureProvider<String>((ref) => rootBundle.loadString('packages/mobile_backend/assets/english-words.txt'));

final englishWordsProvider =
    FutureProvider<EnglishWords>((ref) async => EnglishWords.parse(await ref.watch(englishWordsTextProvider.future)));

// --------------------------------------------------------------------------
// Combining
// --------------------------------------------------------------------------

/// A Gujarati word and English words this alike are the same speech.
const sameSound = 0.72;

/// Short words (up to two consonants) match by chance more easily.
const sameSoundShort = 0.85;

/// An English phrase must need each of its words: without one it must score this much less.
const everyWord = 0.03;

/// Between two replaced English words, up to this many Gujarati words become
/// the English heard between them ("can બી ધૂ યુ like" → "can be the... Would you like").
const betweenMax = 3;

/// The English reader's confidence in English it alone heard.
const runMinWord = 0.6;
const runMinMean = 0.85;

/// Shorter confident runs were the English reader's translation of Gujarati.
const runMinWords = 4;

/// Time slack between the two readers' word times (ms).
const slack = 600;

/// The Indian model's words are short and packed; a pause between them
/// shorter than this is still its speech, not something it left out (ms).
const gap = 800;

/// Sentences: at least this many English words, a pause this long ends one,
/// Gujarati words this far outside its time are still considered (ms), and
/// this sound similarity makes the Gujarati the same sentence.
const sentenceMinWords = 3;
const sentencePause = 800;
const sentenceSlack = 1000;
const sentenceSame = 0.62;

/// Longest phrases matched at once. Longer ones let common short words match
/// by chance ("છે" → "She").
const maxIndicWords = 2;
const maxEnglishWords = 3;

/// The commonest Gujarati and Hindi words: never English on their own (they
/// sound like short English words: છે/"she", એટલે/"at least"). Inside an
/// English phrase they can still become the English reader's words.
const commonIndic = {
  'છે', 'છો', 'છું', 'છીએ', 'હતું', 'હતો', 'હતી', 'તો', 'એટલે', 'એકદમ', 'અને', 'પણ', 'કે', 'ને', 'ના', 'નો', 'ની', 'નું', //
  'મને', 'હું', 'તમે', 'તું', 'એ', 'આ', 'જ', 'હા', 'શું', 'કેમ', 'ક્યાં', 'પછી', 'બી', 'કંઈ', 'નથી', 'નહીં', 'નહિ', 'થી', 'માં', //
  'મારા', 'મારી', 'મારો', 'મારું', 'એનું', 'એની', 'એના', 'એનો', 'તમારા', 'તમારી', 'આપણે', 'એમ', 'એમને', 'એને', 'તોય', //
  'है', 'हैं', 'था', 'थी', 'तो', 'और', 'कि', 'के', 'का', 'की', 'में', 'से', 'हाँ', 'हां', 'नहीं', 'भी', 'यह', 'वह', 'मैं', //
  'तुम', 'आप', 'क्या', 'को', 'पर', 'ही', 'हम',
};

/// Short English words that are mostly what a common Gujarati word sounds like.
const _notEnglishAloneExtra = {'she', 'so', 'my', 'them', 'he', 'me', 'we', 'us', 'it', 'i', "i'd"};

/// Gujarati/Hindi endings that attach to English words ("સિટીથી" = "from the city").
const _endings = ['માંથી', 'થી', 'માં', 'નો', 'ની', 'નું', 'ને', 'ના', 'નાં', 'વાળા', 'મેં', 'से', 'में', 'का', 'की', 'के', 'को'];

/// (how many Gujarati words, ending left on the last one) to try at [i].
/// Several words can be one English word or phrase ("લવ સ્ટોરી").
List<(int, String)> _forms(List<MixWord> words, int i) {
  final forms = <(int, String)>[];
  for (var n = maxIndicWords; n >= 1; n--) {
    if (i + n > words.length || words.sublist(i, i + n).any((w) => w.lang == 'en' || commonIndic.contains(w.w))) continue;
    final last = words[i + n - 1].w;
    forms.add((n, ''));
    forms.addAll([for (final end in _endings) if (last.endsWith(end) && last.length - end.length >= 2) (n, end)]);
  }
  return forms;
}

final _edges = RegExp(r"^[^\p{L}\p{M}\p{N}_']+|[^\p{L}\p{M}\p{N}_']+$", unicode: true);

String _clean(String word) => word.replaceAll(_edges, '');

int _consonantCount(String sounds) => sounds.split('').where((ch) => !_vowelSet.contains(ch)).length;

String _englishSoundsOf(Iterable<MixWord> words) => words.map((e) => englishSounds(e.w)).join();

String _indicSoundsOf(Iterable<MixWord> words) => words.map((w) => indicSounds(w.w)).join();

double _phraseScore(String sounds, List<MixWord> words) => soundSimilarity(sounds, _englishSoundsOf(words));

double _mean(Iterable<double> xs) => xs.fold(0.0, (t, x) => t + x) / xs.length;

/// Best (score, nIndic, first, last English index, ending) for the Gujarati
/// word(s) at [i], or null.
(double, int, int, int, String)? _bestMatch(List<MixWord> out, int i, List<MixWord> english, Set<int> used, EnglishWords dict) {
  (double, int, int, int, String)? best;
  for (final (n, ending) in _forms(out, i)) {
    final span = out.sublist(i, i + n);
    final texts = [for (final w in span) w.w];
    texts[texts.length - 1] = texts.last.substring(0, texts.last.length - ending.length);
    final parts = [for (final t in texts) indicSounds(t)];
    final sounds = parts.join();
    if (sounds.isEmpty) continue;
    final need = _consonantCount(sounds) <= 2 ? sameSoundShort : sameSound;
    final s0 = span.first.s - slack, s1 = span.last.e + slack;
    final near = [
      for (var j = 0; j < english.length; j++)
        if (!used.contains(j) && english[j].e >= s0 && english[j].s <= s1) j,
    ];
    for (var a = 0; a < near.length; a++) {
      for (var b = a; b < (a + maxEnglishWords < near.length ? a + maxEnglishWords : near.length); b++) {
        final js = near.sublist(a, b + 1);
        if (js.last - js.first != js.length - 1) continue; // not in a row
        final words = [for (final j in js) english[j]];
        final keys = [for (final e in words) _key(e.w)];
        if (!keys.every(dict.isEnglish)) continue;
        final ps = [for (final e in words) e.p];
        if (ps.reduce((x, y) => x < y ? x : y) < 0.3 || _mean(ps) < 0.5) continue;
        // Alone, Indian names and words that sound like their own translation
        // stay Gujarati; an Indian name only switches inside an English phrase.
        if (keys.every((k) => _nativeNames.contains(k) || _notEnglishAlone.contains(k) || _notEnglishAloneExtra.contains(k))) {
          continue;
        }
        if (keys.length < 3 && keys.any(_nativeNames.contains)) continue;
        final enSounds = _englishSoundsOf(words);
        final ratio = enSounds.length / (sounds.isEmpty ? 1 : sounds.length);
        if (ratio < 0.6 || ratio > 1.6) continue;
        final score = soundSimilarity(sounds, enSounds);
        if (score < need || (best != null && score <= best.$1)) continue;
        // Each English word must be needed ("ગુજરાતી" is "Gujarat?", not "Gujarat? Yeah,").
        if (words.length > 1 &&
            [_phraseScore(sounds, words.sublist(1)), _phraseScore(sounds, words.sublist(0, words.length - 1))]
                    .reduce((x, y) => x > y ? x : y) >=
                score - everyWord) {
          continue;
        }
        // …and each Gujarati word (a Gujarati word next to the English stays).
        if (n > 1 &&
            ending.isEmpty &&
            [soundSimilarity(parts.sublist(1).join(), enSounds), soundSimilarity(parts.sublist(0, parts.length - 1).join(), enSounds)]
                    .reduce((x, y) => x > y ? x : y) >=
                score - everyWord) {
          continue;
        }
        best = (score, n, js.first, js.last, ending);
      }
    }
  }
  return best;
}

bool _isUpper(String w) => w == w.toUpperCase() && w != w.toLowerCase();

/// An English reader's word placed in the line.
MixWord _word(MixWord e, int j, {int? s, int? end}) {
  var w = _clean(e.w);
  if (w.isEmpty) w = e.w;
  if (w.length > 3 && _isUpper(w)) w = w.toLowerCase(); // it sometimes SHOUTS
  return MixWord(w, s ?? e.s, end ?? e.e, lang: 'en', p: e.p, j: j);
}

int _clamp(int x, int lo, int hi) => x < lo ? lo : (x > hi ? hi : x);

/// Puts the matched English in place of the Gujarati word(s); returns how many words it is.
int _replace(List<MixWord> out, int i, List<MixWord> english, Set<int> used, (double, int, int, int, String) match) {
  final (_, n, j, k, ending) = match;
  final lo = out[i].s, hi = out[i + n - 1].e;
  final repl = <MixWord>[];
  for (var x = j; x <= k; x++) {
    final e = english[x];
    // Times kept inside the Gujarati words' span, so the order stays right.
    final s = _clamp(e.s, lo, hi);
    final end = _clamp(e.e, lo, hi);
    repl.add(_word(e, x, s: s, end: end > s ? end : s));
  }
  repl[repl.length - 1] = repl.last.copyWith(w: repl.last.w + ending); // "Cityથી": the ending stays on
  out.replaceRange(i, i + n, repl);
  used.addAll([for (var x = j; x <= k; x++) x]);
  return repl.length;
}

/// A few Gujarati words left between two replaced English words become the
/// English heard between those two: inside an English phrase, the Indian
/// model's leftovers are English it spelled by sound.
void _fillBetween(List<MixWord> out, List<MixWord> english, Set<int> used, EnglishWords dict) {
  var i = 0;
  while (i < out.length) {
    if (out[i].lang != 'en') {
      i++;
      continue;
    }
    var k = i + 1;
    while (k < out.length && out[k].lang != 'en') {
      k++;
    }
    final between = k - i - 1;
    if (k >= out.length || between < 1 || between > betweenMax) {
      i = k;
      continue;
    }
    final jl = out[i].j!, jr = out[k].j!;
    final gapJs = [for (var j = jl + 1; j < jr; j++) j];
    final words = [for (final j in gapJs) english[j]];
    final inBetween = out.sublist(i + 1, k);
    // Everyday Gujarati words there (એટલે મારા) and the English reader's
    // translation of them ("So my") don't sound alike; English spelled by sound (ટુ ડુ અ) does.
    if (inBetween.any((w) => commonIndic.contains(w.w)) &&
        soundSimilarity(_indicSoundsOf(inBetween), _englishSoundsOf(words)) < sameSound) {
      i = k;
      continue;
    }
    if (gapJs.isNotEmpty &&
        !gapJs.any(used.contains) &&
        words.every((e) => dict.isEnglish(_key(e.w)) && e.p >= 0.5)) {
      final lo = out[i].e, hi = out[k].s;
      out.replaceRange(i + 1, k, [
        for (final j in gapJs) _word(english[j], j, s: _clamp(english[j].s, lo, hi), end: _clamp(english[j].e, lo, hi)),
      ]);
      used.addAll(gapJs);
      k = i + 1 + gapJs.length;
    }
    i = k;
  }
}

/// The English reader's words grouped into sentences (indices): at . ? ! … or a pause.
List<List<int>> sentences(List<MixWord> english) {
  final out = <List<int>>[[]];
  for (var j = 0; j < english.length; j++) {
    out.last.add(j);
    final pause = j + 1 < english.length && english[j + 1].s - english[j].e > sentencePause;
    final w = english[j].w.replaceAll(RegExp(r"""["']+$"""), '');
    if (w.endsWith('.') || w.endsWith('?') || w.endsWith('!') || w.endsWith('…') || pause) out.add([]);
  }
  return [for (final s in out) if (s.isNotEmpty) s];
}

/// Sounds of the words joined, and which word each sound belongs to.
(String, List<int>) _soundsOf(List<MixWord> words, String Function(String) sounder) {
  final text = StringBuffer();
  final owner = <int>[];
  for (var k = 0; k < words.length; k++) {
    final s = sounder(words[k].w);
    text.write(s);
    owner.addAll(List.filled(s.length, k));
  }
  return (text.toString(), owner);
}

/// English sentences spelled in Gujarati letters → the English reader's sentence.
///
/// Word by word, short words (ટુ, ડુ, અ) don't match on their own. A whole
/// sentence does: its sounds follow the English closely, while a Gujarati
/// sentence and its translation don't. Only the part of the English sentence
/// that matches is taken (it may also hold a translation).
void _matchSentences(List<MixWord> out, List<MixWord> english, Set<int> used, EnglishWords dict) {
  for (final sent in sentences(english)) {
    final js = [for (final j in sent) if (!used.contains(j)) j];
    if (js.length < sentenceMinWords) continue;
    final s0 = english[js.first].s - sentenceSlack, s1 = english[js.last].e + sentenceSlack;
    final idx = [
      for (var i = 0; i < out.length; i++)
        if (out[i].lang != 'en' && out[i].e >= s0 && out[i].s <= s1) i,
    ];
    if (idx.isEmpty) continue;
    final (a, aOwner) = _soundsOf([for (final i in idx) out[i]], indicSounds);
    final (b, bOwner) = _soundsOf([for (final j in js) english[j]], englishSounds);
    if (a.isEmpty || b.isEmpty) continue;
    final (_, a0, a1, b0, b1) = localMatch(a, b);
    if (a1 <= a0 || b1 <= b0) continue;
    final first = idx[aOwner[a0]], last = idx[aOwner[a1 - 1]];
    final spanEn = js.sublist(bOwner[b0], bOwner[b1 - 1] + 1);
    final words = [for (final j in spanEn) english[j]];
    final span = out.sublist(first, last + 1);
    if (words.length < sentenceMinWords || span.any((w) => w.lang == 'en')) continue;
    final keys = [for (final e in words) _key(e.w)];
    final englishShare = keys.where(dict.isEnglish).length / keys.length;
    final meanP = _mean([for (final e in words) e.p]);
    final score = soundSimilarity(_indicSoundsOf(span), _englishSoundsOf(words));
    // A Gujarati sentence full of loanwords sounds like its translation; its
    // everyday Gujarati words (છે, તો, મારા) give it away.
    final glue = span.where((w) => commonIndic.contains(w.w)).length;
    if (score >= sentenceSame && englishShare >= 0.8 && meanP >= 0.5 && glue <= 1) {
      out.replaceRange(first, last + 1, [
        for (var x = 0; x < spanEn.length; x++) _word(words[x], spanEn[x]).copyWith(w: words[x].w),
      ]);
      used.addAll(spanEn);
    }
  }
}

/// Combines the Indian model's words with the English reader's words (same
/// time origin). Returns the words in order, each `en` or `indic`.
List<MixWord> merge(List<MixWord> indic, List<MixWord> english, EnglishWords dict) {
  final out = [for (final w in indic) MixWord(w.w, w.s, w.e, lang: 'indic')];
  final used = <int>{};

  // 0. Whole English sentences spelled in Gujarati letters.
  _matchSentences(out, english, used, dict);

  // 1. Gujarati words spelled by sound → the English heard at that moment.
  var i = 0;
  while (i < out.length) {
    final match = _bestMatch(out, i, english, used, dict);
    i += match == null ? 1 : _replace(out, i, english, used, match);
  }

  // 2. Gujarati leftovers inside an English phrase.
  _fillBetween(out, english, used, dict);

  // 3. English the Indian model dropped: confident runs where it wrote nothing.
  final covered = <List<int>>[];
  for (final w in [...out]..sort((x, y) => x.s.compareTo(y.s))) {
    if (covered.isNotEmpty && w.s - covered.last[1] < gap) {
      if (w.e > covered.last[1]) covered.last[1] = w.e;
    } else {
      covered.add([w.s, w.e]);
    }
  }
  bool free(MixWord e) {
    final mid = (e.s + e.e) / 2;
    return !covered.any((c) => c[0] - 150 <= mid && mid <= c[1] + 150);
  }

  final runs = <List<int>>[[]];
  for (var j = 0; j < english.length; j++) {
    final e = english[j];
    if (!used.contains(j) && free(e) && dict.isEnglish(_key(e.w)) && e.p >= runMinWord) {
      runs.last.add(j);
    } else if (runs.last.isNotEmpty) {
      runs.add([]);
    }
  }
  for (final r in runs) {
    if (r.length >= runMinWords && _mean([for (final j in r) english[j].p]) >= runMinMean) {
      var at = out.indexWhere((w) => w.s > english[r.first].s);
      if (at < 0) at = out.length;
      // Whole sentences keep the English reader's punctuation.
      out.insertAll(at, [for (final j in r) _word(english[j], j).copyWith(w: english[j].w)]);
    }
  }
  return [for (final w in out) w.copyWith(dropJ: true)];
}

String joinWords(List<MixWord> words) => words.map((w) => w.w).join(' ').trim();
