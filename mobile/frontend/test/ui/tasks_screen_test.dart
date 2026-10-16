import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/tasks_repository.dart';
import 'package:mobile_frontend/ui/recording/recording_detail_screen.dart';
import 'package:mobile_frontend/ui/tasks/tasks_screen.dart';

import 'fakes.dart';

void main() {
  late FakeTasks tasks;
  late List<String> copied;

  const report = TaskItem(id: 1, description: 'Send the report', meetingId: 7, meetingTitle: 'Weekly review', due: 'by Friday',
      assignedBy: 'Priya', quoteMs: 12000, fromAi: true);
  const bug = TaskItem(id: 2, description: 'Fix the login bug', meetingId: 7, meetingTitle: 'Weekly review', fromAi: true);
  const milk = TaskItem(id: 3, description: 'Buy milk');
  const booked = TaskItem(id: 4, description: 'Book the venue', done: true);

  Future<void> show(WidgetTester t, List<TaskItem> items) async {
    tasks = FakeTasks(items);
    copied = [];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    await t.pumpWidget(ProviderScope(
      overrides: [
        ...quietBackend(taskList: tasks),
        recordingsProvider.overrideWith((ref) => Stream.value(const <Recording>[])),
      ],
      child: const MaterialApp(home: Scaffold(body: TasksScreen())),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('with no tasks it says where they come from', (t) async {
    await show(t, const []);
    expect(find.text('My tasks'), findsOneWidget);
    expect(find.text('Tasks appear here after your recordings are processed.'), findsOneWidget);
    expect(find.text('Add a task…'), findsOneWidget);
  });

  testWidgets('open tasks first, completed behind Show N completed', (t) async {
    await show(t, const [report, bug, milk, booked]);
    expect(find.text('Send the report'), findsOneWidget);
    expect(find.text('by Friday · Priya · Weekly review'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Book the venue'), findsNothing);
    await t.tap(find.text('Show 1 completed'));
    await t.pumpAndSettle();
    expect(find.text('Book the venue'), findsOneWidget);
    await t.tap(find.text('Hide 1 completed'));
    await t.pumpAndSettle();
    expect(find.text('Book the venue'), findsNothing);
  });

  testWidgets('tick, edit, copy', (t) async {
    await show(t, const [report, milk]);
    await t.tap(find.byKey(const Key('task-done-3')));
    await t.pumpAndSettle();
    expect(tasks.calls, ['done:3:true']);
    expect(find.text('Show 1 completed'), findsOneWidget);

    await t.tap(find.text('Send the report'));
    await t.pumpAndSettle();
    expect(find.text('Due (e.g. Friday)'), findsOneWidget);
    await t.enterText(find.byKey(const Key('task-words')), 'Send the Q3 report');
    await t.enterText(find.byKey(const Key('task-due')), 'Monday');
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(tasks.calls.last, 'edit:1:Send the Q3 report:Monday');
    expect(find.text('Send the Q3 report'), findsOneWidget);

    await t.tap(find.byKey(const Key('task-menu-1')));
    await t.pumpAndSettle();
    await t.tap(find.text('Copy'));
    await t.pumpAndSettle();
    expect(copied, ['Send the Q3 report']);
    expect(find.text('Task copied'), findsOneWidget);
  });

  testWidgets('delete with Undo keeps it; without, it goes', (t) async {
    await show(t, const [report, milk]);
    await t.tap(find.byKey(const Key('task-menu-3')));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(find.text('Buy milk'), findsNothing, reason: 'hidden while Undo is offered');
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);
    expect(tasks.calls, isEmpty);

    await t.tap(find.byKey(const Key('task-menu-3')));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(tasks.calls, ['delete:3']);
    expect(find.text('Buy milk'), findsNothing);
  });

  testWidgets('add a task', (t) async {
    await show(t, const [report]);
    await t.enterText(find.byKey(const Key('add-task')), 'Call the bank');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(tasks.calls, ['add:Call the bank']);
    expect(find.text('Call the bank'), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const Key('add-task'))).controller!.text, '');
  });

  testWidgets('drag to reorder saves the order', (t) async {
    await show(t, const [report, bug, milk]);
    expect(find.byTooltip('Drag to reorder'), findsNWidgets(3));
    final handle = find.byKey(const Key('task-drag-3'));
    await t.drag(handle, const Offset(0, -300));
    await t.pumpAndSettle();
    expect(tasks.calls.single, startsWith('reorder:3,'));
  });

  testWidgets('Where it was said opens the recording at the line', (t) async {
    await show(t, const [report, milk]);
    await t.tap(find.byKey(const Key('task-menu-3')));
    await t.pumpAndSettle();
    expect(find.text('Where it was said'), findsNothing, reason: 'added by hand: said nowhere');
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('task-menu-1')));
    await t.pumpAndSettle();
    await t.tap(find.text('Where it was said'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    final screen = t.widget<RecordingDetailScreen>(find.byType(RecordingDetailScreen));
    expect((screen.recordingId, screen.playFromMs), (7, 12000));
  });
}
