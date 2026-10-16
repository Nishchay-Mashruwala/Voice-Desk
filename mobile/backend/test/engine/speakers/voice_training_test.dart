import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/engine/audio/audio_source.dart';
import 'package:mobile_backend/engine/audio/recorder_controller.dart';
import 'package:mobile_backend/engine/audio/wav.dart';
import 'package:mobile_backend/engine/speakers/voice_training.dart';

/// A microphone the test speaks into, a second at a time.
class FakeMic implements AudioSource {
  bool allowed = true;
  bool running = false;
  StreamController<Uint8List>? _pcm;

  /// [seconds] of audio, in quarter-second chunks.
  Future<void> say(double seconds) async {
    for (var i = 0; i < (seconds * 4).round(); i++) {
      _pcm?.add(Uint8List(kBytesPerSecond ~/ 4));
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<bool> hasPermission() async => allowed;
  @override
  Future<Stream<Uint8List>> start() async {
    running = true;
    _pcm = StreamController<Uint8List>();
    return _pcm!.stream;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {
    running = false;
    await _pcm?.close();
  }

  @override
  Stream<double> get level => const Stream.empty();
}

class IdleRecorder extends RecorderController {
  IdleRecorder([this.initial = const RecorderState()]);
  final RecorderState initial;
  @override
  RecorderState build() => initial;
}

final myPrint = Float32List(8)..[3] = 1;

void main() {
  late AppDatabase db;
  late FakeMic mic;
  late List<int> printed; // samples given to the printer
  late (Float32List?, int) printerSays;

  ProviderContainer make({RecorderState recorder = const RecorderState()}) => ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        audioSourceProvider.overrideWithValue(mic),
        recorderProvider.overrideWith(() => IdleRecorder(recorder)),
        voicePrinterProvider.overrideWithValue((samples) async {
          printed.add(samples.length);
          return printerSays;
        }),
      ]);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mic = FakeMic();
    printed = [];
    printerSays = (myPrint, 15000);
  });
  tearDown(() => db.close());

  test('Done is off until 8 s, and recording stops itself at 25 s', () async {
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(voiceTrainingProvider, (_, _) {});
    addTearDown(sub.close);
    final training = c.read(voiceTrainingProvider.notifier);
    await training.start();
    expect(c.read(voiceTrainingProvider).phase, TrainingPhase.recording);
    await mic.say(7.75);
    expect(c.read(voiceTrainingProvider).canFinish, isFalse);
    await mic.say(0.25);
    expect(c.read(voiceTrainingProvider).canFinish, isTrue);
    await mic.say(17);
    await pumpUntil(() => c.read(voiceTrainingProvider).phase == TrainingPhase.saved);
    expect(mic.running, isFalse);
    expect(printed, [25 * 16000]);
  });

  test('too little speech says so', () async {
    printerSays = (null, 4200);
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(voiceTrainingProvider, (_, _) {});
    addTearDown(sub.close);
    final training = c.read(voiceTrainingProvider.notifier);
    await training.start();
    await mic.say(10);
    await training.done();
    final s = c.read(voiceTrainingProvider);
    expect((s.phase, s.message, s.heardMs), (TrainingPhase.failed, 'too_little', 4200));
    expect(await c.read(myVoiceProvider.future), (null, null));
  });

  test('a voice is saved with its date, and forgetting deletes it', () async {
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(voiceTrainingProvider, (_, _) {});
    addTearDown(sub.close);
    final training = c.read(voiceTrainingProvider.notifier);
    await training.start();
    await mic.say(12);
    await training.done();
    expect(c.read(voiceTrainingProvider).phase, TrainingPhase.saved);
    final (voice, at) = await c.read(myVoiceProvider.future);
    expect(voice, myPrint);
    expect(DateTime.now().difference(at!).inMinutes, 0);

    await training.forget();
    expect(await c.read(myVoiceProvider.future), (null, null));
  });

  test('Cancel stops the microphone and keeps nothing', () async {
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(voiceTrainingProvider, (_, _) {});
    addTearDown(sub.close);
    final training = c.read(voiceTrainingProvider.notifier);
    await training.start();
    await mic.say(9);
    await training.cancel();
    expect((c.read(voiceTrainingProvider).phase, mic.running), (TrainingPhase.idle, false));
    expect(printed, isEmpty);
  });

  test('closing the screen mid-reading turns the microphone off', () async {
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(voiceTrainingProvider, (_, _) {});
    await c.read(voiceTrainingProvider.notifier).start();
    await mic.say(5);
    expect(mic.running, isTrue);
    sub.close(); // the screen goes: the provider is disposed
    await pumpUntil(() => !mic.running);
    expect(mic.running, isFalse);
    expect(printed, isEmpty);
  });

  test("while a recording runs, training doesn't start", () async {
    final c = make(recorder: const RecorderState(phase: RecorderPhase.recording));
    addTearDown(c.dispose);
    final sub = c.listen(voiceTrainingProvider, (_, _) {});
    addTearDown(sub.close);
    await c.read(voiceTrainingProvider.notifier).start();
    expect((c.read(voiceTrainingProvider).message, mic.running), ('busy', false));
  });

  test('no microphone permission says so', () async {
    mic.allowed = false;
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(voiceTrainingProvider, (_, _) {});
    addTearDown(sub.close);
    await c.read(voiceTrainingProvider.notifier).start();
    expect(c.read(voiceTrainingProvider).message, 'microphone_denied');
  });

  test('the print is made from 3 s windows every 1.5 s of the speech', () {
    expect(trainingWindows(6000), [(0, 3000), (1500, 4500), (3000, 6000)]);
    expect(trainingWindows(7000), [(0, 3000), (1500, 4500), (3000, 6000)]);
    expect(trainingWindows(2000), isEmpty);
  });
}

Future<void> pumpUntil(bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
