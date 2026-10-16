import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/speakers/voice_training.dart';
import 'package:mobile_frontend/ui/settings/voice_training_screen.dart';

import 'fakes.dart';

/// Training as the test sets it; records what the screen asks for.
class FakeTraining extends VoiceTraining {
  FakeTraining(this.initial);
  final TrainingState initial;
  final calls = <String>[];

  @override
  TrainingState build() => initial;

  void set(TrainingState s) => state = s;

  @override
  Future<void> start() async => calls.add('start');
  @override
  Future<void> done() async => calls.add('done');
  @override
  Future<void> cancel() async => calls.add('cancel');
  @override
  Future<void> forget() async => calls.add('forget');
}

void main() {
  late FakeTraining training;

  Future<void> show(
    WidgetTester t, {
    TrainingState state = const TrainingState(),
    (Float32List?, DateTime?) voice = (null, null),
    FakeModels? models,
  }) async {
    training = FakeTraining(state);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...quietBackend(models: models, myVoice: voice),
          voiceTrainingProvider.overrideWith(() => training),
        ],
        child: const MaterialApp(home: VoiceTrainingScreen()),
      ),
    );
    await t.pump();
  }

  testWidgets('not trained yet: Train my voice starts the reading', (t) async {
    await show(t);
    expect(find.text('Not trained yet'), findsOneWidget);
    await t.tap(find.text('Train my voice'));
    await t.pump();
    expect(training.calls, ['start']);
  });

  testWidgets('Done is off until 8 s, then finishes the reading', (t) async {
    await show(t, state: const TrainingState(phase: TrainingPhase.recording, elapsed: Duration(seconds: 5)));
    expect(find.text('Read this aloud in your normal voice:'), findsOneWidget);
    expect(find.textContaining('The quick brown fox jumps over the lazy dog.'), findsOneWidget);
    // The button itself says to keep reading, and does nothing, until 8 s.
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Keep reading…')).onPressed, isNull);
    expect(find.text('Done'), findsNothing);
    training.set(const TrainingState(phase: TrainingPhase.recording, elapsed: Duration(seconds: 8)));
    await t.pump();
    expect(find.text('Keep reading…'), findsNothing);
    await t.tap(find.text('Done'));
    await t.pump();
    expect(training.calls, ['done']);
  });

  testWidgets('while the voice is worked out, Back waits', (t) async {
    training = FakeTraining(const TrainingState(phase: TrainingPhase.working));
    await t.pumpWidget(
      ProviderScope(
        overrides: [...quietBackend(), voiceTrainingProvider.overrideWith(() => training)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VoiceTrainingScreen())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.binding.handlePopRoute();
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(VoiceTrainingScreen), findsOneWidget);
  });

  testWidgets('too little speech says so', (t) async {
    await show(t, state: const TrainingState(phase: TrainingPhase.failed, message: 'too_little', heardMs: 4200));
    expect(find.text('Only 4s of speech was heard. Please read the text aloud for about 15 seconds.'), findsOneWidget);
    expect(find.text('Train my voice'), findsOneWidget);
  });

  testWidgets('a saved voice shows its date, with Re-train', (t) async {
    await show(t, voice: (Float32List(192), DateTime(2026, 10, 15)));
    expect(find.text('Voice saved 15 Oct 2026'), findsOneWidget);
    expect(find.text('Re-train'), findsOneWidget);
  });

  testWidgets('Forget asks, then deletes', (t) async {
    await show(t, voice: (Float32List(192), DateTime(2026, 10, 15)));
    await t.tap(find.text('Forget my voice'));
    await t.pumpAndSettle();
    expect(find.text('Forget your voice?'), findsOneWidget);
    expect(
      find.text('Voice Desk deletes what it learned about your voice. Until you train it again, your lines show as Person 1, 2…'),
      findsOneWidget,
    );
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(training.calls, isEmpty);
    await t.tap(find.text('Forget my voice'));
    await t.pumpAndSettle();
    await t.tap(find.text('Forget'));
    await t.pumpAndSettle();
    expect(training.calls, ['forget']);
  });

  testWidgets('without the voice model, training downloads it first', (t) async {
    final models = FakeModels({ModelId.speakers: const ModelState(ModelPhase.missing)});
    await show(t, models: models);
    expect(find.text('Downloads 28 MB first.'), findsOneWidget);
    await t.tap(find.text('Train my voice'));
    await t.pump();
    expect(models.downloads, [ModelId.speakers]);
  });
}
