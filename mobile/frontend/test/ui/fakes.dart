import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/speech/your_words.dart';

/// The speech model in a given state; counts what the screen asks of it.
class FakeSpeechModel extends SpeechModel {
  FakeSpeechModel(this.initial);
  final SpeechModelState initial;
  int downloads = 0;
  int deletes = 0;

  @override
  SpeechModelState build() => initial;

  @override
  Future<void> download() async => downloads++;

  @override
  Future<void> delete() async => deletes++;
}

class FakeOnlyWhileCharging extends OnlyWhileCharging {
  FakeOnlyWhileCharging([this.initial = false]);
  final bool initial;
  final sets = <bool>[];

  @override
  Future<bool> build() async => initial;

  @override
  Future<void> set(bool on) async {
    sets.add(on);
    state = AsyncData(on);
  }
}

class FakeYourWords extends YourWordsNotifier {
  FakeYourWords([this.initial = const YourWords()]);
  final YourWords initial;
  final saved = <String>[];

  @override
  Future<YourWords> build() async => initial;

  @override
  Future<void> set({String? name, String? vocabulary, String? leaveOut}) async {
    if (name != null) saved.add('name:$name');
    if (vocabulary != null) saved.add('vocabulary:$vocabulary');
    if (leaveOut != null) saved.add('leaveOut:$leaveOut');
  }
}

/// Processing doing nothing (the screens' tests don't run the real one).
class IdleProcessor extends Processor {
  IdleProcessor([this.initial = const ProcessingState()]);
  final ProcessingState initial;
  final retried = <int>[];

  @override
  ProcessingState build() => initial;

  @override
  void kick() {}

  @override
  Future<void> retry(int id) async => retried.add(id);
}

const readyModel = SpeechModelState(SpeechModelPhase.ready);

/// Overrides the backend parts the screens read but these tests don't exercise.
List<Override> quietBackend({
  SpeechModelState model = readyModel,
  ProcessingState processing = const ProcessingState(),
  FakeYourWords? yourWords,
}) => [
  speechModelProvider.overrideWith(() => FakeSpeechModel(model)),
  onlyWhileChargingProvider.overrideWith(FakeOnlyWhileCharging.new),
  processorProvider.overrideWith(() => IdleProcessor(processing)),
  yourWordsProvider.overrideWith(() => yourWords ?? FakeYourWords()),
];
