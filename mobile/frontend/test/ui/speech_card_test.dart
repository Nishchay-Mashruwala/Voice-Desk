import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_frontend/ui/settings/speech_card.dart';
import 'package:mobile_frontend/ui/widgets/badge.dart';

import 'fakes.dart';

void main() {
  late FakeModels models;
  late FakeSpeechSettings speech;

  Future<void> show(
    WidgetTester t, {
    SpeechSettings settings = const SpeechSettings(),
    Map<ModelId, ModelState> state = const {},
  }) async {
    models = FakeModels(state);
    speech = FakeSpeechSettings(settings);
    await t.pumpWidget(const SizedBox()); // a fresh scope each time
    await t.pumpWidget(ProviderScope(
      overrides: quietBackend(models: models, speech: speech),
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SpeechCard()))),
    ));
    await t.pumpAndSettle();
  }

  const missing = ModelState(ModelPhase.missing);

  testWidgets('ticking Gujarati asks, then downloads', (t) async {
    await show(t, state: {ModelId.gujarati: missing, ModelId.indicTokens: missing});
    expect(find.text('Languages you speak'), findsOneWidget);
    await t.tap(find.text('ગુજરાતી Gujarati'));
    await t.pumpAndSettle();
    expect(find.text('Gujarati model · 198 MB'), findsOneWidget);
    expect(find.text('Wi-Fi recommended.'), findsOneWidget);
    await t.tap(find.text('Download'));
    await t.pumpAndSettle();
    expect(speech.sets, ['languages:en,gu']);
    expect(models.downloads, [ModelId.gujarati]);
  });

  testWidgets('Cancel leaves it unticked', (t) async {
    await show(t, state: {ModelId.hindi: missing});
    await t.tap(find.text('हिन्दी Hindi'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(speech.sets, isEmpty);
    expect(models.downloads, isEmpty);
  });

  testWidgets('a language already downloaded is ticked without asking', (t) async {
    await show(t);
    await t.tap(find.text('ગુજરાતી Gujarati'));
    await t.pumpAndSettle();
    expect(find.text('Wi-Fi recommended.'), findsNothing);
    expect(speech.sets, ['languages:en,gu']);
  });

  testWidgets("English can't be unticked when it's the only language", (t) async {
    await show(t);
    await t.tap(find.text('English'));
    await t.pumpAndSettle();
    expect(speech.sets, isEmpty);
    // With Gujarati on too, it can.
    await show(t, settings: const SpeechSettings(languages: {Lang.en, Lang.gu}));
    await t.tap(find.text('English'));
    await t.pumpAndSettle();
    expect(speech.sets, ['languages:gu']);
  });

  testWidgets('the Hindi/Gujarati question shows only with both ticked', (t) async {
    await show(t, settings: const SpeechSettings(languages: {Lang.en, Lang.gu}));
    expect(find.text('Hindi or Gujarati — which do you speak more?'), findsNothing);
    await show(t, settings: const SpeechSettings(languages: {Lang.en, Lang.hi, Lang.gu}));
    expect(find.text('Hindi or Gujarati — which do you speak more?'), findsOneWidget);
    await t.tap(find.text('Hindi'));
    await t.pumpAndSettle();
    expect(speech.sets, ['prefer:hi']);
  });

  testWidgets('a language downloading shows its progress, a failed one Try again', (t) async {
    await show(t, settings: const SpeechSettings(languages: {Lang.en, Lang.hi, Lang.gu}), state: {
      ModelId.gujarati: const ModelState(ModelPhase.downloading, done: 89000000, total: 197663066),
      ModelId.hindi: const ModelState(ModelPhase.failed, message: 'network'),
    });
    expect(find.text('Downloading the Gujarati model · 45%'), findsOneWidget);
    expect(find.text("Couldn't download the Hindi model."), findsOneWidget);
    await t.tap(find.text('Try again'));
    expect(models.downloads, [ModelId.hindi]);
  });

  testWidgets('accuracy cards show size or Downloaded, and the time', (t) async {
    await show(t, state: {ModelId.englishAccurate: missing});
    expect(find.text('Accuracy (speech model)'), findsOneWidget);
    expect(find.text('Auto — picks for this phone'), findsOneWidget);
    expect(find.text('Now: Faster'), findsOneWidget);
    // The M31 speed test: 0.17 × 30 min ≈ 5 min; the bigger model ≈ 0.9 × 30 = 27 min.
    expect(find.text('about 5 min for a 30-min recording'), findsOneWidget);
    expect(find.text('Downloads 482 MB · about 27 min for a 30-min recording'), findsOneWidget);
  });

  testWidgets('More accurate asks before downloading', (t) async {
    await show(t, state: {ModelId.englishAccurate: missing});
    await t.tap(find.text('More accurate'));
    await t.pumpAndSettle();
    expect(find.text('English speech model (More accurate) · 482 MB'), findsOneWidget);
    await t.tap(find.text('Download'));
    await t.pumpAndSettle();
    expect(speech.sets, ['accuracy:accurate']);
    expect(models.downloads, [ModelId.englishAccurate]);
  });

  testWidgets('choosing a downloaded one just sets it', (t) async {
    await show(t, settings: const SpeechSettings(accuracy: Accuracy.accurate));
    await t.tap(find.text('Faster'));
    await t.pumpAndSettle();
    expect(speech.sets, ['accuracy:faster']);
    expect(models.downloads, isEmpty);
  });

  testWidgets('a downloaded accuracy model shows the green tag', (t) async {
    await show(t, state: {ModelId.englishAccurate: missing});
    final tag = t.widget<VdBadge>(find.widgetWithText(VdBadge, 'Downloaded'));
    expect(tag.kind, BadgeKind.ok);
    expect(find.widgetWithText(VdBadge, 'Downloaded'), findsOneWidget); // only Faster is on the phone
  });

  testWidgets('the speaker detection switch saves it', (t) async {
    await show(t);
    expect(find.text('Speaker detection'), findsOneWidget);
    expect(find.text('Who said what, after each recording'), findsOneWidget);
    await t.tap(find.text('Speaker detection'));
    await t.pumpAndSettle();
    expect(speech.sets, ['speakers:false']);
  });
}
