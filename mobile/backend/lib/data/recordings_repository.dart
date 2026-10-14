import 'dart:io';

import 'package:drift/drift.dart';

import '../engine/audio/wav.dart';
import 'db.dart';
import 'recording.dart';

/// Recordings shorter than this aren't kept.
const kMinRecording = Duration(seconds: 1);

/// The one place the screens get and change recordings.
abstract class RecordingsRepository {
  /// Newest first.
  Stream<List<Recording>> watchAll();
  Future<Recording?> get(int id);

  /// A new recording (status `recording`); a blank title becomes the default.
  Future<Recording> create({String? title, required DateTime startedAt});
  Future<Directory> audioDir(int id);

  /// Its audio pieces, in order.
  Future<List<File>> pieces(int id);

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
  Future<Recording> create({String? title, required DateTime startedAt}) async {
    final name = (title ?? '').trim();
    final id = await _db.into(_db.meetings).insert(MeetingsCompanion.insert(
          title: name.isEmpty ? defaultTitle(startedAt) : name,
          startedAt: startedAt,
          status: RecordingStatus.recording.id,
        ));
    await audioDir(id);
    return (await get(id))!;
  }

  @override
  Future<Directory> audioDir(int id) => Directory('${_root.path}/$id').create(recursive: true);

  @override
  Future<List<File>> pieces(int id) async {
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
      for (final piece in await pieces(m.id)) {
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
    final waiting = [RecordingStatus.processing.id, RecordingStatus.queued.id, RecordingStatus.waitingCharge.id];
    final m = await (_db.select(_db.meetings)
          ..where((m) => m.status.isIn(waiting))
          ..orderBy([(m) => OrderingTerm.asc(m.startedAt), (m) => OrderingTerm.asc(m.id)])
          ..limit(1))
        .getSingleOrNull();
    return m == null ? null : _toRecording(m);
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
}
