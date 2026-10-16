import 'dart:io';

import 'package:drift/drift.dart';

import '../engine/audio/flac.dart';
import '../engine/audio/wav.dart';
import '../engine/speech/speech_setup.dart';
import 'db.dart';
import 'recording.dart';

/// Process again needs the recording's audio, and it is gone.
class NoAudio implements Exception {
  const NoAudio(this.id);
  final int id;

  @override
  String toString() => 'NoAudio($id)';
}

/// A FLAC that didn't match the pieces this many times isn't tried again.
const kMaxCompressFailures = 3;

/// Recordings shorter than this aren't kept.
const kMinRecording = Duration(seconds: 1);

/// The one place the screens get and change recordings.
abstract class RecordingsRepository {
  /// Newest first.
  Stream<List<Recording>> watchAll();
  Future<Recording?> get(int id);

  /// A new recording (status `recording`); a blank title becomes the default.
  Future<Recording> create({String? title, required DateTime startedAt, SpeechSetup setup = SpeechSetup.englishOnly});
  Future<Directory> audioDir(int id);

  /// Its audio: the WAV pieces in order while there are any (they are the
  /// audio until a checked FLAC replaces them), else its FLAC.
  Future<List<File>> pieces(int id);

  /// Its WAV pieces in order (left until compressed and checked).
  Future<List<File>> wavPieces(int id);

  /// Finished (done or failed) recordings whose pieces are still to be
  /// compressed, oldest first; not those that failed three times.
  Future<List<Recording>> toCompress();

  /// Its FLAC is written and checked: the pieces go, unless it is being
  /// processed again meanwhile (then a later pass deletes them).
  Future<void> compressed(int id);

  /// Its FLAC didn't match the pieces.
  Future<void> countCompressFailure(int id);

  /// Recordings with audio on the phone and its size in bytes, largest first
  /// (not one being recorded).
  Future<List<(Recording, int)>> audioSizes();

  /// Done recordings started before [cutoff] that still have audio.
  Future<List<Recording>> audioOlderThan(DateTime cutoff);

  /// Deletes its audio (FLAC and pieces); its text stays.
  Future<void> deleteAudio(int id);

  /// Recording finished: status `queued`.
  Future<void> finish(int id, Duration duration);
  Future<void> rename(int id, String title);
  Future<void> delete(int id);

  /// Recordings left `recording` by a crash or a kill: repairs their pieces and
  /// finishes them (or drops them when under [kMinRecording]). Returns how many were kept.
  Future<int> recoverInterrupted();

  Future<void> setStatus(int id, RecordingStatus status, {String? error});

  /// The oldest recording waiting to be turned into text (`processing`, `queued` or `waiting_charge`).
  Future<Recording?> nextToProcess();

  /// Every recording waiting to be processed, oldest first.
  Future<List<Recording>> toProcess();

  /// Queues a finished recording to be turned into text again with [setup];
  /// its lines stay until the new ones are complete. [NoAudio] when its audio
  /// is gone.
  Future<void> processAgain(int id, SpeechSetup setup);

  /// A Process again run found no audio: its drafts go, the old text stays.
  Future<void> cancelProcessAgain(int id);

  /// Whether a recording is being made now.
  Future<bool> anyRecording();

  /// Removes recordings' folders whose recording is gone (a delete that met
  /// a file being written).
  Future<void> removeOrphanFolders();

  /// Done recordings waiting for their summary and tasks (or cut off while
  /// finding them), oldest first.
  Future<List<Recording>> tasksWaiting();

  /// A new tasks status; the work so far starts over.
  Future<void> setTasksStatus(int id, TasksStatus status);

  /// The task step got as far as [part], with its answers so far ([work]).
  Future<void> saveTasksPart(int id, int part, String work);

  /// The task step failed: [why] is kept.
  Future<void> tasksFailed(int id, String why);

  /// One more processing job started for it; returns how many since the last finished one.
  Future<int> startAttempt(int id);
  Future<void> clearAttempts(int id);
}

class LocalRecordingsRepository implements RecordingsRepository {
  LocalRecordingsRepository(this._db, this._root);

  final AppDatabase _db;
  final Directory _root;

  Recording _toRecording(Meeting m) => Recording(
        id: m.id,
        title: m.title,
        kind: m.kind,
        startedAt: m.startedAt,
        duration: m.durationMs == null ? null : Duration(milliseconds: m.durationMs!),
        status: RecordingStatus.fromId(m.status),
        error: m.error,
        processedMs: m.processedMs,
        setup: SpeechSetup.parse(m.languages, m.preferIndic, m.englishModel, speakers: m.speakers),
        reprocessing: m.reprocessing,
        audioDeleted: m.audioDeleted,
        compressFailed: m.flacFailures >= kMaxCompressFailures,
        audioPath: m.audioPath,
        summary: m.summary,
        tasksStatus: TasksStatus.fromId(m.tasksStatus),
        tasksPart: m.tasksPart,
        tasksWork: m.tasksWork,
      );

  @override
  Stream<List<Recording>> watchAll() =>
      (_db.select(_db.meetings)..orderBy([(m) => OrderingTerm.desc(m.startedAt), (m) => OrderingTerm.desc(m.id)]))
          .watch()
          .map((rows) => rows.map(_toRecording).toList());

  @override
  Future<Recording?> get(int id) async {
    final m = await (_db.select(_db.meetings)..where((m) => m.id.equals(id))).getSingleOrNull();
    return m == null ? null : _toRecording(m);
  }

  @override
  Future<Recording> create({String? title, required DateTime startedAt, SpeechSetup setup = SpeechSetup.englishOnly}) async {
    final name = (title ?? '').trim();
    final id = await _db.into(_db.meetings).insert(MeetingsCompanion.insert(
          title: name.isEmpty ? defaultTitle(startedAt) : name,
          startedAt: startedAt,
          status: RecordingStatus.recording.id,
          languages: Value(setup.languagesCode),
          preferIndic: Value(setup.prefer.name),
          englishModel: Value(setup.english.name),
          speakers: Value(setup.speakers),
        ));
    await audioDir(id);
    return (await get(id))!;
  }

  @override
  Future<Directory> audioDir(int id) => Directory('${_root.path}/$id').create(recursive: true);

  @override
  Future<List<File>> pieces(int id) async {
    final wav = await wavPieces(id);
    if (wav.isNotEmpty) return wav;
    // The pieces go only once the FLAC is checked: then it is the audio.
    final flac = File('${_root.path}/$id/$kFlacName');
    return flac.existsSync() ? [flac] : const [];
  }

  @override
  Future<List<File>> wavPieces(int id) async {
    final dir = Directory('${_root.path}/$id');
    if (!dir.existsSync()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'piece-\d+\.wav$').hasMatch(f.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static final _finished = [RecordingStatus.done.id, RecordingStatus.error.id];

  @override
  Future<List<Recording>> toCompress() async {
    final rows = await (_db.select(_db.meetings)
          ..where((m) =>
              m.status.isIn(_finished) &
              m.audioDeleted.equals(false) &
              m.flacFailures.isSmallerThanValue(kMaxCompressFailures))
          ..orderBy([(m) => OrderingTerm.asc(m.startedAt), (m) => OrderingTerm.asc(m.id)]))
        .get();
    return [
      for (final m in rows)
        if ((await wavPieces(m.id)).isNotEmpty) _toRecording(m),
    ];
  }

  @override
  Future<void> compressed(int id) => _db.transaction(() async {
        final m = await (_db.select(_db.meetings)..where((m) => m.id.equals(id))).getSingleOrNull();
        final flac = File('${_root.path}/$id/$kFlacName');
        if (m == null || !flac.existsSync()) return;
        await (_db.update(_db.meetings)..where((r) => r.id.equals(id)))
            .write(MeetingsCompanion(audioPath: Value(flac.path)));
        // Being processed again: its job may be reading the pieces.
        if (!_finished.contains(m.status)) return;
        for (final p in await wavPieces(id)) {
          await p.delete();
        }
      });

  @override
  Future<List<(Recording, int)>> audioSizes() async {
    final rows = await (_db.select(_db.meetings)
          ..where((m) => m.status.equals(RecordingStatus.recording.id).not() & m.audioDeleted.equals(false)))
        .get();
    final out = <(Recording, int)>[];
    for (final m in rows) {
      final bytes = (await pieces(m.id)).fold(0, (sum, f) => sum + f.lengthSync());
      if (bytes > 0) out.add((_toRecording(m), bytes));
    }
    return out..sort((a, b) => b.$2.compareTo(a.$2));
  }

  @override
  Future<List<Recording>> audioOlderThan(DateTime cutoff) async {
    final rows = await (_db.select(_db.meetings)
          ..where((m) =>
              m.status.equals(RecordingStatus.done.id) &
              m.audioDeleted.equals(false) &
              m.startedAt.isSmallerThanValue(cutoff))
          ..orderBy([(m) => OrderingTerm.asc(m.startedAt)]))
        .get();
    return [for (final m in rows) _toRecording(m)];
  }

  @override
  Future<void> deleteAudio(int id) => _db.transaction(() async {
        // Only a done recording: one queued meanwhile (Process again) keeps it.
        final m = await (_db.select(_db.meetings)..where((m) => m.id.equals(id))).getSingleOrNull();
        if (m == null || m.status != RecordingStatus.done.id) return;
        await (_db.update(_db.meetings)..where((m) => m.id.equals(id)))
            .write(const MeetingsCompanion(audioDeleted: Value(true), audioPath: Value(null)));
        final dir = Directory('${_root.path}/$id');
        if (dir.existsSync()) {
          for (final f in dir.listSync().whereType<File>()) {
            if (f.path.endsWith('.wav') || f.path.endsWith('.flac') || f.path.endsWith('.flac.part')) await f.delete();
          }
        }
      });

  @override
  Future<bool> anyRecording() async =>
      (await (_db.select(_db.meetings)..where((m) => m.status.equals(RecordingStatus.recording.id))).get()).isNotEmpty;

  @override
  Future<void> removeOrphanFolders() async {
    if (!_root.existsSync()) return;
    final ids = {for (final m in await _db.select(_db.meetings).get()) m.id};
    for (final d in _root.listSync().whereType<Directory>()) {
      final id = int.tryParse(d.uri.pathSegments.where((s) => s.isNotEmpty).last);
      if (id != null && !ids.contains(id)) await d.delete(recursive: true);
    }
  }

  @override
  Future<void> cancelProcessAgain(int id) => _db.transaction(() async {
        await (_db.delete(_db.transcriptLines)..where((l) => l.meetingId.equals(id) & l.draft.equals(true))).go();
        await (_db.delete(_db.meetingSpeakers)..where((s) => s.meetingId.equals(id) & s.draft.equals(true))).go();
        await (_db.update(_db.meetings)..where((m) => m.id.equals(id))).write(MeetingsCompanion(
              reprocessing: const Value(false),
              attempts: const Value(0),
              status: Value(RecordingStatus.done.id),
              error: const Value(null),
            ));
      });

  @override
  Future<void> countCompressFailure(int id) =>
      _db.customUpdate('UPDATE meetings SET flac_failures = flac_failures + 1 WHERE id = ?',
          variables: [Variable.withInt(id)], updates: {_db.meetings});

  @override
  Future<void> finish(int id, Duration duration) =>
      (_db.update(_db.meetings)..where((m) => m.id.equals(id))).write(MeetingsCompanion(
        status: Value(RecordingStatus.queued.id),
        durationMs: Value(duration.inMilliseconds),
      ));

  @override
  Future<void> rename(int id, String title) async {
    final r = await get(id);
    if (r == null) return;
    final name = title.trim();
    await (_db.update(_db.meetings)..where((m) => m.id.equals(id)))
        .write(MeetingsCompanion(title: Value(name.isEmpty ? defaultTitle(r.startedAt) : name)));
  }

  @override
  Future<void> delete(int id) async {
    await (_db.delete(_db.meetings)..where((m) => m.id.equals(id))).go();
    final dir = Directory('${_root.path}/$id');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  @override
  Future<int> recoverInterrupted() async {
    final left = await (_db.select(_db.meetings)..where((m) => m.status.equals(RecordingStatus.recording.id))).get();
    var kept = 0;
    for (final m in left) {
      var length = Duration.zero;
      for (final piece in await wavPieces(m.id)) {
        await finalizeWav(piece);
        length += wavDuration(piece);
      }
      if (length < kMinRecording) {
        await delete(m.id);
      } else {
        await finish(m.id, length);
        kept++;
      }
    }
    return kept;
  }

  @override
  Future<void> setStatus(int id, RecordingStatus status, {String? error}) =>
      (_db.update(_db.meetings)..where((m) => m.id.equals(id)))
          .write(MeetingsCompanion(status: Value(status.id), error: Value(error)));

  @override
  Future<Recording?> nextToProcess() async {
    final all = await toProcess();
    return all.isEmpty ? null : all.first;
  }

  @override
  Future<void> processAgain(int id, SpeechSetup setup) => _db.transaction(() async {
        final m = await (_db.select(_db.meetings)..where((m) => m.id.equals(id))).getSingleOrNull();
        if (m == null || m.audioDeleted || (await pieces(id)).isEmpty) throw NoAudio(id);
        // Drafts of an earlier run that didn't finish start over.
        await (_db.delete(_db.transcriptLines)..where((l) => l.meetingId.equals(id) & l.draft.equals(true))).go();
        await (_db.delete(_db.meetingSpeakers)..where((s) => s.meetingId.equals(id) & s.draft.equals(true))).go();
        await (_db.update(_db.meetings)..where((m) => m.id.equals(id))).write(MeetingsCompanion(
              reprocessing: const Value(true),
              processedMs: const Value(0),
              attempts: const Value(0),
              status: Value(RecordingStatus.queued.id),
              error: const Value(null),
              languages: Value(setup.languagesCode),
              preferIndic: Value(setup.prefer.name),
              englishModel: Value(setup.english.name),
              speakers: Value(setup.speakers),
            ));
      });

  @override
  Future<List<Recording>> toProcess() async {
    final waiting = [RecordingStatus.processing.id, RecordingStatus.queued.id, RecordingStatus.waitingCharge.id];
    final rows = await (_db.select(_db.meetings)
          ..where((m) => m.status.isIn(waiting))
          ..orderBy([(m) => OrderingTerm.asc(m.startedAt), (m) => OrderingTerm.asc(m.id)]))
        .get();
    return rows.map(_toRecording).toList();
  }

  @override
  Future<int> startAttempt(int id) => _db.transaction(() async {
        final m = await (_db.select(_db.meetings)..where((m) => m.id.equals(id))).getSingle();
        final n = m.attempts + 1;
        await (_db.update(_db.meetings)..where((r) => r.id.equals(id))).write(MeetingsCompanion(attempts: Value(n)));
        return n;
      });

  @override
  Future<void> clearAttempts(int id) =>
      (_db.update(_db.meetings)..where((m) => m.id.equals(id))).write(const MeetingsCompanion(attempts: Value(0)));

  @override
  Future<List<Recording>> tasksWaiting() async {
    final rows = await (_db.select(_db.meetings)
          ..where((m) =>
              m.status.equals(RecordingStatus.done.id) &
              m.tasksStatus.isIn([TasksStatus.waiting.name, TasksStatus.finding.name]))
          ..orderBy([(m) => OrderingTerm.asc(m.startedAt), (m) => OrderingTerm.asc(m.id)]))
        .get();
    return rows.map(_toRecording).toList();
  }

  @override
  Future<void> setTasksStatus(int id, TasksStatus status) => (_db.update(_db.meetings)..where((m) => m.id.equals(id)))
      .write(MeetingsCompanion(tasksStatus: Value(status.name), tasksPart: const Value(0), tasksWork: const Value('')));

  @override
  Future<void> saveTasksPart(int id, int part, String work) => (_db.update(_db.meetings)..where((m) => m.id.equals(id)))
      .write(MeetingsCompanion(tasksStatus: Value(TasksStatus.finding.name), tasksPart: Value(part), tasksWork: Value(work)));

  @override
  Future<void> tasksFailed(int id, String why) => (_db.update(_db.meetings)..where((m) => m.id.equals(id)))
      .write(MeetingsCompanion(tasksStatus: Value(TasksStatus.failed.name), tasksPart: const Value(0), tasksWork: Value(why)));
}
