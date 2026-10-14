import 'dart:convert';

import 'package:drift/drift.dart';

import 'db.dart';
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
  Future<void> save(int meetingId, List<Phrase> phrases, {required int processedMs}) => _db.transaction(() async {
        final m = await (_db.select(_db.meetings)..where((m) => m.id.equals(meetingId))).getSingleOrNull();
        if (m == null) throw RecordingGone(meetingId);
        for (final p in phrases) {
          await _db.into(_db.transcriptLines).insert(TranscriptLinesCompanion.insert(
                meetingId: meetingId,
                startMs: p.startMs,
                endMs: p.endMs,
                content: p.text,
                wordsJson: jsonEncode([
                  for (final w in p.words) [w.text, w.startMs, w.endMs],
                ]),
              ));
        }
        if (processedMs > m.processedMs) {
          await (_db.update(_db.meetings)..where((r) => r.id.equals(meetingId)))
              .write(MeetingsCompanion(processedMs: Value(processedMs)));
        }
      });

  /// The recording's lines in time order, updated as lines are saved.
  Stream<List<Phrase>> watch(int meetingId) => (_db.select(_db.transcriptLines)
        ..where((l) => l.meetingId.equals(meetingId))
        ..orderBy([(l) => OrderingTerm.asc(l.startMs), (l) => OrderingTerm.asc(l.id)]))
      .watch()
      .map((rows) => rows.map(_toPhrase).toList());

  Future<int> processedMs(int meetingId) async =>
      (await (_db.select(_db.meetings)..where((m) => m.id.equals(meetingId))).getSingleOrNull())?.processedMs ?? 0;

  Phrase _toPhrase(TranscriptLine l) => Phrase(
        startMs: l.startMs,
        endMs: l.endMs,
        text: l.content,
        words: [
          for (final w in jsonDecode(l.wordsJson) as List) Word(w[0] as String, w[1] as int, w[2] as int),
        ],
      );
}
