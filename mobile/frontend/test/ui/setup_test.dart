import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/permissions.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/speech/your_words.dart';
import 'package:mobile_frontend/ui/app.dart';
import 'package:mobile_frontend/ui/setup/setup_screen.dart';
import 'package:mobile_frontend/ui/widgets/badge.dart';

import 'fakes.dart';
import 'settings_screen_test.dart' show FakePermissions;

void main() {
  late FakeSetupDone done;
  late FakeModels models;
  late FakeYourWords words;
  late FakeSpeechSettings speech;
  late FakePermissions permissions;

  Future<void> open(
    WidgetTester t, {
    bool setupDone = false,
    Map<ModelId, ModelState> state = const {},
    SpeechModelsState needed = readyModels,
    YourWords yourWords = const YourWords(),
    (Float32List?, DateTime?) myVoice = (null, null),
  }) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.7;
    addTearDown(t.view.reset);
    done = FakeSetupDone(setupDone);
    models = FakeModels(state);
    words = FakeYourWords(yourWords);
    speech = FakeSpeechSettings(const SpeechSettings(languages: {Lang.en, Lang.gu}));
    permissions = FakePermissions();
    await t.pumpWidget(const SizedBox()); // a fresh scope for each open
    await t.pumpWidget(ProviderScope(
      overrides: [
        ...quietBackend(
          models: models,
          yourWords: words,
          speech: speech,
          needed: needed,
          myVoice: myVoice,
          setup: done,
        ),
        neededModelIdsProvider.overrideWithValue(const [ModelId.vad, ModelId.englishFaster, ModelId.gujarati]),
        permissionsProvider.overrideWithValue(permissions),
      ],
      child: const VoiceDeskApp(),
    ));
    await t.pumpAndSettle();
  }

  Future<void> next(WidgetTester t) async {
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
  }

  testWidgets('a new phone starts with the setup, an old flag goes straight to the tabs', (t) async {
    await open(t);
    expect(find.text('Speak, and it writes.'), findsOneWidget);
    expect(
      find.text('Voice Desk records your meetings and turns them into text — all on this phone, even offline.'),
      findsOneWidget,
    );
    expect(find.byType(NavigationBar), findsNothing);
    await open(t, setupDone: true);
    expect(find.byType(SetupScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('Next and Back move through the steps; Next is on while permissions are refused', (t) async {
    await open(t);
    await t.tap(find.text('Get started'));
    await t.pumpAndSettle();
    expect(find.text('to record'), findsOneWidget);
    expect(find.text('to show and stop a recording'), findsOneWidget);
    expect(find.text("so Android doesn't stop a long recording"), findsOneWidget);
    expect(find.text('Allowed'), findsOneWidget); // the microphone
    await t.tap(find.text('Allow').first);
    await t.pumpAndSettle();
    expect(permissions.requested, ['notifications']);
    await next(t);
    expect(find.text('Your name'), findsOneWidget);
    await t.tap(find.text('Back'));
    await t.pumpAndSettle();
    expect(find.text('to record'), findsOneWidget);
  });

  testWidgets('About you is saved when moving on', (t) async {
    await open(t);
    await t.tap(find.text('Get started'));
    await t.pumpAndSettle();
    await next(t);
    expect(find.text('How people say your name in meetings.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('setup-name')), 'Nishchay');
    await t.enterText(find.byKey(const Key('setup-aliases')), 'Nishu');
    await t.tap(find.widgetWithText(FilterChip, 'हिन्दी Hindi'));
    await t.pumpAndSettle();
    expect(find.text('Hindi or Gujarati — which do you speak more?'), findsOneWidget);
    await next(t);
    expect(words.saved, ['name:Nishchay', 'aliases:Nishu']);
    expect(speech.sets, contains('languages:en,hi,gu'));
  });

  testWidgets('Skip on Your voice goes to Download', (t) async {
    await open(t, state: {ModelId.gujarati: const ModelState(ModelPhase.missing)});
    await t.tap(find.text('Get started'));
    await t.pumpAndSettle();
    await next(t);
    await next(t);
    expect(find.text('Train my voice'), findsOneWidget);
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
    expect(find.text("Wi-Fi recommended. If it's interrupted, it continues where it stopped."), findsOneWidget);
  });

  Future<void> toDownload(WidgetTester t) async {
    await t.tap(find.text('Get started'));
    await t.pumpAndSettle();
    await next(t);
    await next(t);
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
  }

  testWidgets('Download lists what is needed with the total, and starts it', (t) async {
    final gujarati = kCatalogue[ModelId.gujarati]!.download.size + kCatalogue[ModelId.indicTokens]!.download.size;
    await open(
      t,
      state: {ModelId.gujarati: const ModelState(ModelPhase.missing), ModelId.indicTokens: const ModelState(ModelPhase.missing)},
      needed: SpeechModelsState(ModelPhase.missing, bytesToDownload: gujarati),
    );
    await toDownload(t);
    expect(find.text('Gujarati model'), findsOneWidget);
    expect(find.text('${(gujarati / 1000000).round()} MB'), findsOneWidget);
    expect(find.widgetWithText(VdBadge, 'Downloaded'), findsNWidgets(2)); // voice activity, English
    await t.tap(find.text('Download (${(gujarati / 1000000).round()} MB)'));
    await t.pumpAndSettle();
    expect(models.neededDownloads, 1);
  });

  testWidgets('Use the app while it downloads finishes the setup', (t) async {
    await open(
      t,
      state: {ModelId.gujarati: const ModelState(ModelPhase.missing)},
      needed: const SpeechModelsState(ModelPhase.downloading, done: 50000000, total: 200000000),
    );
    await toDownload(t);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await t.tap(find.text('Use the app while it downloads'));
    await t.pumpAndSettle();
    expect(done.finished, 1);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('with everything downloaded it says Voice Desk is ready', (t) async {
    await open(t);
    await toDownload(t);
    expect(find.text('Voice Desk is ready — it works offline from now on.'), findsOneWidget);
    await t.tap(find.text('Start'));
    await t.pumpAndSettle();
    expect(done.finished, 1);
  });

  testWidgets('on a phone in use the fields come filled and models show Downloaded', (t) async {
    await open(
      t,
      yourWords: const YourWords(name: 'Nishchay', aliases: 'Nishu'),
      myVoice: (Float32List(192), DateTime(2026, 10, 15)),
    );
    await t.tap(find.text('Get started'));
    await t.pumpAndSettle();
    await next(t);
    expect(t.widget<TextField>(find.byKey(const Key('setup-name'))).controller!.text, 'Nishchay');
    expect(t.widget<TextField>(find.byKey(const Key('setup-aliases'))).controller!.text, 'Nishu');
    expect(t.widget<FilterChip>(find.widgetWithText(FilterChip, 'ગુજરાતી Gujarati')).selected, isTrue);
    await next(t);
    expect(find.text('Voice saved 15 Oct 2026'), findsOneWidget);
    await next(t);
    expect(find.widgetWithText(VdBadge, 'Downloaded'), findsNWidgets(3));
    expect(words.saved, isEmpty, reason: 'nothing changed, nothing saved');
  });
}
