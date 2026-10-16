import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/transcript.dart';
import '../models/catalogue.dart';
import '../models/speech_model.dart';
import 'mixed.dart';
import 'sherpa_speech.dart';
import 'speech_setup.dart';

/// The speech engine didn't start or stopped working (a broken model file, a crash).
class SpeechEngineFailed implements Exception {
  const SpeechEngineFailed(this.reason);
  final String reason;

  @override
  String toString() => 'SpeechEngineFailed($reason)';
}

/// What came out of some audio: the phrases that ended in it, and the time up
/// to which nothing more can come (ms from the recording's start).
class Transcribed {
  const Transcribed(this.phrases, this.settledMs);
  final List<Phrase> phrases;
  final int settledMs;
}

/// Cuts audio at pauses and turns each phrase into text. Audio is pushed in
/// order, 16 kHz mono samples (-1..1); times are ms from the recording's start.
abstract class SpeechToText {
  /// Audio that follows what was pushed before.
  Future<Transcribed> push(Float32List samples);

  /// No more audio: closes the phrase still going.
  Future<Transcribed> finish();
  Future<void> close();
}

/// Starts speech to text for a recording made with [setup], at [startMs] of
/// it, on [threads] threads.
typedef SpeechToTextFactory = Future<SpeechToText> Function(
    {required SpeechSetup setup, required int startMs, required int threads});

final speechToTextFactoryProvider = Provider<SpeechToTextFactory>((ref) {
  final store = ref.watch(modelStoreProvider);
  return ({required SpeechSetup setup, required int startMs, required int threads}) async {
    final englishModel = setup.english == EnglishModel.faster ? ModelId.englishFaster : ModelId.englishAccurate;
    File en(String name) => store.file(englishModel, name);
    final files = SpeechFiles(
      vad: store.file(ModelId.vad, 'silero_vad.onnx'),
      english: setup.hasEnglish
          ? TransducerFiles(
              encoder: en('encoder.int8.onnx'), decoder: en('decoder.int8.onnx'), joiner: en('joiner.int8.onnx'), tokens: en('tokens.txt'))
          : null,
      indicTokens: setup.indian.isEmpty ? null : store.file(ModelId.indicTokens, 'tokens.txt'),
      indic: {
        if (setup.languages.contains(Lang.hi)) Lang.hi: store.file(ModelId.hindi, 'hi.int8.onnx'),
        if (setup.languages.contains(Lang.gu)) Lang.gu: store.file(ModelId.gujarati, 'gu.int8.onnx'),
      },
      speakers: setup.speakers ? store.file(ModelId.speakers, 'campplus.onnx') : null,
    );
    return SherpaSpeech.start(files, setup,
        englishWords: await ref.read(englishWordsTextProvider.future), startMs: startMs, threads: threads);
  };
});
