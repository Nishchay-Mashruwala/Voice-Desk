import '../../data/transcript.dart';
import 'mixed.dart';
import 'speech_setup.dart';

/// Where the Indian model wrote nothing this long while the English reader
/// heard a few words: English said on its own (desktop `SILENT_INDIC_S`, ms).
const silentIndicMs = 2000;

/// Such a stretch is taken as the English reader wrote it when this share of
/// its words are dictionary words, heard with this mean confidence. (The
/// desktop asked Whisper which language the stretch was; Parakeet can't say.)
const directEnglishShare = 0.8;
const directEnglishConf = 0.85;

/// A phrase this much English is written exactly as the English reader wrote it.
const mostlyEnglish = 0.7;

/// Stretches of at least [minMs] within [startMs, endMs) without any of [words].
List<(int, int)> uncovered(List<Word> words, int startMs, int endMs, int minMs) {
  final out = <(int, int)>[];
  var at = startMs;
  for (final w in [...words]..sort((a, b) => a.startMs.compareTo(b.startMs))) {
    if (w.startMs - at >= minMs) out.add((at, w.startMs));
    if (w.endMs > at) at = w.endMs;
  }
  if (endMs - at >= minMs) out.add((at, endMs));
  return out;
}

MixWord _mix(Word w, String lang) => MixWord(w.text, w.startMs, w.endMs, lang: lang, p: w.conf ?? 1.0);

/// One line from what the two readers heard of the same (padded) phrase: the
/// desktop's `_combine` + `mixed.merge`. Null when neither heard a word.
Phrase? writePhrase({Phrase? english, Phrase? indic, required EnglishWords dict}) {
  final en = english?.words ?? const <Word>[];
  final ind = indic?.words ?? const <Word>[];
  if (en.isEmpty && ind.isEmpty) return null;
  if (ind.isEmpty) return english;
  if (en.isEmpty) return indic;

  final start = english!.startMs < indic!.startMs ? english.startMs : indic.startMs;
  final end = english.endMs > indic.endMs ? english.endMs : indic.endMs;

  // English said where the Indian model wrote nothing: taken as heard.
  final direct = <Word>[];
  for (final (a, b) in uncovered(ind, start, end, silentIndicMs)) {
    final inside = [
      for (final e in en)
        if (a <= (e.startMs + e.endMs) / 2 && (e.startMs + e.endMs) / 2 < b) e,
    ];
    if (inside.length < 2) continue;
    final share = inside.where((e) => dict.isEnglish(e.text)).length / inside.length;
    final conf = inside.fold(0.0, (t, e) => t + (e.conf ?? 1.0)) / inside.length;
    if (share >= directEnglishShare && conf >= directEnglishConf) direct.addAll(inside);
  }
  final rest = [for (final e in en) if (!direct.contains(e)) _mix(e, 'en')];
  final indicWords = [for (final w in ind) _mix(w, 'indic')];
  final out = rest.isEmpty ? indicWords : merge(indicWords, rest, dict);
  for (final e in direct) {
    var at = out.indexWhere((w) => w.s > e.startMs);
    if (at < 0) at = out.length;
    out.insert(at, _mix(e, 'en'));
  }
  if (out.isNotEmpty && out.where((w) => w.lang == 'en').length >= mostlyEnglish * out.length) return english;
  final words = [for (final w in out) Word(w.w, w.s, w.e, w.lang == 'en' ? w.p : null)];
  return Phrase(startMs: start, endMs: end, text: joinWords(out), words: words);
}

/// Words only Hindi uses (Devanagari). Not रही / रहे: in Gujarati letters
/// they are રહી / રહે, everyday Gujarati.
const _hindiMarkers = {
  'है', 'हैं', 'था', 'थे', 'क्या', 'मुझे', 'मैं', 'हम', 'यह', 'वह', 'और', 'लेकिन', 'बहुत', 'अच्छा', 'रहा', //
  'मेरा', 'मेरी', 'मेरे', 'तुम', 'लिए', 'कैसे', 'कहाँ', 'यहाँ', 'वहाँ', 'हूँ',
};

/// Words only Gujarati uses (in Gujarati script; compared in Devanagari).
const _gujaratiMarkerWords = {
  'છે', 'છો', 'છું', 'છીએ', 'હતો', 'હતી', 'હતું', 'શું', 'તમે', 'હું', 'આપણે', 'મને', 'નથી', 'એટલે', 'પણ', 'કેમ', //
  'મારું', 'તમારું',
};
final _gujaratiMarkers = {for (final w in _gujaratiMarkerWords) toDevanagari(w)};

/// Gujarati letters as the same Devanagari letters (the two blocks mirror each other).
String toDevanagari(String word) => String.fromCharCodes([
      for (final cp in word.runes) cp >= 0x0A80 && cp <= 0x0AFF ? cp - gujaratiToDevanagari : cp,
    ]);

final _edges = RegExp(r'^[^\p{L}\p{M}]+|[^\p{L}\p{M}]+$', unicode: true);

/// How many of the phrase's words are [markers] (in either script).
int _count(Phrase p, Set<String> markers) =>
    p.words.where((w) => markers.contains(toDevanagari(w.text.replaceAll(_edges, '')))).length;

Set<String> _markers(Lang l) => l == Lang.hi ? _hindiMarkers : _gujaratiMarkers;

Lang _other(Lang l) => l == Lang.hi ? Lang.gu : Lang.hi;

/// Whether the preferred model's reading has words of the other language in
/// it: then that model is tried on the phrase too.
bool worthTryingOther(Phrase preferredOutput, Lang preferred) {
  final other = _count(preferredOutput, _markers(_other(preferred)));
  return other >= 1 && other > _count(preferredOutput, _markers(preferred));
}

/// Which reading to keep: the other language only when its own reading has
/// more of its words than of the preferred language's; else the preferred.
Lang pickIndic(Phrase preferredOutput, Phrase otherOutput, Lang preferred) {
  final other = _other(preferred);
  return _count(otherOutput, _markers(other)) > _count(otherOutput, _markers(preferred)) ? other : preferred;
}
