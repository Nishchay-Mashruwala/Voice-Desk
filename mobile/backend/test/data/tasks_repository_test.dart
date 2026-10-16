import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/data/tasks_repository.dart';
import 'package:mobile_backend/engine/tasks/task_answer.dart';

void main() {
  late AppDatabase db;
  late LocalRecordingsRepository recordings;
  late TasksRepository tasks;
  late int meeting;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    recordings = LocalRecordingsRepository(db, Directory.systemTemp.createTempSync('tasks'));
    tasks = TasksRepository(db);
    meeting = (await recordings.create(title: 'Weekly review', startedAt: DateTime(2026, 10, 16, 9))).id;
  });
  tearDown(() => db.close());

  FoundTask ai(String description, [String? quote]) =>
      FoundTask(description: description, assignedBy: 'Person 1', due: 'by Friday', quote: quote ?? description.toLowerCase());

  Future<List<String>> shown() async => [for (final t in await tasks.watchFor(meeting).first) t.description];

  test('found tasks are saved with the summary', () async {
    await tasks.saveFound(meeting, 'We planned the launch.', [(ai('Send the report'), 12000), (ai('Fix the bug'), null)]);
    expect((await recordings.get(meeting))!.summary, 'We planned the launch.');
    final saved = await tasks.watchFor(meeting).first;
    expect([for (final t in saved) (t.description, t.assignedBy, t.due, t.quoteMs, t.fromAi, t.done)], [
      ('Send the report', 'Person 1', 'by Friday', 12000, true, false),
      ('Fix the bug', 'Person 1', 'by Friday', null, true, false),
    ]);
    expect(saved.first.meetingTitle, 'Weekly review');
  });

  test("a re-run replaces untouched AI tasks and keeps the owner's", () async {
    await tasks.saveFound(meeting, 'One.', [(ai('Send the report'), null), (ai('Fix the bug'), null), (ai('Book a room'), null)]);
    final saved = await tasks.watchFor(meeting).first;
    await tasks.edit(saved[0].id, description: 'Send the Q3 report');
    await tasks.setDone(saved[1].id, true);
    await tasks.add('Call the bank', meetingId: meeting);
    await tasks.saveFound(meeting, 'Two.', [(ai('Send the report again', 'send the report'), null), (ai('Write the notes'), null)]);
    expect(await shown(), ['Send the Q3 report', 'Call the bank', 'Write the notes', 'Fix the bug'],
        reason: 'edited and ticked kept, their quotes not found twice; Book a room replaced');
    expect((await recordings.get(meeting))!.summary, 'Two.');
  });

  test('a deleted AI task is not found again', () async {
    await tasks.saveFound(meeting, 'One.', [(ai('Send the report'), null), (ai('Fix the bug'), null)]);
    final saved = await tasks.watchFor(meeting).first;
    await tasks.delete(saved[0].id);
    expect(await shown(), ['Fix the bug']);
    await tasks.saveFound(meeting, 'Two.', [(ai('Send the report'), null), (ai('Fix the bug'), null)]);
    expect(await shown(), ['Fix the bug']);
  });

  test("the owner's own task is removed when deleted", () async {
    final id = await tasks.add('Call the bank');
    await tasks.delete(id);
    expect(await db.select(db.tasks).get(), isEmpty);
  });

  test('a task found again keeps its row: an edit or delete made meanwhile still lands', () async {
    await tasks.saveFound(meeting, 'One.', [(ai('Send the report'), null), (ai('Fix the bug'), null), (ai('Book a room'), null)]);
    final before = await tasks.watchFor(meeting).first;
    await tasks.saveFound(meeting, 'Two.', [(ai('Send the report'), 9000), (ai('Fix the bug'), null)]);
    final after = await tasks.watchFor(meeting).first;
    expect([for (final t in after) (t.id, t.description)], [(before[0].id, 'Send the report'), (before[1].id, 'Fix the bug')],
        reason: 'the same rows, in the same places; Book a room, not found again, goes');
    expect(after[0].quoteMs, 9000, reason: 'updated from the new run');
    // The owner's edit dialog was open during the run; his Save still lands.
    await tasks.edit(before[0].id, description: 'Send the Q3 report');
    await tasks.delete(before[1].id);
    expect(await shown(), ['Send the Q3 report']);
  });

  test('a re-run keeps a task changed during it', () async {
    await tasks.saveFound(meeting, 'One.', [(ai('Send the report'), null)]);
    final first = (await tasks.watchFor(meeting).first).single;
    // Find tasks runs again; meanwhile the owner ticks it.
    await tasks.setDone(first.id, true);
    await tasks.saveFound(meeting, 'Two.', [(ai('Send the report'), null)]);
    final now = await tasks.watchFor(meeting).first;
    expect([for (final t in now) (t.id, t.done)], [(first.id, true)]);
  });

  test('the Tasks tab order: open by position, done last', () async {
    final other = (await recordings.create(title: 'Standup', startedAt: DateTime(2026, 10, 16, 10))).id;
    await tasks.saveFound(meeting, 'One.', [(ai('A'), null), (ai('B'), null)]);
    await tasks.saveFound(other, 'Two.', [(ai('C'), null)]);
    final d = await tasks.add('D');
    var all = await tasks.watchAll().first;
    expect([for (final t in all) t.description], ['A', 'B', 'C', 'D']);
    await tasks.reorder([d, all[2].id, all[0].id, all[1].id]);
    await tasks.setDone(all[2].id, true);
    all = await tasks.watchAll().first;
    expect([for (final t in all) t.description], ['D', 'A', 'B', 'C']);
    expect([for (final t in all) t.done], [false, false, false, true]);
  });

  test('editing the due date, and clearing it', () async {
    final id = await tasks.add('Call the bank');
    await tasks.edit(id, due: 'tomorrow');
    expect((await tasks.watchAll().first).single.due, 'tomorrow');
    await tasks.edit(id, due: '');
    expect((await tasks.watchAll().first).single.due, isNull);
  });

  test("a recording's tasks go with it", () async {
    await tasks.saveFound(meeting, 'One.', [(ai('Send the report'), null)]);
    await tasks.add('Call the bank');
    await recordings.delete(meeting);
    expect([for (final t in await tasks.watchAll().first) t.description], ['Call the bank']);
  });

  group('the queue', () {
    test('waiting recordings, oldest first, and where each got to', () async {
      final later = (await recordings.create(startedAt: DateTime(2026, 10, 16, 11))).id;
      for (final id in [meeting, later]) {
        await recordings.setStatus(id, RecordingStatus.done);
        await recordings.setTasksStatus(id, TasksStatus.waiting);
      }
      await recordings.saveTasksPart(meeting, 2, '{"summaries": []}');
      final waiting = await recordings.tasksWaiting();
      expect([for (final r in waiting) r.id], [meeting, later]);
      expect((waiting.first.tasksStatus, waiting.first.tasksPart, waiting.first.tasksWork),
          (TasksStatus.finding, 2, '{"summaries": []}'));
      await recordings.setTasksStatus(meeting, TasksStatus.found);
      expect([for (final r in await recordings.tasksWaiting()) r.id], [later]);
    });

    test('a recording still being turned into text is not waiting for tasks', () async {
      await recordings.setTasksStatus(meeting, TasksStatus.waiting);
      expect(await recordings.tasksWaiting(), isEmpty);
    });

    test('a new status starts the work over', () async {
      await recordings.setStatus(meeting, RecordingStatus.done);
      await recordings.saveTasksPart(meeting, 3, 'work');
      await recordings.setTasksStatus(meeting, TasksStatus.waiting);
      final r = (await recordings.get(meeting))!;
      expect((r.tasksStatus, r.tasksPart, r.tasksWork), (TasksStatus.waiting, 0, ''));
    });
  });
}
