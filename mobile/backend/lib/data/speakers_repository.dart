import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../engine/speakers/grouping.dart';
import '../engine/speakers/voice_print.dart';
import 'db.dart';
import 'settings_repository.dart';
import 'transcript_repository.dart';

/// Your trained voice (base64 print) and when it was saved (ms since epoch).
const kVoicePrintKey = 'voice_print';
const kVoiceSavedAtKey = 'voice_saved_at';

/// A voice is remembered from at least this much of the person's speech…
const kRememberMinMs = 2000;

/// …and at most this much.
const kRememberMaxMs = 30000;

/// Your own lines ("Me") are named by your trained voice, not by hand.
class CantRenameMe implements Exception {
  const CantRenameMe();
}

/// Too little of the person's speech to remember their voice.
class NotEnoughSpeech implements Exception {
  const NotEnoughSpeech(this.speechMs);
  final int speechMs;

  @override
  String toString() => 'NotEnoughSpeech($speechMs ms)';
}

/// A person whose voice is recognised in new recordings.
@immutable
class RememberedPerson {
  const RememberedPerson({required this.id, required this.name, required this.speechMs});
  final int id;
  final String name;

  /// How much of their speech their voice was learned from.
  final int speechMs;
}

/// Who said what: a recording's speaker groups, your voice, and the people
/// whose voices are remembered.
class SpeakersRepository {
  SpeakersRepository(this._db) : _settings = SettingsRepository(_db);

  final AppDatabase _db;
  final SettingsRepository _settings;

  /// Your voice, once trained.
  Future<Float32List?> myVoice() async {
    final text = await _settings.getString(kVoicePrintKey);
    return text.isEmpty ? null : decodePrint(text);
  }

  Future<DateTime?> myVoiceSavedAt() async {
    final ms = int.tryParse(await _settings.getString(kVoiceSavedAtKey));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> saveMyVoice(Float32List print, {required DateTime at}) => _db.transaction(() async {
        await _settings.setString(kVoicePrintKey, encodePrint(print));
        await _settings.setString(kVoiceSavedAtKey, '${at.millisecondsSinceEpoch}');
      });

  /// Past recordings keep their "Me" lines.
  Future<void> forgetMyVoice() => _db.transaction(() async {
        await _settings.setString(kVoicePrintKey, '');
        await _settings.setString(kVoiceSavedAtKey, '');
      });

  /// The remembered people, by name.
  Future<List<KnownVoice>> people() async => [
        for (final p in await (_db.select(_db.people)..orderBy([(p) => OrderingTerm.asc(p.nameKey)])).get())
          KnownVoice(p.name, decodePrint(p.printB64)),
      ];

  /// The remembered people, by name, as they change.
  Stream<List<RememberedPerson>> watchPeople() =>
      (_db.select(_db.people)..orderBy([(p) => OrderingTerm.asc(p.nameKey)])).watch().map((rows) => [
            for (final p in rows) RememberedPerson(id: p.id, name: p.name, speechMs: p.speechMs),
          ]);

  /// A remembered person's new name (a name already remembered: the two become one).
  Future<void> renamePerson(int id, String name) => _db.transaction(() async {
        final fixed = _checked(name);
        final person = await (_db.select(_db.people)..where((p) => p.id.equals(id))).getSingleOrNull();
        if (person == null) return;
        final key = fixed.toLowerCase();
        final other =
            await (_db.select(_db.people)..where((p) => p.nameKey.equals(key) & p.id.equals(id).not())).getSingleOrNull();
        if (other == null) {
          await (_db.update(_db.people)..where((p) => p.id.equals(id))).write(PeopleCompanion(
                name: Value(fixed),
                nameKey: Value(key),
                updatedAt: Value(DateTime.now()),
              ));
          return;
        }
        final merged = meanPrint([
          (decodePrint(other.printB64), other.speechMs),
          (decodePrint(person.printB64), person.speechMs),
        ]);
        await (_db.delete(_db.people)..where((p) => p.id.equals(id))).go();
        await (_db.update(_db.people)..where((p) => p.id.equals(other.id))).write(PeopleCompanion(
              name: Value(fixed),
              printB64: Value(encodePrint(merged)),
              speechMs: Value(other.speechMs + person.speechMs),
              updatedAt: Value(DateTime.now()),
            ));
      });

  /// Their voice is no longer recognised; past recordings keep their name.
  Future<void> forgetPerson(int id) => (_db.delete(_db.people)..where((p) => p.id.equals(id))).go();

  /// "Said by…": only this line is said by [label] (one of its recording's
  /// groups, [groupId], or someone else); no voice print changes.
  Future<void> moveLine(int lineId, {int? groupId, required String label}) async {
    final name = label.trim();
    if (name.isEmpty) throw ArgumentError.value(label, 'label', 'a name');
    final changed = await (_db.update(_db.transcriptLines)..where((l) => l.id.equals(lineId)))
        .write(TranscriptLinesCompanion(speaker: Value(name), speakerGroup: Value(groupId)));
    if (changed == 0) throw LineGone(lineId);
  }

  /// A recording's speaker groups (of its Process again run when [draft]), in order.
  Future<List<SpeakerGroup>> groups(int meetingId, {bool draft = false}) async => [
        for (final g in await (_db.select(_db.meetingSpeakers)
              ..where((s) => s.meetingId.equals(meetingId) & s.draft.equals(draft))
              ..orderBy([(s) => OrderingTerm.asc(s.groupId)]))
            .get())
          SpeakerGroup(id: g.groupId, label: g.label, print: decodePrint(g.printB64), speechMs: g.speechMs),
      ];

  /// The recording's speaker groups as they change (renames).
  Stream<List<SpeakerGroup>> watchGroups(int meetingId) => (_db.select(_db.meetingSpeakers)
        ..where((s) => s.meetingId.equals(meetingId) & s.draft.equals(false))
        ..orderBy([(s) => OrderingTerm.asc(s.groupId)]))
      .watch()
      .map((rows) => [
            for (final g in rows)
              SpeakerGroup(id: g.groupId, label: g.label, print: decodePrint(g.printB64), speechMs: g.speechMs),
          ]);

  /// Names a recording's speaker [groupId] [name] (trimmed), on all its lines.
  /// With [remember], their voice is recognised in later recordings: learned
  /// from up to [kRememberMaxMs] of their lines, merged with a person of that
  /// name (any case) if there is one.
  Future<void> rename(int meetingId, int groupId, String name, {required bool remember}) async {
    final fixed = _checked(name);
    await _db.transaction(() async {
      final group = await (_db.select(_db.meetingSpeakers)
            ..where((s) => s.meetingId.equals(meetingId) & s.groupId.equals(groupId) & s.draft.equals(false)))
          .getSingleOrNull();
      if (group == null) throw RecordingGone(meetingId);
      if (group.label == kMeLabel) throw const CantRenameMe();
      if (remember) await _remember(meetingId, groupId, fixed);
      await (_db.update(_db.transcriptLines)
            ..where((l) => l.meetingId.equals(meetingId) & l.speakerGroup.equals(groupId) & l.draft.equals(false)))
          .write(TranscriptLinesCompanion(speaker: Value(fixed)));
      await (_db.update(_db.meetingSpeakers)..where((s) => s.id.equals(group.id)))
          .write(MeetingSpeakersCompanion(label: Value(fixed)));
    });
  }

  /// [name] trimmed; not empty, not "Me".
  String _checked(String name) {
    final fixed = name.trim();
    if (fixed.isEmpty || fixed.toLowerCase() == kMeLabel.toLowerCase()) {
      throw ArgumentError.value(name, 'name', 'a name other than Me');
    }
    return fixed;
  }

  /// The group's voice, from its lines in time order (up to [kRememberMaxMs]),
  /// saved as [name]'s.
  Future<void> _remember(int meetingId, int groupId, String name) async {
    final lines = await (_db.select(_db.transcriptLines)
          ..where((l) => l.meetingId.equals(meetingId) & l.speakerGroup.equals(groupId) & l.draft.equals(false))
          ..orderBy([(l) => OrderingTerm.asc(l.startMs)]))
        .get();
    final pieces = <(Float32List, int)>[];
    var speech = 0;
    for (final l in lines) {
      if (speech >= kRememberMaxMs) break;
      final voices = jsonDecode(l.voicesJson) as List;
      if (voices.isEmpty) continue;
      speech += l.endMs - l.startMs;
      for (final v in voices) {
        pieces.add((decodePrint(v[2] as String), (v[1] as int) - (v[0] as int)));
      }
    }
    speech = speech.clamp(0, kRememberMaxMs);
    if (speech < kRememberMinMs) throw NotEnoughSpeech(speech);
    final print = meanPrint(pieces);
    final key = name.toLowerCase();
    final known = await (_db.select(_db.people)..where((p) => p.nameKey.equals(key))).getSingleOrNull();
    if (known == null) {
      await _db.into(_db.people).insert(PeopleCompanion.insert(
          name: name, nameKey: key, printB64: encodePrint(print), speechMs: speech, updatedAt: DateTime.now()));
      return;
    }
    final merged = meanPrint([(decodePrint(known.printB64), known.speechMs), (print, speech)]);
    await (_db.update(_db.people)..where((p) => p.id.equals(known.id))).write(PeopleCompanion(
          name: Value(name),
          printB64: Value(encodePrint(merged)),
          speechMs: Value(known.speechMs + speech),
          updatedAt: Value(DateTime.now()),
        ));
  }

  /// The speakers step's result for a run's lines: lines with an id are
  /// updated (a line cut in two keeps its id on the first part), new parts
  /// added, and the run's groups replaced.
  Future<void> saveGroups(int meetingId, SpeakerResult r, {required bool draft}) => _db.transaction(() async {
        final m = await (_db.select(_db.meetings)..where((m) => m.id.equals(meetingId))).getSingleOrNull();
        if (m == null) throw RecordingGone(meetingId);
        for (final l in r.lines) {
          final row = TranscriptLinesCompanion(
            meetingId: Value(meetingId),
            startMs: Value(l.startMs),
            endMs: Value(l.endMs),
            content: Value(l.text),
            wordsJson: Value(encodeWords(l.words)),
            voicesJson: Value(encodeVoices(l.voices)),
            speaker: Value(l.speaker),
            speakerGroup: Value(l.speakerGroup),
            draft: Value(draft),
          );
          if (l.id == null) {
            await _db.into(_db.transcriptLines).insert(row);
          } else {
            await (_db.update(_db.transcriptLines)..where((t) => t.id.equals(l.id!))).write(row);
          }
        }
        await (_db.delete(_db.meetingSpeakers)..where((s) => s.meetingId.equals(meetingId) & s.draft.equals(draft)))
            .go();
        for (final g in r.groups) {
          await _db.into(_db.meetingSpeakers).insert(MeetingSpeakersCompanion.insert(
                meetingId: meetingId,
                groupId: g.id,
                label: g.label,
                printB64: encodePrint(g.print),
                speechMs: g.speechMs,
                draft: Value(draft),
              ));
        }
      });
}
