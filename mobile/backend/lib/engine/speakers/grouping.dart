import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../data/transcript.dart';
import 'voice_print.dart';

/// Lines are one person's while their mean similarity is at least this
/// (measured: same voice ≥ 0.33, other voices ≤ 0.31).
const kSameGroup = 0.35;

/// The group most like the trained voice is "Me" from this similarity.
const kMeAt = 0.30;

/// A remembered person names a group from this similarity…
const kPersonAt = 0.35;

/// …when the group has this much speech (less is too little to compare).
const kMinNamedMs = 3000;

/// A group with less speech than this joins the nearest group.
const kMinGroupMs = 1500;

/// A speaker turn shorter than this joins its neighbour.
const kMinTurnMs = 250;

const kMeLabel = 'Me';
String personLabel(int n) => 'Person $n';

/// One person in a recording: their lines share [id].
@immutable
class SpeakerGroup {
  const SpeakerGroup({required this.id, required this.label, required this.print, required this.speechMs});
  final int id;
  final String label;
  final Float32List print;

  /// How much of their speech made [print].
  final int speechMs;

  @override
  String toString() => 'SpeakerGroup($id $label, ${speechMs}ms)';
}

/// A remembered person's voice.
@immutable
class KnownVoice {
  const KnownVoice(this.name, this.print);
  final String name;
  final Float32List print;
}

class SpeakerResult {
  const SpeakerResult(this.lines, this.groups);

  /// The lines, split where the speaker changes, each with its speaker.
  final List<Phrase> lines;

  /// In order of first appearance.
  final List<SpeakerGroup> groups;
}

/// The speakers step (tests replace it).
typedef SpeakerGrouper = Future<SpeakerResult> Function(List<Phrase> lines,
    {Float32List? me, List<KnownVoice> people});

/// [groupSpeakers] away from the screens' thread (an hour's lines take a
/// moment on a phone).
Future<SpeakerResult> groupInBackground(List<Phrase> lines, {Float32List? me, List<KnownVoice> people = const []}) =>
    Isolate.run(() => groupSpeakers(lines, me: me, people: people));

/// Who said each line: the lines' voice prints grouped by person, lines cut
/// where the speaker changes, and the groups named "Me" (like [me]), after a
/// remembered person in [people], or "Person 1, 2…".
SpeakerResult groupSpeakers(List<Phrase> lines, {Float32List? me, List<KnownVoice> people = const []}) {
  final printed = [for (final (i, l) in lines.indexed) if (l.voices.isNotEmpty) i];
  if (printed.isEmpty) return SpeakerResult([for (final l in lines) l.withSpeaker(null, null)], const []);

  // 1. Whole lines, grouped.
  final clusterOf = clusterPrints(
      [for (final i in printed) meanPrint([for (final v in lines[i].voices) (v.print, v.ms)])], kSameGroup);
  final clusters = clusterOf.fold(0, (n, c) => c >= n ? c + 1 : n);
  final centres = [
    for (var c = 0; c < clusters; c++)
      meanPrint([
        for (final (k, i) in printed.indexed)
          if (clusterOf[k] == c)
            for (final v in lines[i].voices) (v.print, v.ms)
      ]),
  ];

  // 2. Each window of a long line goes to the group nearest its voice; one
  // window between two of the same group's is theirs.
  final pieceGroups = <int, List<int>>{};
  for (final (k, i) in printed.indexed) {
    final voices = lines[i].voices;
    if (voices.length == 1) {
      pieceGroups[i] = [clusterOf[k]];
      continue;
    }
    final who = [for (final v in voices) _nearest(v.print, centres, List.generate(clusters, (c) => c))];
    pieceGroups[i] = _smooth(who);
  }

  // 3. The turns: each word goes to the window whose middle is nearest its own.
  final turns = <int, List<_Turn>>{for (final i in printed) i: _turnsOf(lines[i], pieceGroups[i]!)};

  // 4. Groups with too little speech join the group nearest their voice.
  final speech = List.filled(clusters, 0);
  for (final ts in turns.values) {
    for (final t in ts) {
      speech[t.group] += t.ms;
    }
  }
  final real = [for (var c = 0; c < clusters; c++) if (speech[c] >= kMinGroupMs) c];
  final into = List.generate(clusters, (c) => real.isEmpty || speech[c] >= kMinGroupMs || speech[c] == 0
      ? c
      : _nearest(centres[c], [for (final r in real) centres[r]], real));
  for (final i in printed) {
    turns[i] = _joined([for (final t in turns[i]!) t.by(into[t.group])]);
    pieceGroups[i] = [for (final g in pieceGroups[i]!) into[g]];
  }

  // 5. Ids in order of first appearance, and each group's voice from its windows.
  final first = <int, int>{};
  for (final i in printed) {
    for (final t in turns[i]!) {
      final at = first[t.group];
      if (at == null || t.startMs < at) first[t.group] = t.startMs;
    }
  }
  final order = first.keys.toList()..sort((x, y) => first[x]!.compareTo(first[y]!));
  final idOf = {for (final (n, c) in order.indexed) c: n + 1};
  final prints = {
    for (final c in order)
      c: meanPrint([
        for (final i in printed)
          for (final (k, v) in lines[i].voices.indexed)
            if (pieceGroups[i]![k] == c) (v.print, v.ms)
      ]),
  };
  final speechOf = {for (final c in order) c: 0};
  for (final ts in turns.values) {
    for (final t in ts) {
      speechOf[t.group] = speechOf[t.group]! + t.ms;
    }
  }

  // 6. Names.
  final names = _names(order, prints, speechOf, me, people);

  // 7. The lines: printed ones as their turns, the others (too short for a
  // print) said by whoever spoke nearest in time.
  final out = <Phrase>[];
  for (final (i, l) in lines.indexed) {
    final ts = turns[i];
    if (ts != null) {
      out.addAll([for (final t in ts) t.phrase(l, names[t.group]!, idOf[t.group]!)]);
      continue;
    }
    final near = _nearestInTime(l, [for (final j in printed) for (final t in turns[j]!) t]);
    out.add(l.withSpeaker(names[near.group], idOf[near.group]));
  }
  return SpeakerResult(out, [
    for (final c in order) SpeakerGroup(id: idOf[c]!, label: names[c]!, print: prints[c]!, speechMs: speechOf[c]!),
  ]);
}

/// Average-linkage grouping of [prints]: groups merge while their mean
/// similarity is at least [at]. Returns each print's group, numbered in order
/// of first appearance. The nearest-neighbour chain keeps it to n² steps.
List<int> clusterPrints(List<Float32List> prints, double at) {
  final n = prints.length;
  final sim = Float32List(n * n);
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      sim[i * n + j] = sim[j * n + i] = similarity(prints[i], prints[j]);
    }
  }
  final size = List.filled(n, 1);
  final open = List.filled(n, true); // may still merge
  final parent = List.generate(n, (i) => i);
  var left = n;
  final chain = <int>[];
  while (left > 1) {
    if (chain.isEmpty) chain.add(open.indexOf(true));
    final a = chain.last;
    final prev = chain.length > 1 ? chain[chain.length - 2] : -1;
    var b = prev;
    var best = prev < 0 ? double.negativeInfinity : sim[a * n + prev];
    for (var k = 0; k < n; k++) {
      if (open[k] && k != a && sim[a * n + k] > best) {
        best = sim[a * n + k];
        b = k;
      }
    }
    if (b != prev) {
      chain.add(b);
      continue;
    }
    // a and prev are each other's nearest.
    chain
      ..removeLast()
      ..removeLast();
    if (best >= at) {
      for (var k = 0; k < n; k++) {
        if (!open[k] || k == a || k == prev) continue;
        final s = (size[a] * sim[a * n + k] + size[prev] * sim[prev * n + k]) / (size[a] + size[prev]);
        sim[a * n + k] = sim[k * n + a] = s;
      }
      size[a] += size[prev];
      open[prev] = false;
      parent[prev] = a;
      left -= 1;
    } else {
      // Neither has any group that close: both are done.
      open[a] = open[prev] = false;
      left -= 2;
    }
  }
  int root(int i) {
    while (parent[i] != i) {
      i = parent[i];
    }
    return i;
  }

  final number = <int, int>{};
  return [for (var i = 0; i < n; i++) number.putIfAbsent(root(i), () => number.length)];
}

/// Of [groups], the one whose print in [prints] (same order) is most like [p].
int _nearest(Float32List p, List<Float32List> prints, List<int> groups) {
  var best = 0;
  for (var k = 1; k < prints.length; k++) {
    if (similarity(p, prints[k]) > similarity(p, prints[best])) best = k;
  }
  return groups[best];
}

/// One stray between two of the same group's goes with them.
List<int> _smooth(List<int> who) {
  final out = [...who];
  for (var k = 1; k < out.length - 1; k++) {
    if (out[k - 1] == out[k + 1] && out[k] != out[k - 1]) out[k] = out[k - 1];
  }
  return out;
}

/// A stretch of one line said by one group: its words `from` ≤ k < `until`.
class _Turn {
  const _Turn(this.group, this.from, this.until, this.startMs, this.endMs);
  final int group;
  final int from;
  final int until;
  final int startMs;
  final int endMs;

  int get ms => endMs - startMs;

  _Turn by(int group) => _Turn(group, from, until, startMs, endMs);

  /// This part of [line], said by [speaker]. The first part keeps the line's id.
  Phrase phrase(Phrase line, String speaker, int group) {
    if (from == 0 && until >= line.words.length) return line.withSpeaker(speaker, group);
    final words = line.words.sublist(from, until);
    return Phrase(
      id: from == 0 ? line.id : null,
      startMs: startMs,
      endMs: endMs,
      text: words.map((w) => w.text).join(' '),
      words: words,
      voices: [for (final v in line.voices) if (v.endMs > startMs && v.startMs < endMs) v],
      speaker: speaker,
      speakerGroup: group,
    );
  }
}

/// [line] cut where the speaker of its windows ([who], one per voice piece)
/// changes, at the words.
List<_Turn> _turnsOf(Phrase line, List<int> who) {
  final voices = line.voices;
  if (who.toSet().length == 1 || line.words.length < 2) {
    // One speaker, or nothing to cut at: the group with most of its windows' time.
    final time = <int, int>{};
    for (final (k, v) in voices.indexed) {
      time[who[k]] = (time[who[k]] ?? 0) + v.ms;
    }
    final most = time.keys.reduce((x, y) => time[y]! > time[x]! ? y : x);
    return [_Turn(most, 0, line.words.length, line.startMs, line.endMs)];
  }
  int at(Word w) {
    final mid = w.startMs + w.endMs;
    int off(VoicePiece v) => (mid - v.startMs - v.endMs).abs(); // twice the distance between middles
    var best = 0;
    for (var k = 1; k < voices.length; k++) {
      if (off(voices[k]) < off(voices[best])) best = k;
    }
    return who[best];
  }

  final byWord = _smooth([for (final w in line.words) at(w)]);
  var runs = <(int, int, int)>[]; // (group, from, to)
  for (var k = 0; k < byWord.length; k++) {
    if (runs.isNotEmpty && runs.last.$1 == byWord[k]) {
      runs.last = (runs.last.$1, runs.last.$2, k + 1);
    } else {
      runs.add((byWord[k], k, k + 1));
    }
  }
  // A turn shorter than kMinTurnMs joins the one before it (the first, the one after).
  int span((int, int, int) r) => line.words[r.$3 - 1].endMs - line.words[r.$2].startMs;
  while (runs.length > 1) {
    final k = runs.indexWhere((r) => span(r) < kMinTurnMs);
    if (k < 0) break;
    final r = runs.removeAt(k);
    if (k > 0) {
      runs[k - 1] = (runs[k - 1].$1, runs[k - 1].$2, r.$3);
    } else {
      runs[0] = (runs[0].$1, r.$2, runs[0].$3);
    }
    runs = _merged(runs);
  }
  return [
    for (final (k, r) in runs.indexed)
      _Turn(r.$1, r.$2, r.$3, k == 0 ? line.startMs : line.words[r.$2].startMs,
          k == runs.length - 1 ? line.endMs : line.words[r.$3 - 1].endMs),
  ];
}

/// Neighbouring runs of one group made one.
List<(int, int, int)> _merged(List<(int, int, int)> runs) {
  final out = <(int, int, int)>[];
  for (final r in runs) {
    if (out.isNotEmpty && out.last.$1 == r.$1) {
      out.last = (r.$1, out.last.$2, r.$3);
    } else {
      out.add(r);
    }
  }
  return out;
}

/// A line's turns, neighbours of one group made one.
List<_Turn> _joined(List<_Turn> turns) {
  final out = <_Turn>[];
  for (final t in turns) {
    if (out.isNotEmpty && out.last.group == t.group) {
      out.last = _Turn(t.group, out.last.from, t.until, out.last.startMs, t.endMs);
    } else {
      out.add(t);
    }
  }
  return out;
}

_Turn _nearestInTime(Phrase l, List<_Turn> turns) {
  int gap(_Turn t) => t.endMs < l.startMs ? l.startMs - t.endMs : (t.startMs > l.endMs ? t.startMs - l.endMs : 0);
  return turns.reduce((x, y) => gap(y) < gap(x) ? y : x);
}

/// "Me", remembered people (best pairs first, one group each), then "Person N".
Map<int, String> _names(
    List<int> order, Map<int, Float32List> prints, Map<int, int> speech, Float32List? me, List<KnownVoice> people) {
  final names = <int, String>{};
  if (me != null) {
    final best = order.reduce((x, y) => similarity(me, prints[y]!) > similarity(me, prints[x]!) ? y : x);
    if (similarity(me, prints[best]!) >= kMeAt) names[best] = kMeLabel;
  }
  final pairs = [
    for (final c in order)
      if (!names.containsKey(c) && speech[c]! >= kMinNamedMs)
        for (final p in people) (similarity(p.print, prints[c]!), c, p.name),
  ]..sort((x, y) => y.$1.compareTo(x.$1));
  final taken = <String>{};
  for (final (score, c, name) in pairs) {
    if (score >= kPersonAt && !names.containsKey(c) && taken.add(name.toLowerCase())) names[c] = name;
  }
  // "Person N" skips any number a remembered name already took.
  var n = 0;
  for (final c in order) {
    if (names.containsKey(c)) continue;
    String label;
    do {
      label = personLabel(++n);
    } while (names.values.any((v) => v.toLowerCase() == label.toLowerCase()));
    names[c] = label;
  }
  return names;
}
