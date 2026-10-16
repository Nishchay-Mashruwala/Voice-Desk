import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/tasks_repository.dart';
import 'package:mobile_frontend/ui/app.dart';

import 'fakes.dart';

void main() {
  testWidgets('shows Record, Tasks and Settings tabs, Record first', (t) async {
    await t.pumpWidget(ProviderScope(overrides: quietBackend(), child: const VoiceDeskApp()));
    await t.pump(); // the setup flag is read first
    expect(find.text('Record'), findsWidgets);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    await t.tap(find.text('Tasks'));
    await t.pumpAndSettle();
    expect(find.text('Tasks appear here after your recordings are processed.'), findsOneWidget);
  });

  testWidgets("Undo on the Tasks tab keeps the task (the app's own shell, as on the phone)", (t) async {
    final tasks = FakeTasks(const [TaskItem(id: 3, description: 'Buy milk')]);
    await t.pumpWidget(ProviderScope(overrides: quietBackend(taskList: tasks), child: const VoiceDeskApp()));
    await t.pump();
    await t.tap(find.text('Tasks'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('task-menu-3')));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('Undo'));
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(tasks.calls, isEmpty);
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets('the app asks for portrait only', (t) async {
    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    await keepPortrait();
    final call = calls.singleWhere((c) => c.method == 'SystemChrome.setPreferredOrientations');
    expect(call.arguments, ['DeviceOrientation.portraitUp']);
  });
}
