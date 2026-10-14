import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/transcript.dart';
import '../models/speech_model.dart';
import 'sherpa_speech.dart';

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

/// Starts speech to text at [startMs] of a recording, on [threads] threads.
typedef SpeechToTextFactory = Future<SpeechToText> Function({required int startMs, required int threads});

final speechToTextFactoryProvider = Provider<SpeechToTextFactory>((ref) {
  final store = ref.watch(speechModelStoreProvider);
  return ({required int startMs, required int threads}) => SherpaSpeech.start(store.files, startMs: startMs, threads: threads);
});
