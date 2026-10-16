import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/permissions.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/speech/your_words.dart';
import 'package:mobile_backend/engine/tasks/task_settings.dart';
import 'package:mobile_frontend/ui/settings/settings_screen.dart';
import 'package:mobile_frontend/ui/settings/people_screen.dart';

import 'fakes.dart';

class FakePermissions implements PermissionsStatus {
  Map<String, bool> status = {'microphone': true, 'notifications': false, 'battery_unrestricted': false};
  final requested = <String>[];
  @override
  Future<Map<String, bool>> check() async => status;
  @override
  Future<void> request(String id) async {
    requested.add(id);
    status = {...status, id: true};
  }

  @override
  Future<void> openSettings() async {}
}

void main() {
  testWidgets('lists permissions with Allowed or Allow', (t) async {
    // A tall screen: the whole Settings page is built at once.
    t.view.physicalSize = const Size(1080, 8100);
    t.view.devicePixelRatio = 2.7;
    addTearDown(t.view.reset);
    final permissions = FakePermissions();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider.overrideWithValue(permissions),
          appVersionProvider.overrideWith((ref) async => '1.0.0'),
          ...quietBackend(),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Run unrestricted in the background'), findsOneWidget);
    expect(find.text('Allowed'), findsOneWidget);
    expect(find.text('Allow'), findsNWidgets(2));
    expect(find.text('Voice Desk 1.0.0'), findsOneWidget);

    await t.tap(find.descendant(of: find.widgetWithText(ListTile, 'Notifications'), matching: find.text('Allow')));
    await t.pumpAndSettle();
    expect(permissions.requested, ['notifications']);
    expect(find.text('Allowed'), findsNWidgets(2));
  });

  testWidgets('the Speech card offers what the settings still need, and the switch saves only_while_charging', (t) async {
    // A tall screen: the whole Settings page is built at once.
    t.view.physicalSize = const Size(1080, 8100);
    t.view.devicePixelRatio = 2.7;
    addTearDown(t.view.reset);
    final models = FakeModels();
    final charging = FakeOnlyWhileCharging();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider.overrideWithValue(FakePermissions()),
          appVersionProvider.overrideWith((ref) async => '1.0.0'),
          ...quietBackend(
            models: models,
            charging: charging,
            needed: const SpeechModelsState(ModelPhase.missing, bytesToDownload: 108678949),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Speech'), findsOneWidget);
    expect(find.text('Turn recordings into text: download the speech models (109 MB, Wi-Fi recommended).'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Download'));
    expect(models.neededDownloads, 1);
    await t.tap(find.text('Only process while charging'));
    await t.pumpAndSettle();
    expect(charging.sets, [true]);
  });

  testWidgets('your name, vocabulary and Leave out are saved when you leave each field', (t) async {
    final words = FakeYourWords(const YourWords(name: 'Nishchay'));
    await t.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWithValue(FakePermissions()),
        appVersionProvider.overrideWith((ref) async => '1.0.0'),
        ...quietBackend(yourWords: words),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
    ));
    await t.pumpAndSettle();
    expect(find.text('You and your words'), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const Key('your-name'))).controller!.text, 'Nishchay');
    await t.enterText(find.byKey(const Key('your-vocabulary')), 'Priya, Voice Desk');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.enterText(find.byKey(const Key('your-leave-out')), 'umm, uh');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(words.saved, ['vocabulary:Priya, Voice Desk', 'leaveOut:umm, uh']);
  });

  testWidgets('other names are saved when you leave the field', (t) async {
    final words = FakeYourWords(const YourWords(name: 'Nishchay'));
    await t.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWithValue(FakePermissions()),
        appVersionProvider.overrideWith((ref) async => '1.0.0'),
        ...quietBackend(yourWords: words),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
    ));
    await t.pumpAndSettle();
    expect(find.text('Other names people call you'), findsOneWidget);
    await t.enterText(find.byKey(const Key('your-aliases')), 'Nishu, Nish Bhai');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(words.saved, ['aliases:Nishu, Nish Bhai']);
  });

  testWidgets('People opens the People list', (t) async {
    t.view.physicalSize = const Size(1080, 8100);
    t.view.devicePixelRatio = 2.7;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWithValue(FakePermissions()),
        appVersionProvider.overrideWith((ref) async => '1.0.0'),
        ...quietBackend(myVoice: (Float32List(192), DateTime(2026, 10, 15))),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('People'));
    await t.pumpAndSettle();
    expect(find.byType(PeopleScreen), findsOneWidget);
  });

  testWidgets('the Storage row says what the page holds', (t) async {
    t.view.physicalSize = const Size(1080, 8100);
    t.view.devicePixelRatio = 2.7;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWithValue(FakePermissions()),
        appVersionProvider.overrideWith((ref) async => '1.0.0'),
        ...quietBackend(),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
    ));
    await t.pumpAndSettle();
    expect(find.text('Recordings, models and free space'), findsOneWidget);
  });

  group('Find tasks', () {
    Future<(FakeTaskSettings, FakeModels)> show(WidgetTester t,
        {PhoneClass phone = m31, Map<ModelId, ModelState> models = const {}}) async {
      t.view.physicalSize = const Size(1080, 8100);
      t.view.devicePixelRatio = 2.7;
      addTearDown(t.view.reset);
      final tasks = FakeTaskSettings();
      final fakeModels = FakeModels(models);
      await t.pumpWidget(ProviderScope(
        overrides: [
          permissionsProvider.overrideWithValue(FakePermissions()),
          appVersionProvider.overrideWith((ref) async => '1.0.0'),
          ...quietBackend(tasks: tasks, phone: phone, models: fakeModels),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ));
      await t.pumpAndSettle();
      return (tasks, fakeModels);
    }

    testWidgets('the Find tasks switch saves it', (t) async {
      final (tasks, _) = await show(t);
      expect(find.text('A summary and your tasks, after each recording'), findsOneWidget);
      expect(find.text('About 24 min more for a 30-minute recording'), findsOneWidget, reason: "the M31 test's speed until measured");
      await t.tap(find.text('Find tasks'));
      await t.pumpAndSettle();
      expect(tasks.sets, ['find_tasks:false']);
    });

    testWidgets('turning it on without the task model asks to download it first', (t) async {
      final (tasks, models) = await show(t, models: {ModelId.taskFaster: const ModelState(ModelPhase.missing)});
      await tasks.setFindTasks(false);
      tasks.sets.clear();
      await t.pumpAndSettle();
      await t.tap(find.text('Find tasks'));
      await t.pumpAndSettle();
      expect(find.text('Task AI (Faster) · 1107 MB'), findsOneWidget);
      await t.tap(find.text('Download'));
      await t.pumpAndSettle();
      expect(models.downloads, [ModelId.taskFaster]);
      expect(tasks.sets, ['find_tasks:true']);
    });

    testWidgets('Task AI shows only on an 8 GB phone', (t) async {
      await show(t);
      expect(find.text('Task AI'), findsNothing);
      expect(find.byType(RadioListTile<TaskAi>), findsNothing);
    });

    testWidgets('on an 8 GB phone More accurate can be chosen', (t) async {
      const big = PhoneClass(totalRamBytes: 73 * 1024 * 1024 * 1024 ~/ 10, dotProduct: true);
      final (tasks, _) = await show(t, phone: big);
      expect(find.text('Task AI'), findsOneWidget);
      expect(find.widgetWithText(RadioListTile<TaskAi>, '2497 MB'), findsOneWidget);
      await t.tap(find.widgetWithText(RadioListTile<TaskAi>, 'More accurate'));
      await t.pumpAndSettle();
      expect(tasks.sets, ['task_ai:accurate']);
    });
  });
}
