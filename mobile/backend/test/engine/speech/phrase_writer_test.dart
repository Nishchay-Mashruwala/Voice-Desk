import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/speech/mixed.dart';
import 'package:mobile_backend/engine/speech/phrase_writer.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';

void main() {
  final dict = EnglishWords.parse(File('assets/english-words.txt').readAsStringSync());

  /// A reader's line from (word, start ms, end ms[, confidence]).
  Phrase line(List<(String, int, int, double?)> words) => Phrase(
        startMs: words.isEmpty ? 0 : words.first.$2,
        endMs: words.isEmpty ? 0 : words.last.$3,
        text: words.map((w) => w.$1).join(' '),
        words: [for (final (w, s, e, p) in words) Word(w, s, e, p)],
      );

  /// Words at even times (300 ms apart, 240 ms long).
  Phrase spread(String text, int start, {double? p}) =>
      line([for (final (k, w) in text.split(' ').indexed) (w, start + k * 300, start + k * 300 + 240, p)]);

  test("one reader empty gives the other's words", () {
    final en = spread('fine thanks', 0, p: 0.9);
    final gu = spread('હા બરાબર', 0);
    final empty = line([]);
    expect(writePhrase(english: en, indic: empty, dict: dict), en);
    expect(writePhrase(english: en, dict: dict), en);
    expect(writePhrase(english: empty, indic: gu, dict: dict), gu);
    expect(writePhrase(indic: gu, dict: dict), gu);
    expect(writePhrase(english: empty, indic: empty, dict: dict), isNull);
    expect(writePhrase(dict: dict), isNull);
  });

  test('a mostly English phrase is written as Parakeet wrote it', () {
    // The Indian model spelled the English by sound; the English reader wrote it with its punctuation.
    final en = line([('Would', 0, 200, 0.9), ('you', 300, 500, 0.95), ('like', 600, 800, 0.9), ('to', 900, 1000, 0.9), ('do', 1100, 1300, 0.9), ('a', 1400, 1450, 0.9), ('film?', 1500, 1900, 0.9)]);
    final gu = line([('વુડ', 0, 200, null), ('યુ', 300, 500, null), ('લાઈક', 600, 800, null), ('ટુ', 900, 1000, null), ('ડુ', 1100, 1300, null), ('અ', 1400, 1450, null), ('ફિલ્મ', 1500, 1900, null)]);
    expect(writePhrase(english: en, indic: gu, dict: dict), en);
  });

  test('an English word inside Gujarati keeps its confidence, the Gujarati words none', () {
    final gu = line([('હા', 4480, 4640, null), ('એનું', 4720, 4880, null), ('બેકગ્રાઉન્ડ', 4960, 5600, null), ('તો', 5680, 5760, null), ('સ્કોટિશ', 5840, 6300, null), ('છે', 6400, 6500, null)]);
    final en = line([('Yes,', 4900, 5100, 0.67), ('her', 5260, 5280, 0.32), ('background', 5280, 5600, 0.99), ('is', 5640, 5800, 0.98), ('Scottish.', 5800, 6300, 0.97)]);
    final p = writePhrase(english: en, indic: gu, dict: dict)!;
    expect(p.text, 'હા એનું background તો Scottish છે');
    // The English reader's own time, kept inside the Gujarati word's (as on the desktop).
    expect(p.words[2], const Word('background', 5280, 5600, 0.99));
    expect(p.words[0].conf, isNull);
    expect((p.startMs, p.endMs), (4480, 6500));
  });

  test('an Indic-silent stretch of confident dictionary English is taken directly', () {
    final gu = spread('તો આવી ગુજરાતી', 0);
    final heard = line([('that', 2000, 2300, 0.9), ('was', 2400, 2700, 0.9), ('really', 2800, 3200, 0.9), ('good.', 3300, 4500, 0.9)]);
    final en = line([('So', 0, 200, 0.4), ...[for (final w in heard.words) (w.text, w.startMs, w.endMs, w.conf)]]);
    expect(writePhrase(english: en, indic: gu, dict: dict)!.text, 'તો આવી ગુજરાતી that was really good.');
    // The same words, heard unsurely: a translation, most likely; not taken.
    final unsure = line([('So', 0, 200, 0.4), for (final w in heard.words) (w.text, w.startMs, w.endMs, 0.7)]);
    expect(writePhrase(english: unsure, indic: gu, dict: dict)!.text, 'તો આવી ગુજરાતી');
  });

  test('stretches without words', () {
    final ws = [const Word('તો', 1000, 1200), const Word('આવી', 1300, 1600), const Word('એક', 4500, 4700)];
    expect(uncovered(ws, 0, 8000, 2000), [(1600, 4500), (4700, 8000)]);
    expect(uncovered(const [], 2000, 5000, 2000), [(2000, 5000)]);
    expect(uncovered(ws, 500, 5000, 3000), isEmpty);
  });

  test('Hindi words in a Gujarati reading suggest trying Hindi', () {
    expect(worthTryingOther(spread('મુઝે ક્યા પતા થા', 0), Lang.gu), isTrue);
    expect(worthTryingOther(spread('હું ઘરે છું', 0), Lang.gu), isFalse);
    expect(worthTryingOther(spread('background', 0), Lang.gu), isFalse);
    // And the other way round, Gujarati words in a Hindi reading.
    expect(worthTryingOther(spread('मने खबर नथी', 0), Lang.hi), isTrue);
    expect(worthTryingOther(spread('मुझे पता है', 0), Lang.hi), isFalse);
  });

  test('the other language wins only on its own markers', () {
    // The Hindi model on Gujarati speech: Gujarati words in Devanagari.
    expect(pickIndic(spread('મને ખબર નથી', 0), spread('मने खबर नथी', 0), Lang.gu), Lang.gu);
    expect(pickIndic(spread('મુઝે ક્યા પતા થા', 0), spread('मुझे क्या पता था', 0), Lang.gu), Lang.hi);
    expect(pickIndic(spread('मने खबर नथी', 0), spread('મને ખબર નથી', 0), Lang.hi), Lang.gu);
  });

  test('everyday Gujarati words never count as Hindi', () {
    // રહે / રહી are written रहे / रही in Devanagari: Hindi words too.
    expect(worthTryingOther(spread('એ અહીં રહે', 0), Lang.gu), isFalse);
    expect(worthTryingOther(spread('તે ત્યાં રહી', 0), Lang.gu), isFalse);
  });
}
