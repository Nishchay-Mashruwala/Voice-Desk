import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;

import '../engine/tasks/task_answer.dart';
import 'db.dart';

/// One of the owner's tasks, as the screens show it.
@immutable
class TaskItem {
  const TaskItem({
    required this.id,
    required this.description,
    this.meetingId,
    this.meetingTitle,
    this.assignedBy,
    this.due,
    this.quote,
    this.quoteMs,
    this.done = false,
    this.fromAi = false,
  });

  final int id;
  final String description;

  /// The recording it came from, and its title (null: added by the owner).
  final int? meetingId;
  final String? meetingTitle;
  final String? assignedBy;
  final String? due;
  final String? quote;

  /// Where the quoted line starts ("Where it was said").
  final int? quoteMs;
  final bool done;
  final bool fromAi;

  TaskItem copyWith({String? description, String? due, bool? done}) => TaskItem(
        id: id,
        description: description ?? this.description,
        meetingId: meetingId,
        meetingTitle: meetingTitle,
        assignedBy: assignedBy,
        due: due ?? this.due,
        quote: quote,
        quoteMs: quoteMs,
        done: done ?? this.done,
        fromAi: fromAi,
      );
}

/// The owner's tasks: those the task AI found, and those he added.
class TasksRepository {
  TasksRepository(this._db);
  final AppDatabase _db;

  Stream<List<TaskItem>> _watch(Expression<bool> Function($TasksTable t) where) {
    final q = _db.select(_db.tasks).join([leftOuterJoin(_db.meetings, _db.meetings.id.equalsExp(_db.tasks.meetingId))])
      ..where(where(_db.tasks) & _db.tasks.deleted.equals(false))
      ..orderBy([OrderingTerm.asc(_db.tasks.done), OrderingTerm.asc(_db.tasks.position), OrderingTerm.asc(_db.tasks.id)]);
    return q.watch().map((rows) => [
          for (final r in rows)
            if (r.readTable(_db.tasks) case final t)
              TaskItem(
                id: t.id,
                description: t.description,
                meetingId: t.meetingId,
                meetingTitle: r.readTableOrNull(_db.meetings)?.title,
                assignedBy: t.assignedBy,
                due: t.due,
                quote: t.quote,
                quoteMs: t.quoteMs,
                done: t.done,
                fromAi: t.fromAi,
              ),
        ]);
  }

  /// Every task: the open ones in the owner's order, then the done ones.
  Stream<List<TaskItem>> watchAll() => _watch((t) => const Constant(true));

  /// A recording's tasks, in the same order.
  Stream<List<TaskItem>> watchFor(int meetingId) => _watch((t) => t.meetingId.equals(meetingId));

  Future<int> _nextPosition() async {
    final max = _db.tasks.position.max();
    final row = await (_db.selectOnly(_db.tasks)..addColumns([max])).getSingle();
    return (row.read(max) ?? -1) + 1;
  }

  /// A task of the owner's own, at the end of the list.
  Future<int> add(String description, {int? meetingId}) async => _db.into(_db.tasks).insert(TasksCompanion.insert(
        meetingId: Value(meetingId),
        description: description.trim(),
        position: await _nextPosition(),
        createdAt: DateTime.now(),
      ));

  /// New words or a new due date (blank: none); a re-run keeps it from now on.
  Future<void> edit(int id, {String? description, String? due}) =>
      (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(TasksCompanion(
        description: description == null ? const Value.absent() : Value(description.trim()),
        due: due == null ? const Value.absent() : Value(due.trim().isEmpty ? null : due.trim()),
        edited: const Value(true),
      ));

  /// Ticked or not; a re-run keeps it from now on.
  Future<void> setDone(int id, bool done) => (_db.update(_db.tasks)..where((t) => t.id.equals(id)))
      .write(TasksCompanion(done: Value(done), edited: const Value(true)));

  /// The owner's own task goes; an AI task stays hidden, so it isn't found again.
  Future<void> delete(int id) => _db.transaction(() async {
        final t = await (_db.select(_db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();
        if (t == null) return;
        if (t.fromAi) {
          await (_db.update(_db.tasks)..where((r) => r.id.equals(id))).write(const TasksCompanion(deleted: Value(true)));
        } else {
          await (_db.delete(_db.tasks)..where((r) => r.id.equals(id))).go();
        }
      });

  /// Brings a deleted task back (Undo).
  Future<void> restore(int id) =>
      (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(const TasksCompanion(deleted: Value(false)));

  /// The owner's order: [ids] get places 0, 1, 2, … (others keep theirs).
  Future<void> reorder(List<int> ids) => _db.transaction(() async {
        for (final (i, id) in ids.indexed) {
          await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(TasksCompanion(position: Value(i)));
        }
      });

  /// A recording's summary and the tasks the AI found, with where each quote
  /// starts. The AI's tasks the owner hasn't touched are updated in place when
  /// found again (same row: an edit dialog or a delete's Undo open meanwhile
  /// still lands on it) and removed when not; those he added, edited or ticked
  /// stay; a found task that one of those, or one he deleted, already covers
  /// (the same quote) isn't added again.
  Future<void> saveFound(int meetingId, String summary, List<(FoundTask, int?)> found) => _db.transaction(() async {
        final rows = await (_db.select(_db.tasks)..where((t) => t.meetingId.equals(meetingId))).get();
        bool untouched(TaskRow r) => r.fromAi && !r.edited && !r.deleted;
        final kept = [for (final r in rows) if (!untouched(r)) r];
        final free = [for (final r in rows) if (untouched(r)) r];
        var position = await _nextPosition();
        for (final (task, quoteMs) in found) {
          if (kept.any((k) => _same(k, task))) continue;
          final row = TasksCompanion(
            description: Value(task.description.trim()),
            assignedBy: Value(task.assignedBy),
            due: Value(task.due),
            quote: Value(task.quote),
            quoteMs: Value(quoteMs),
          );
          final again = free.where((r) => _same(r, task)).firstOrNull;
          if (again != null) {
            free.remove(again);
            await (_db.update(_db.tasks)..where((t) => t.id.equals(again.id))).write(row);
            continue;
          }
          await _db.into(_db.tasks).insert(row.copyWith(
                meetingId: Value(meetingId),
                position: Value(position++),
                fromAi: const Value(true),
                createdAt: Value(DateTime.now()),
              ));
        }
        for (final gone in free) {
          await (_db.delete(_db.tasks)..where((t) => t.id.equals(gone.id))).go();
        }
        await (_db.update(_db.meetings)..where((m) => m.id.equals(meetingId))).write(MeetingsCompanion(summary: Value(summary)));
      });

  static String _norm(String? s) => (s ?? '').replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}]', unicode: true), '').toLowerCase();

  /// The same task: one quote holds the other, or (without quotes) the same words.
  static bool _same(TaskRow kept, FoundTask t) {
    final a = _norm(kept.quote), b = _norm(t.quote);
    if (a.isNotEmpty && b.isNotEmpty) return a.contains(b) || b.contains(a);
    return _norm(kept.description) == _norm(t.description);
  }
}
