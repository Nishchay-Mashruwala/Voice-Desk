import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/speakers/grouping.dart';
import 'package:mobile_backend/engine/speakers/voice_print.dart';

/// Voices as directions (unit vectors with a little noise): A and B far apart.
final _rng = Random(7);
Float32List voice(int axis, {double noise = 0.05, List<double>? mix}) {
  final v = Float32List(8);
  if (mix != null) {
    for (var i = 0; i < mix.length; i++) {
      v[i] = mix[i];
    }
  } else {
    v[axis] = 1;
  }
  for (var i = 0; i < v.length; i++) {
    v[i] += (_rng.nextDouble() - 0.5) * noise;
  }
  return normalised(v);
}

final a = 0, b = 1;

/// A line of [text] from [start] to [end] (words evenly), with one [print] for the whole line or [voices].
Phrase line(int start, int end, String text, {Float32List? print, List<VoicePiece>? voices}) {
  final ws = text.split(' ');
  final step = (end - start) ~/ ws.length;
  return Phrase(
    startMs: start,
    endMs: end,
    text: text,
    words: [for (final (i, w) in ws.indexed) Word(w, start + i * step, i == ws.length - 1 ? end : start + (i + 1) * step)],
    voices: voices ?? [if (print != null) VoicePiece(start, end, print)],
  );
}

List<(String, String?)> said(SpeakerResult r) => [for (final l in r.lines) (l.text, l.speaker)];

void main() {
  test('two voices make two groups, named Person 1 and 2 in order of first appearance', () {
    final r = groupSpeakers([
      line(0, 2000, 'hello there', print: voice(b)),
      line(2500, 4500, 'hi how are you', print: voice(a)),
      line(5000, 7000, 'fine thanks', print: voice(b)),
      line(7500, 9500, 'good to hear', print: voice(a)),
    ]);
    expect(said(r), [
      ('hello there', 'Person 1'),
      ('hi how are you', 'Person 2'),
      ('fine thanks', 'Person 1'),
      ('good to hear', 'Person 2'),
    ]);
    expect(r.groups.map((g) => (g.label, g.speechMs)), [('Person 1', 4000), ('Person 2', 4000)]);
    expect(r.lines[0].speakerGroup, r.lines[2].speakerGroup);
  });

  test('one voice is one group', () {
    final r = groupSpeakers([for (var i = 0; i < 4; i++) line(i * 3000, i * 3000 + 2000, 'line $i', print: voice(a))]);
    expect(r.groups, hasLength(1));
    expect(r.lines.every((l) => l.speaker == 'Person 1'), isTrue);
  });

  test('a phrase with two voices is split where the speaker changes', () {
    final long = Phrase(
      id: 9,
      startMs: 0,
      endMs: 4200,
      text: 'one two three four five six seven',
      words: line(0, 4200, 'one two three four five six seven').words,
      voices: [
      VoicePiece(0, 1500, voice(a)),
      VoicePiece(750, 2250, voice(a)),
      VoicePiece(1500, 3000, voice(b)),
      VoicePiece(2250, 3750, voice(b)),
      VoicePiece(2700, 4200, voice(b)),
      ],
    );
    final r = groupSpeakers([
      long,
      line(5000, 7000, 'a speaks again', print: voice(a)),
      line(7500, 9500, 'b speaks again', print: voice(b)),
    ]);
    // A's last window ends at 2.25 s and B's first starts at 1.5 s: the change is
    // put halfway (1.875 s), so "four" (1.8–2.4 s) is B's.
    expect(said(r), [
      ('one two three', 'Person 1'),
      ('four five six seven', 'Person 2'),
      ('a speaks again', 'Person 1'),
      ('b speaks again', 'Person 2'),
    ]);
    // The halves keep the line's time span between them, split at the words.
    expect((r.lines[0].startMs, r.lines[0].endMs, r.lines[1].startMs, r.lines[1].endMs), (0, 1800, 1800, 4200));
    expect(r.lines[0].words.map((w) => w.text), ['one', 'two', 'three']);
    expect((r.lines[0].id, r.lines[1].id), (9, null)); // the first part is the saved line
  });

  test('a single stray window stays with its neighbours', () {
    final r = groupSpeakers([
      line(0, 3600, 'one two three four five six', voices: [
        VoicePiece(0, 1500, voice(a)),
        VoicePiece(750, 2250, voice(a)),
        VoicePiece(1500, 3000, voice(b)),
        VoicePiece(2100, 3600, voice(a)),
      ]),
      line(4000, 6000, 'other voice', print: voice(b)),
    ]);
    expect(said(r).first, ('one two three four five six', 'Person 1'));
    expect(r.lines, hasLength(2));
  });

  test('a group with under 1.5 s of speech joins the nearest', () {
    final nearB = voice(0, mix: [0, 0.3, 0.95]); // closer to B than to A, but not B
    final r = groupSpeakers([
      line(0, 3000, 'voice a here', print: voice(a)),
      line(3500, 6500, 'voice b here', print: voice(b)),
      line(7000, 8000, 'short', print: nearB),
    ]);
    expect(r.groups, hasLength(2));
    expect(said(r).last, ('short', 'Person 2'));
  });

  test('the trained voice is Me, and a voice below the line is not', () {
    final lines = [
      line(0, 3000, 'my words', print: voice(a)),
      line(3500, 6500, 'their words', print: voice(b)),
    ];
    expect(said(groupSpeakers(lines, me: voice(a))), [('my words', 'Me'), ('their words', 'Person 1')]);
    final faint = voice(0, mix: [0.2, 0, 0, 0.98]); // similarity to A about 0.2
    expect(said(groupSpeakers(lines, me: faint)), [('my words', 'Person 1'), ('their words', 'Person 2')]);
  });

  test('a remembered person names their group; each person names one group; best pairs first', () {
    final r = groupSpeakers(
      [
        line(0, 3000, 'first voice', print: voice(a)),
        line(3500, 6500, 'second voice', print: voice(b)),
      ],
      people: [
        KnownVoice('Asha', voice(0, mix: [0, 0.5, 0, 0.87])), // like B, less so
        KnownVoice('Kiran', voice(b)),
      ],
    );
    expect(said(r), [('first voice', 'Person 1'), ('second voice', 'Kiran')]);
  });

  test('groups with under 3 s of speech are not matched to remembered people', () {
    final r = groupSpeakers(
      [
        line(0, 3000, 'first voice', print: voice(a)),
        line(3500, 5500, 'second voice', print: voice(b)),
      ],
      people: [KnownVoice('Kiran', voice(b))],
    );
    expect(said(r).last, ('second voice', 'Person 2'));
  });

  test('a short line without a print takes the speaker nearest in time', () {
    final r = groupSpeakers([
      line(0, 3000, 'voice a here', print: voice(a)),
      line(3200, 3500, 'yes'),
      line(6000, 9000, 'voice b here', print: voice(b)),
    ]);
    expect(said(r), [('voice a here', 'Person 1'), ('yes', 'Person 1'), ('voice b here', 'Person 2')]);
    expect(r.groups.first.speechMs, 3000); // the print's speech only
  });

  test('when every group has under 1.5 s of speech, none is folded away', () {
    final r = groupSpeakers([line(0, 1000, 'yes', print: voice(a)), line(2000, 3000, 'no', print: voice(b))]);
    expect(said(r), [('yes', 'Person 1'), ('no', 'Person 2')]);
  });

  test('a long line of one word goes to the group with most of its windows', () {
    final r = groupSpeakers([
      line(0, 4200, 'hmmmm', voices: [
        VoicePiece(0, 1500, voice(a)),
        VoicePiece(750, 2250, voice(a)),
        VoicePiece(1500, 3000, voice(b)),
        VoicePiece(2250, 3750, voice(b)),
        VoicePiece(2700, 4200, voice(b)),
      ]),
      line(5000, 8000, 'a speaks', print: voice(a)),
      line(9000, 12000, 'b speaks', print: voice(b)),
    ]);
    expect(r.lines, hasLength(3));
    expect(r.lines.first.speaker, r.lines.last.speaker);
  });

  test('three voices make three groups', () {
    const c = 2;
    final r = groupSpeakers([
      for (final (i, axis) in [a, b, c, a, b, c].indexed) line(i * 3500, i * 3500 + 3000, 'line $i', print: voice(axis)),
    ]);
    expect(r.groups, hasLength(3));
    expect([for (final l in r.lines) l.speaker],
        ['Person 1', 'Person 2', 'Person 3', 'Person 1', 'Person 2', 'Person 3']);
  });

  test('a remembered name like "Person 1" is not given to a second group too', () {
    final r = groupSpeakers(
      [line(0, 3000, 'first voice', print: voice(a)), line(3500, 6500, 'second voice', print: voice(b))],
      people: [KnownVoice('Person 1', voice(b))],
    );
    expect(said(r), [('first voice', 'Person 2'), ('second voice', 'Person 1')]);
  });

  test('lines without prints keep no speaker', () {
    final lines = [line(0, 2000, 'no prints here'), line(2500, 4000, 'none here either')];
    final r = groupSpeakers(lines);
    expect(r.groups, isEmpty);
    expect(r.lines.every((l) => l.speaker == null && l.speakerGroup == null), isTrue);
  });
}
