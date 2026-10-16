import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/speech/vocabulary.dart';

/// A few ordinary words, as the bundled English list has them (lowercase stems;
/// capitalised entries are names).
final common = CommonWords.parse('''
# test list
by
fine
finish
nation
nice
prize
rule
voice
desk
say
Raul
''');

/// A phrase of [text]'s words, 500 ms each.
Phrase heard(String text) {
  final words = text.split(' ');
  return Phrase(
    startMs: 0,
    endMs: words.length * 500,
    text: text,
    words: [for (var i = 0; i < words.length; i++) Word(words[i], i * 500, i * 500 + 500)],
  );
}

String fixed(String text, {String vocabulary = 'Nishchay, Priya, Rahul, Voice Desk, Raj'}) =>
    Vocabulary.fromSettings(name: '', vocabulary: vocabulary, common: common).apply(heard(text)).text;

void main() {
  test('should fix: words that sound like an entry', () {
    expect(fixed('Nishher said yes'), 'Nishchay said yes');
    expect(fixed('ask Nishchey'), 'ask Nishchay');
    expect(fixed('nishchay is here'), 'Nishchay is here');
    expect(fixed('Pria will send it'), 'Priya will send it');
    expect(fixed('Raul agreed'), 'Rahul agreed'); // a name in the list, not an ordinary word
  });

  test('should fix: an entry heard as two words, or a two-word entry heard as one', () {
    expect(fixed('ask Nish chay now'), 'ask Nishchay now');
    expect(fixed('open voice desk'), 'open Voice Desk');
    expect(fixed('open voicedesk'), 'open Voice Desk');
  });

  test('keeps the punctuation the heard word had', () {
    expect(fixed('Thanks, Nishher.'), 'Thanks, Nishchay.');
    expect(fixed('Pria, can you'), 'Priya, can you');
  });

  test('must never change: ordinary words, or names that only start the same', () {
    for (final text in [
      'Nisha will join',
      'Nishant will join',
      'that is nice',
      'I am fine',
      'by Friday',
      'a prize for the team',
      'the rule is',
      'finish it',
      'the nation',
      'Priyanka said',
    ]) {
      expect(fixed(text), text, reason: text);
    }
  });

  test('short entries only fix an exact match', () {
    expect(fixed('ask raj'), 'ask Raj');
    expect(fixed('ask rad'), 'ask rad');
  });

  test('the corrected word spans the heard words in time', () {
    final out = Vocabulary.fromSettings(name: '', vocabulary: 'Nishchay', common: common).apply(heard('ask Nish chay now'));
    expect(out.words, const [Word('ask', 0, 500), Word('Nishchay', 500, 1500), Word('now', 1500, 2000)]);
  });

  test('your name counts as vocabulary, whole and each part', () {
    final v = Vocabulary.fromSettings(name: 'Nishchay Mashruwala', vocabulary: '', common: common);
    expect(v.apply(heard('Nishher will do it')).text, 'Nishchay will do it');
    expect(v.apply(heard('Mashruwalla said')).text, 'Mashruwala said');
  });

  test('nothing set: the phrase is unchanged', () {
    final p = heard('Nishher said yes');
    expect(Vocabulary.fromSettings(name: ' ', vocabulary: ' , ', common: common).apply(p), p);
  });

  test('inflected ordinary words are ordinary too', () {
    expect(fixed('prizes for all', vocabulary: 'Priya'), 'prizes for all');
    expect(fixed('finished it', vocabulary: 'Finnish'), 'finished it');
  });

  test('with the real word list: ordinary words stay, your name is fixed', () {
    final real = CommonWords.parse(File('assets/english-words.txt').readAsStringSync());
    final v = Vocabulary.fromSettings(name: 'Nishchay', vocabulary: 'Priya, Rahul, Voice Desk', common: real);
    for (final text in ['Nisha will join', 'a prize for the team', 'I am fine', 'by Friday', 'that is nice', 'the rule is', 'finished it']) {
      expect(v.apply(heard(text)).text, text, reason: text);
    }
    expect(v.apply(heard('Nishher said yes')).text, 'Nishchay said yes');
    expect(v.apply(heard('Pria will send it')).text, 'Priya will send it');
  });

  Phrase heardWith(List<(String, double?)> words) => Phrase(
        startMs: 0,
        endMs: words.length * 500,
        text: words.map((w) => w.$1).join(' '),
        words: [for (final (i, (w, c)) in words.indexed) Word(w, i * 500, i * 500 + 500, c)],
      );
  final vocab = Vocabulary.fromSettings(name: 'Nishchay', vocabulary: 'Priya', common: common);

  test('a confidently heard word is never changed into a sound-alike', () {
    expect(vocab.apply(heardWith([('Nishher', 0.95), ('said', 0.9)])).text, 'Nishher said');
  });

  test('an unsure one is', () {
    expect(vocab.apply(heardWith([('Nishher', 0.3), ('said', 0.9)])).text, 'Nishchay said');
    // Unknown confidence (an older reader): as before, it is fixed.
    expect(vocab.apply(heardWith([('Nishher', null)])).text, 'Nishchay');
  });

  test('an exact match applies at any confidence', () {
    expect(vocab.apply(heardWith([('nishchay', 0.99)])).text, 'Nishchay');
  });

  test('Gujarati-script words never match an entry', () {
    expect(vocab.apply(heardWith([('નિશ્ચય', null), ('પ્રિયા', null)])).text, 'નિશ્ચય પ્રિયા');
  });

  test('an other name is fixed like the name', () {
    final v = Vocabulary.fromSettings(name: 'Nishchay', aliases: 'Nishu, Nish Bhai', vocabulary: '', common: common);
    expect(v.apply(heardWith([('Nishoo', 0.3), ('said', 0.9)])).text, 'Nishu said');
    expect(v.apply(heardWith([('Nishoo', 0.95)])).text, 'Nishoo'); // heard clearly: left as heard
    expect(v.apply(heardWith([('nish', 0.9), ('bhai', 0.9)])).text, 'Nish Bhai');
  });
}
