import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/audio/wav.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/speech/sherpa_speech.dart';
import 'package:mobile_backend/engine/speech/speech_to_text.dart';

/// Runs the real models on the PC. Needs VOICEDESK_TEST_MODELS (a folder with
/// silero_vad.onnx and the Parakeet folder) and VOICEDESK_SHERPA_LIB (the
/// folder of sherpa-onnx-c-api.dll from the pub cache's sherpa_onnx_windows).
void main() {
  final models = Platform.environment['VOICEDESK_TEST_MODELS'];
  final lib = Platform.environment['VOICEDESK_SHERPA_LIB'];

  test('transcribes the Parakeet test file', () async {
    final parakeet = '$models/sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8';
    final files = SpeechModelFiles(
      vad: File('$models/silero_vad.onnx'),
      model: File('$parakeet/model.int8.onnx'),
      tokens: File('$parakeet/tokens.txt'),
    );
    final wav = File('$parakeet/test_wavs/0.wav').readAsBytesSync();
    final pcm = wav.buffer.asInt16List(kWavHeaderBytes, (wav.length - kWavHeaderBytes) ~/ 2);
    final samples = Float32List.fromList([for (final s in pcm) s / 32768]);

    final speech = await SherpaSpeech.start(files, startMs: 5000, threads: 2, libraryDir: lib);
    final phrases = <Phrase>[];
    for (var at = 0; at < samples.length; at += 16000) {
      phrases.addAll((await speech.push(Float32List.sublistView(samples, at, (at + 16000).clamp(0, samples.length)))).phrases);
    }
    final last = await speech.finish();
    phrases.addAll(last.phrases);
    await speech.close();

    for (final p in phrases) {
      // ignore: avoid_print
      print('PHRASE ${p.startMs}-${p.endMs}: ${p.text}');
    }
    expect(phrases, isNotEmpty);
    expect(phrases.every((p) => p.startMs >= 5000 && p.text.isNotEmpty), isTrue);
    final words = [for (final p in phrases) ...p.words];
    for (var i = 1; i < words.length; i++) {
      expect(words[i].startMs, greaterThanOrEqualTo(words[i - 1].startMs));
    }
    expect(last.settledMs, 5000 + samples.length * 1000 ~/ 16000);
  }, skip: models == null || lib == null ? 'set VOICEDESK_TEST_MODELS and VOICEDESK_SHERPA_LIB' : false);

  test('an engine that cannot start reports SpeechEngineFailed', () async {
    final missing = SpeechModelFiles(
      vad: File('no/such/silero_vad.onnx'),
      model: File('no/such/model.int8.onnx'),
      tokens: File('no/such/tokens.txt'),
    );
    await expectLater(
      SherpaSpeech.start(missing, startMs: 0, threads: 1, libraryDir: 'no/such/library'),
      throwsA(isA<SpeechEngineFailed>()),
    );
  });

  test('settled never passes the start of a phrase still being confirmed', () async {
    final parakeet = '$models/sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8';
    final files = SpeechModelFiles(
      vad: File('$models/silero_vad.onnx'),
      model: File('$parakeet/model.int8.onnx'),
      tokens: File('$parakeet/tokens.txt'),
    );
    final wav = File('$parakeet/test_wavs/0.wav').readAsBytesSync();
    final pcm = wav.buffer.asInt16List(kWavHeaderBytes, (wav.length - kWavHeaderBytes) ~/ 2);
    // A second of quiet first, so the phrase starts after audio already settled.
    final samples = Float32List.fromList([...List.filled(16000, 0.0), for (final s in pcm) s / 32768]);
    final speech = await SherpaSpeech.start(files, startMs: 0, threads: 2, libraryDir: lib);
    var settledSoFar = 0;
    for (var at = 0; at < samples.length; at += 1600) {
      final t = await speech.push(Float32List.sublistView(samples, at, (at + 1600).clamp(0, samples.length)));
      for (final p in t.phrases) {
        expect(p.startMs, greaterThanOrEqualTo(settledSoFar), reason: 'a resume at $settledSoFar would skip the start of "${p.text}"');
      }
      settledSoFar = t.settledMs;
    }
    await speech.close();
  }, skip: models == null || lib == null ? 'set VOICEDESK_TEST_MODELS and VOICEDESK_SHERPA_LIB' : false);
}
