import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/speech/mixed.dart';

/// The desktop's `test_mixed.py`, case for case (seconds → ms). Word times and
/// Whisper's words come from the owner's "Gujarati Test" meeting.
void main() {
  final dict = EnglishWords.parse(File('assets/english-words.txt').readAsStringSync());

  int ms(double s) => (s * 1000).round();

  /// IndicConformer's words: ("તમે", 0.0, 0.2), …
  List<MixWord> g(List<(String, double, double)> spec) =>
      [for (final (w, s, e) in spec) MixWord(w, ms(s), ms(e), lang: 'indic')];

  /// The English reader's words: (word, confidence, start, end).
  List<MixWord> en(List<(String, double, double, double)> spec) =>
      [for (final (w, p, s, e) in spec) MixWord(w, ms(s), ms(e), lang: 'en', p: p)];

  /// Gujarati words at even times.
  List<MixWord> spread(String text, double start) => [
        for (final (k, w) in text.split(' ').indexed) MixWord(w, ms(start) + k * 300, ms(start) + k * 300 + 240, lang: 'indic'),
      ];

  /// English words at even times, all with confidence [p].
  List<MixWord> heard(String text, double start, {double p = 0.9}) => [
        for (final (k, w) in text.split(' ').indexed) MixWord(w, ms(start) + k * 300, ms(start) + k * 300 + 240, lang: 'en', p: p),
      ];

  double alike(String gu, String english) => soundSimilarity(
        gu.split(' ').map(indicSounds).join(),
        english.split(' ').map(englishSounds).join(),
      );

  String mix(List<MixWord> indic, List<MixWord> english) => joinWords(merge(indic, english, dict));

  test('English spelled in Gujarati sounds like the English', () {
    for (final (gu, english) in [
      ('બેકગ્રાઉન્ડ', 'background'),
      ('અફકોર્સ', 'of course'),
      ('એક્ચુલી', 'actually'),
      ('સ્કોટિશ', 'Scottish'),
      ('ફ્રેકલ્સ', 'freckles'),
      ('સ્ટેજ', 'stage'),
      ('નોર્મલી', 'normally'),
    ]) {
      expect(alike(gu, english), greaterThanOrEqualTo(0.8), reason: '$gu / $english');
    }
  });

  test("Gujarati and its translation don't", () {
    for (final (gu, english) in [('ભૂખ', 'hungry'), ('પાણી', 'water'), ('કારણ', 'because'), ('ગુસ્સા', 'anger'), ('સરસ', 'nice')]) {
      expect(alike(gu, english), lessThan(0.5), reason: '$gu / $english');
    }
  });

  test('English words with endings', () {
    for (final w in ['actually', 'freckles', 'normally', 'stopped', 'Scottish', 'background']) {
      expect(dict.isEnglish(w), isTrue, reason: w);
    }
    // Gujarati written in Latin letters isn't English.
    for (final w in ['aavde', 'hoon', 'khaali', 'gusa', 'varso']) {
      expect(dict.isEnglish(w), isFalse, reason: w);
    }
  });

  test('an English word replaces its Gujarati spelling', () {
    final words = g([('હા', 4.48, 4.64), ('એનું', 4.72, 4.88), ('બેકગ્રાઉન્ડ', 4.96, 5.6), ('તો', 5.68, 5.76), ('સ્કોટિશ', 5.84, 6.3), ('છે', 6.4, 6.5)]);
    final english = en([('Yes,', 0.67, 4.9, 5.1), ('her', 0.32, 5.26, 5.28), ('background', 0.99, 5.28, 5.6), ('is', 0.98, 5.64, 5.8), ('Scottish.', 0.97, 5.8, 6.3)]);
    expect(mix(words, english), 'હા એનું background તો Scottish છે');
  });

  test('a translation and Latin-letter Gujarati are not used', () {
    final words = g([('ભૂખ', 0.0, 0.3), ('લાગી', 0.4, 0.7), ('છે', 0.8, 0.9), ('આવડે', 1.0, 1.3), ('છે', 1.4, 1.5)]);
    final english = en([('You', 0.05, 0.0, 0.1), ('feel', 0.42, 0.1, 0.3), ('hungry,', 0.98, 0.3, 0.8), ('aavde', 0.97, 1.0, 1.3), ('she', 0.9, 1.4, 1.5)]);
    expect(mix(words, english), 'ભૂખ લાગી છે આવડે છે');
  });

  test('Indian names stay Gujarati alone', () {
    // The English reader translated "તમે ગુજરાતી છો" as "Are you from Gujarat?"
    final words = g([('તમે', 0.0, 0.24), ('ગુજરાતી', 0.24, 0.64), ('છો', 0.64, 0.8)]);
    final english = en([('Are', 0.26, 0.0, 0.22), ('you', 0.99, 0.22, 0.3), ('from', 0.33, 0.3, 0.3), ('Gujarat?', 0.97, 0.3, 0.9), ('Yeah,', 0.44, 1.08, 1.3)]);
    expect(mix(words, english), 'તમે ગુજરાતી છો');
  });

  test('a Gujarati ending stays on the English word', () {
    final words = g([('તો', 7.2, 7.3), ('કેન્ઝી', 7.36, 7.8), ('સિટીથી', 7.92, 8.3), ('છે', 8.4, 8.5)]);
    final english = en([('from', 0.99, 7.42, 7.5), ('Kansas', 0.74, 7.5, 7.78), ('City.', 0.77, 7.78, 8.2)]);
    expect(mix(words, english), 'તો Kansas Cityથી છે');
  });

  test("Gujarati leftovers inside an English phrase become the English reader's words", () {
    final words = g([
      ('જેમાં', 1.5, 1.8), ('કેન', 2.3, 2.5), ('બી', 2.6, 2.7), ('ધૂ', 2.8, 3.0), ('યુ', 3.7, 3.8), ('લાઈક', 3.84, 4.0),
      ('ટુ', 4.0, 4.1), ('ડુ', 4.1, 4.18), ('અ', 4.18, 4.2), ('ફિલ્મ', 4.56, 4.9),
    ]);
    final english = en([
      ('can', 0.86, 2.38, 2.6), ('be', 0.97, 2.6, 2.78), ('the...', 0.71, 2.78, 3.5), ('Would', 0.77, 3.56, 3.74),
      ('you', 0.99, 3.74, 3.84), ('like', 0.99, 3.84, 4.0), ('to', 1.0, 4.0, 4.1), ('do', 0.98, 4.1, 4.18),
      ('a', 0.98, 4.18, 4.28), ('film?', 0.97, 4.56, 4.9),
    ]);
    // Taken as two sentences, with the English reader's punctuation.
    expect(mix(words, english), 'જેમાં can be the... Would you like to do a film?');
  });

  test('everyday Gujarati between English words stays', () {
    // "Gujarati. [એટલે મારા] dad": the English words between are a translation ("So my").
    final words = g([('હેવ', 2.96, 3.2), ('ગુજરાતી', 3.28, 3.68), ('એટલે', 4.0, 4.3), ('મારા', 4.32, 4.5), ('ડેડ', 4.56, 4.8)]);
    final english = en([('have', 0.68, 2.9, 3.2), ('Gujarati.', 0.83, 3.3, 3.7), ('So', 0.49, 3.9, 4.2), ('my', 0.71, 4.3, 4.5), ('dad', 0.67, 4.56, 4.8)]);
    expect(mix(words, english), contains('એટલે મારા'));
  });

  test('English the Gujarati model dropped is put back', () {
    final words = g([('તો', 0.0, 0.2), ('આવી', 0.3, 0.6), ('ગુજરાતી', 1.0, 1.5)]);
    final english = en([('Wow,', 0.93, 6.48, 6.8), ("that's", 0.99, 6.88, 7.1), ('amazing.', 0.99, 7.1, 7.5), ('Yeah,', 0.91, 7.56, 7.8), ('we', 1.0, 7.8, 7.94)]);
    expect(mix(words, english), "તો આવી ગુજરાતી Wow, that's amazing. Yeah, we");
  });

  test('a short confident translation in a small gap is not', () {
    // "ભરોસો નહીં" -> "don't believe in": confident, but a translation.
    final words = g([('તમારા', 0.0, 0.4), ('પર', 0.5, 0.6), ('ભરો', 0.7, 0.9), ('વાળા', 2.2, 2.5)]);
    final english = en([("don't", 0.97, 1.1, 1.3), ('believe', 0.98, 1.3, 1.6), ('in', 0.93, 1.6, 1.8)]);
    expect(mix(words, english), 'તમારા પર ભરો વાળા');
  });

  test('an English sentence spelled in Gujarati becomes the English sentence', () {
    // Word by word this came out "કેન બી ધ વુડ you like ટુ ડુ અ ગુજરાતી film".
    final words = [...spread('તો આવી એક લવ સ્ટોરી થઈ શકે કે જેમાં', 0.0), ...spread('વુડ યુ લાઈક ટુ ડુ અ ગુજરાતી ફિલ્મ', 3.0)];
    final english = heard('Would you like to do a Gujarati film?', 3.0, p: 0.86);
    expect(mix(words, english), 'તો આવી એક લવ સ્ટોરી થઈ શકે કે જેમાં Would you like to do a Gujarati film?');
  });

  test('the translation of a Gujarati sentence is not taken', () {
    // Confident translations sharing loanwords ("producer", "Gujarati").
    for (final (gu, english) in [
      ('આગળ ભાઈ કોને પ્રોડ્યુસર બનવું છે ગુજરાતી પિક્ચર માં', 'ever become a producer in a Gujarati film?'),
      ('અરે મને તો કરું હેફ વા ટુ છોડી દે ને ભાઈ', "I'm half white now, please leave me alone, brother."),
      ('કે મમ્મી મને ગુસ્સા', 'my mom made me angry, she says, I'),
      // Loanwords make these sound alike; છે, તો, મારા show it's Gujarati.
      ('એટલે મારા ડેડ તો ગુજરાતી છે બોમ્બે', 'So my dad is Gujarati, Bombay.'),
    ]) {
      final merged = merge(spread(gu, 0.0), heard(english, 0.0, p: 0.75), dict);
      expect(merged.where((w) => w.lang == 'en').length, lessThanOrEqualTo(1), reason: '$gu → ${joinWords(merged)}');
    }
  });

  test('all Gujarati when the English reader heard nothing', () {
    final words = g([('ભૂખ', 0.0, 0.3), ('લાગી', 0.4, 0.7)]);
    expect(merge(words, const [], dict).map((w) => w.lang), ['indic', 'indic']);
  });

  test('sentences end at . ? ! or a pause', () {
    final words = en([('Hi.', 0.9, 0.0, 0.2), ('How', 0.9, 0.3, 0.5), ('are', 0.9, 0.5, 0.7), ('you', 0.9, 0.7, 0.9), ('then', 0.9, 1.8, 2.0)]);
    expect(sentences(words), [[0], [1, 2, 3], [4]]);
  });
}
