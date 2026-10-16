import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'voice_print.dart';
import 'voice_training.dart';

const _rate = 16000;

/// Your voice print from a reading: the speech in it (the VAD, as for
/// recordings), cut in [kTrainingWindowMs] windows every [kTrainingStepMs],
/// their prints averaged. Runs away from the screens' thread.
/// [libraryDir]: where `sherpa-onnx-c-api` is (null on the phone).
Future<(Float32List?, int)> sherpaVoicePrint(Float32List samples,
        {required String vad, required String speakers, String? libraryDir}) =>
    Isolate.run(() => _print(samples, vad, speakers, libraryDir));

(Float32List?, int) _print(Float32List samples, String vadPath, String speakersPath, String? libraryDir) {
  if (Platform.isWindows && libraryDir != null) DynamicLibrary.open('$libraryDir/onnxruntime.dll');
  so.initBindings(libraryDir);
  final vad = so.VoiceActivityDetector(
    config: so.VadModelConfig(
      sileroVad: so.SileroVadModelConfig(
        model: vadPath,
        threshold: 0.5,
        minSilenceDuration: 0.5,
        minSpeechDuration: 0.25,
        maxSpeechDuration: 20,
        windowSize: 512,
      ),
      sampleRate: _rate,
      numThreads: 1,
      debug: false,
    ),
    bufferSizeInSeconds: 30,
  );
  final speech = <double>[];
  try {
    void take() {
      while (!vad.isEmpty()) {
        speech.addAll(vad.front().samples);
        vad.pop();
      }
    }

    for (var at = 0; at + 512 <= samples.length; at += 512) {
      vad.acceptWaveform(Float32List.sublistView(samples, at, at + 512));
      take();
    }
    vad.flush();
    take();
  } finally {
    vad.free();
  }
  final heardMs = speech.length * 1000 ~/ _rate;
  if (heardMs < kMinTrainingSpeechMs) return (null, heardMs);

  final all = Float32List.fromList(speech);
  final extractor = so.SpeakerEmbeddingExtractor(
    config: so.SpeakerEmbeddingExtractorConfig(model: speakersPath, numThreads: 2, debug: false),
  );
  final prints = <(Float32List, int)>[];
  try {
    for (final (a, b) in trainingWindows(heardMs)) {
      final stream = extractor.createStream();
      try {
        stream.acceptWaveform(samples: Float32List.sublistView(all, a * 16, b * 16), sampleRate: _rate);
        stream.inputFinished();
        if (extractor.isReady(stream)) prints.add((normalised(extractor.compute(stream)), 1));
      } finally {
        stream.free();
      }
    }
  } finally {
    extractor.free();
  }
  return (prints.isEmpty ? null : meanPrint(prints), heardMs);
}
