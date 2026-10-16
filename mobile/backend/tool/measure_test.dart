// Measures speech recognition on the owner's test set (a PC tool, not part
// of the app or of `flutter test`'s normal run):
//
//   flutter test tool/measure_test.dart
//
// with VOICEDESK_TEST_MODELS (a folder laid out as the phone's models/speech/),
// VOICEDESK_SHERPA_LIB (sherpa-onnx-c-api.dll's folder) and VOICEDESK_TEST_AUDIO
// (name.wav with name.txt holding the right words, outside the repository).
// VOICEDESK_SETUP picks the languages (default `en`; e.g. `en,gu`), and
// VOICEDESK_ACCURATE=1 the bigger English model.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/audio/wav.dart';
import 'package:mobile_backend/engine/speech/sherpa_speech.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';

import 'word_errors.dart';

void main() {
  final env = Platform.environment;
  final models = env['VOICEDESK_TEST_MODELS'];
  final lib = env['VOICEDESK_SHERPA_LIB'];
  final audio = env['VOICEDESK_TEST_AUDIO'];
  final accurate = env['VOICEDESK_ACCURATE'] == '1';
  final setup = SpeechSetup.parse(env['VOICEDESK_SETUP'] ?? 'en', 'gu', accurate ? 'accurate' : 'faster');

  test('words wrong on the test set', () async {
    final en = '$models/${accurate ? 'parakeet-tdt-0.6b' : 'parakeet-tdt-110m'}';
    final files = SpeechFiles(
      vad: File('$models/silero_vad.onnx'),
      english: TransducerFiles(
        encoder: File('$en/encoder.int8.onnx'),
        decoder: File('$en/decoder.int8.onnx'),
        joiner: File('$en/joiner.int8.onnx'),
        tokens: File('$en/tokens.txt'),
      ),
      indicTokens: File('$models/indic/tokens.txt'),
      indic: {Lang.gu: File('$models/indic/gu.int8.onnx'), Lang.hi: File('$models/indic/hi.int8.onnx')},
    );
    final words = File('assets/english-words.txt').readAsStringSync();
    var wrong = 0, total = 0;
    final clips = Directory(audio!).listSync().whereType<File>().where((f) => f.path.endsWith('.wav')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final wav in clips) {
      final ref = File(wav.path.replaceFirst(RegExp(r'\.wav$'), '.txt'));
      if (!ref.existsSync()) continue;
      final bytes = wav.readAsBytesSync();
      final pcm = bytes.buffer.asInt16List(kWavHeaderBytes, (bytes.length - kWavHeaderBytes) ~/ 2);
      final samples = Float32List.fromList([for (final s in pcm) s / 32768]);
      final clock = Stopwatch()..start();
      final speech =
          await SherpaSpeech.start(files, setup, englishWords: words, startMs: 0, threads: 4, libraryDir: lib);
      final lines = <Phrase>[];
      // 10 s at a time, as the app pushes it.
      for (var at = 0; at < samples.length; at += 160000) {
        lines.addAll((await speech.push(Float32List.sublistView(samples, at, (at + 160000).clamp(0, samples.length)))).phrases);
      }
      lines.addAll((await speech.finish()).phrases);
      await speech.close();
      final heard = lines.map((l) => l.text).join(' ');
      final right = ref.readAsStringSync();
      final n = wordErrors(right, heard);
      wrong += n;
      total += wordsOf(right).length;
      final rtf = clock.elapsedMilliseconds / 1000 / (samples.length / 16000);
      // ignore: avoid_print
      print('${wav.uri.pathSegments.last}: $n of ${wordsOf(right).length} words wrong · ${rtf.toStringAsFixed(3)}× · $heard');
    }
    // ignore: avoid_print
    print('TOTAL ${setup.key}: $wrong of $total words wrong');
  }, skip: models == null || lib == null || audio == null ? 'set VOICEDESK_TEST_MODELS, _SHERPA_LIB, _TEST_AUDIO' : false);
}
