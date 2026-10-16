import 'dart:convert';

import 'package:drift/drift.dart';

import 'db.dart';
import '../engine/speakers/voice_print.dart';
import 'retime.dart';
import 'transcript.dart';

/// The recording was deleted while it was being worked on.
class RecordingGone implements Exception {
  const RecordingGone(this.id);
  final int id;

  @override
  String toString() => 'RecordingGone($id)';
}

/// Transcript lines, and how far speech to text has got.
class TranscriptRepository {
  TranscriptRepository(this._db);

  final AppDatabase _db;

  /// Adds [phrases] and moves `processedMs` forward (never back), together.
  /// [draft]: lines of a Process again run, hidden until [commitDraft].
  Future<void> save(int meetingId, List<Phrase> phrases, {required int processedMs, bool draft = false}) =>
      _db.transaction(() async {
        final m = await (_db.select(_db.meetings)..where((m) => m.id.equals(meetingId))).getSingleOrNull();
        if (m == null) throw RecordingGone(meetingId);
        for (final p in phrases) {
          await _db.into(_db.transcriptLines).insert(TranscriptLinesCompanion.insert(
                meetingId: meetingId,
                startMs: p.startMs,
                endMs: p.endMs,
                content: p.text,
                wordsJson: encodeWords(p.words),
                draft: Value(draft),
                voicesJson: Value(encodeVoices(p.voices)),
                speaker: Value(p.speaker),
                speakerGroup: Value(p.speakerGroup),
              ));
        }
        if (processedMs > m.processedMs) {
          await (_db.update(_db.meetings)..where((r) => r.id.equals(meetingId)))
              .write(MeetingsCompanion(processedMs: Value(processedMs)));
        }
      });

  /// The recording's lines in time order, updated as lines are saved; without
  /// their voice prints (only the speakers step reads those).
  Stream<List<Phrase>> watch(int meetingId) => (_db.select(_db.transcriptLines)
        ..where((l) => l.meetingId.equals(meetingId) & l.draft.equals(false))
        ..orderBy([(l) => OrderingTerm.asc(l.startMs), (l) => OrderingTerm.asc(l.id)]))
      .watch()
      .map((rows) => [for (final l in rows) _toPhrase(l, voices: false)]);

  /// The lines of a run, with their voice prints, for the speakers step.
  Future<List<Phrase>> linesForGrouping(int meetingId, {required bool draft}) async =>
      (await (_db.select(_db.transcriptLines)
                ..where((l) => l.meetingId.equals(meetingId) & l.draft.equals(draft))
                ..orderBy([(l) => OrderingTerm.asc(l.startMs), (l) => OrderingTerm.asc(l.id)]))
              .get())
          .map(_toPhrase)
          .toList();

  Future<int> processedMs(int meetingId) async =>
      (await (_db.select(_db.meetings)..where((m) => m.id.equals(meetingId))).getSingleOrNull())?.processedMs ?? 0;

  /// A Process again run is complete: its lines (and speakers) replace the old ones, at once.
  Future<void> commitDraft(int meetingId) => _db.transaction(() async {
        await (_db.delete(_db.transcriptLines)..where((l) => l.meetingId.equals(meetingId) & l.draft.equals(false))).go();
        await (_db.update(_db.transcriptLines)..where((l) => l.meetingId.equals(meetingId)))
            .write(const TranscriptLinesCompanion(draft: Value(false)));
        await (_db.delete(_db.meetingSpeakers)..where((s) => s.meetingId.equals(meetingId) & s.draft.equals(false))).go();
        await (_db.update(_db.meetingSpeakers)..where((s) => s.meetingId.equals(meetingId)))
            .write(const MeetingSpeakersCompanion(draft: Value(false)));
        await (_db.update(_db.meetings)..where((m) => m.id.equals(meetingId)))
            .write(const MeetingsCompanion(reprocessing: Value(false)));
      });

  /// Fixes the words of a line (trimmed): unchanged words keep their times,
  /// new ones share the time around them; its start, end and place stay.
  Future<void> editLine(int lineId, String text) async {
    final fixed = text.trim();
    if (fixed.isEmpty) throw ArgumentError.value(text, 'text', "A line can't be empty");
    await _db.transaction(() async {
      final line = await (_db.select(_db.transcriptLines)..where((l) => l.id.equals(lineId))).getSingleOrNull();
      if (line == null) throw LineGone(lineId);
      final words = retimeWords(_words(line.wordsJson), fixed, line.startMs, line.endMs);
      await (_db.update(_db.transcriptLines)..where((l) => l.id.equals(lineId)))
          .write(TranscriptLinesCompanion(content: Value(fixed), wordsJson: Value(encodeWords(words))));
    });
  }

  Phrase _toPhrase(TranscriptLine l, {bool voices = true}) => Phrase(
        id: l.id,
        startMs: l.startMs,
        endMs: l.endMs,
        text: l.content,
        words: _words(l.wordsJson),
        voices: [
          if (voices)
            for (final v in jsonDecode(l.voicesJson) as List)
              VoicePiece(v[0] as int, v[1] as int, decodePrint(v[2] as String)),
        ],
        speaker: l.speaker,
        speakerGroup: l.speakerGroup,
      );
}

/// `[[startMs, endMs, "<print>"], …]`.
String encodeVoices(List<VoicePiece> voices) =>
    jsonEncode([for (final v in voices) [v.startMs, v.endMs, encodePrint(v.print)]]);

/// `[["word", startMs, endMs(, conf)], …]`.
String encodeWords(List<Word> words) => jsonEncode([
      for (final w in words) [w.text, w.startMs, w.endMs, if (w.conf != null) (w.conf! * 100).round() / 100],
    ]);

List<Word> _words(String json) => [
      for (final w in jsonDecode(json) as List)
        Word(w[0] as String, w[1] as int, w[2] as int, w.length > 3 ? (w[3] as num).toDouble() : null),
    ];

/// The line was deleted (with its recording) while being edited.
class LineGone implements Exception {
  const LineGone(this.lineId);
  final int lineId;

  @override
  String toString() => 'LineGone($lineId)';
}
