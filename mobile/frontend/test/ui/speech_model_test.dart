import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_frontend/ui/record/speech_model_banner.dart';

import 'fakes.dart';

void main() {
  late FakeSpeechModel model;

  Future<void> show(WidgetTester t, SpeechModelState state) async {
    model = FakeSpeechModel(state);
    await t.pumpWidget(const SizedBox()); // a fresh scope for each state
    await t.pumpWidget(
      ProviderScope(
        overrides: [speechModelProvider.overrideWith(() => model)],
        child: const MaterialApp(home: Scaffold(body: SpeechModelBanner())),
      ),
    );
    await t.pump();
  }

  testWidgets('missing shows the banner and Download starts it', (t) async {
    await show(t, const SpeechModelState(SpeechModelPhase.missing));
    expect(
      find.text('Turn recordings into text: download the speech model (105 MB, Wi-Fi recommended).'),
      findsOneWidget,
    );
    await t.tap(find.text('Download'));
    expect(model.downloads, 1);
  });

  testWidgets('downloading shows progress in MB', (t) async {
    await show(t, const SpeechModelState(SpeechModelPhase.downloading, done: 40000000, total: 104981681));
    expect(find.text('Downloading the speech model · 40 of 105 MB'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('after the download it says it is preparing', (t) async {
    await show(t, const SpeechModelState(SpeechModelPhase.downloading, done: 104981681, total: 104981681));
    expect(find.text('Preparing the speech model…'), findsOneWidget);
  });

  testWidgets('ready hides the banner', (t) async {
    await show(t, readyModel);
    expect(find.textContaining('speech model'), findsNothing);
  });

  testWidgets('a failure says why and offers Try again', (t) async {
    await show(t, const SpeechModelState(SpeechModelPhase.failed, message: 'network'));
    expect(find.text('The download stopped. Check the connection and try again.'), findsOneWidget);
    await t.tap(find.text('Try again'));
    expect(model.downloads, 1);
    await show(t, const SpeechModelState(SpeechModelPhase.failed, message: 'storage_low'));
    expect(find.text('Not enough free storage for the speech model (300 MB needed).'), findsOneWidget);
    await show(t, const SpeechModelState(SpeechModelPhase.failed, message: 'corrupt'));
    expect(find.text('The download was damaged. Try again.'), findsOneWidget);
  });
}
