import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_frontend/ui/record/speech_model_banner.dart';

import 'fakes.dart';

void main() {
  late FakeModels models;

  Future<void> show(WidgetTester t, SpeechModelsState state) async {
    models = FakeModels();
    await t.pumpWidget(const SizedBox()); // a fresh scope for each state
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          modelsProvider.overrideWith(() => models),
          neededModelsProvider.overrideWithValue(state),
        ],
        child: const MaterialApp(home: Scaffold(body: SpeechModelBanner())),
      ),
    );
    await t.pump();
  }

  testWidgets('the banner counts what the settings need, and Download gets it all', (t) async {
    await show(t, const SpeechModelsState(ModelPhase.missing, bytesToDownload: 305698161));
    expect(
      find.text('Turn recordings into text: download the speech models (306 MB, Wi-Fi recommended).'),
      findsOneWidget,
    );
    await t.tap(find.text('Download'));
    expect(models.neededDownloads, 1);
  });

  testWidgets('only the task model missing: the banner says so', (t) async {
    await show(t, const SpeechModelsState(ModelPhase.missing, bytesToDownload: 1107409472, missing: Missing.tasks));
    expect(find.text('Find your tasks: download the task model (1107 MB, Wi-Fi recommended).'), findsOneWidget);
    await show(t, const SpeechModelsState(ModelPhase.downloading, done: 40000000, total: 1107409472, missing: Missing.tasks));
    expect(find.text('Downloading the task model… 40 of 1107 MB'), findsOneWidget);
    await show(t, const SpeechModelsState(ModelPhase.failed, freeNeeded: 1207409472, message: 'storage_low', missing: Missing.tasks));
    expect(find.text('Not enough free storage for the task model (1207 MB needed).'), findsOneWidget);
  });

  testWidgets('the speech and task models together', (t) async {
    await show(t, const SpeechModelsState(ModelPhase.missing, bytesToDownload: 1413107633, missing: Missing.both));
    expect(find.text('Turn recordings into text and find your tasks: download the models (1413 MB, Wi-Fi recommended).'),
        findsOneWidget);
    await show(t, const SpeechModelsState(ModelPhase.downloading, done: 40000000, total: 1413107633, missing: Missing.both));
    expect(find.text('Downloading the models · 40 of 1413 MB'), findsOneWidget);
    await show(t, const SpeechModelsState(ModelPhase.downloading, done: 1413107633, total: 1413107633, missing: Missing.both));
    expect(find.text('Preparing the models…'), findsOneWidget);
  });

  testWidgets('downloading shows progress in MB', (t) async {
    await show(t, const SpeechModelsState(ModelPhase.downloading, done: 40000000, total: 108035095));
    expect(find.text('Downloading the speech models · 40 of 108 MB'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('after the download it says it is preparing', (t) async {
    await show(t, const SpeechModelsState(ModelPhase.downloading, done: 108035095, total: 108035095));
    expect(find.text('Preparing the speech models…'), findsOneWidget);
  });

  testWidgets('ready hides the banner', (t) async {
    await show(t, readyModels);
    expect(find.textContaining('speech models'), findsNothing);
  });

  testWidgets('a failure says why and offers Try again', (t) async {
    await show(t, const SpeechModelsState(ModelPhase.failed, message: 'network'));
    expect(find.text('The download stopped. Check the connection and try again.'), findsOneWidget);
    await t.tap(find.text('Try again'));
    expect(models.neededDownloads, 1);
    await show(t, const SpeechModelsState(ModelPhase.failed, message: 'storage_low', freeNeeded: 324105285));
    expect(find.text('Not enough free storage for the speech models (324 MB needed).'), findsOneWidget);
    await show(t, const SpeechModelsState(ModelPhase.failed, message: 'corrupt'));
    expect(find.text('The download was damaged. Try again.'), findsOneWidget);
  });
}
