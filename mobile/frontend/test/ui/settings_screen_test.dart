import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/permissions.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/speech/your_words.dart';
import 'package:mobile_frontend/ui/settings/settings_screen.dart';

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
    t.view.physicalSize = const Size(1080, 5400);
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

  testWidgets('the speech model card offers Download, and the switch saves only_while_charging', (t) async {
    // A tall screen: the whole Settings page is built at once.
    t.view.physicalSize = const Size(1080, 5400);
    t.view.devicePixelRatio = 2.7;
    addTearDown(t.view.reset);
    final model = FakeSpeechModel(const SpeechModelState(SpeechModelPhase.missing));
    final charging = FakeOnlyWhileCharging();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider.overrideWithValue(FakePermissions()),
          appVersionProvider.overrideWith((ref) async => '1.0.0'),
          speechModelProvider.overrideWith(() => model),
          onlyWhileChargingProvider.overrideWith(() => charging),
          processorProvider.overrideWith(IdleProcessor.new),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('English speech model · 105 MB'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Download'));
    expect(model.downloads, 1);
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
}
