import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/audio/wav.dart';
import 'package:mobile_backend/engine/speakers/grouping.dart';
import 'package:mobile_backend/engine/speakers/sherpa_voice_print.dart';
import 'package:mobile_backend/engine/speech/sherpa_speech.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/speech/speech_to_text.dart';

/// Runs the real models on the PC. Needs:
/// - VOICEDESK_TEST_MODELS: a folder laid out as the phone's `models/speech/`
///   (silero_vad.onnx, parakeet-tdt-110m/, parakeet-tdt-0.6b/, indic/);
/// - VOICEDESK_SHERPA_LIB: the folder of sherpa-onnx-c-api.dll (the pub
///   cache's sherpa_onnx_windows);
/// - VOICEDESK_TEST_AUDIO: the owner's recordings (outside the repository:
///   rec2.wav, rec17.wav, gujarati-test.wav, parakeet-0.wav).
void main() {
  final models = Platform.environment['VOICEDESK_TEST_MODELS'];
  final lib = Platform.environment['VOICEDESK_SHERPA_LIB'];
  final audio = Platform.environment['VOICEDESK_TEST_AUDIO'];
  final skip = models == null || lib == null || audio == null
      ? 'set VOICEDESK_TEST_MODELS, VOICEDESK_SHERPA_LIB and VOICEDESK_TEST_AUDIO'
      : false;

  SpeechFiles files({bool accurate = false}) {
    final en = '$models/${accurate ? 'parakeet-tdt-0.6b' : 'parakeet-tdt-110m'}';
    return SpeechFiles(
      vad: File('$models/silero_vad.onnx'),
      english: TransducerFiles(
        encoder: File('$en/encoder.int8.onnx'),
        decoder: File('$en/decoder.int8.onnx'),
        joiner: File('$en/joiner.int8.onnx'),
        tokens: File('$en/tokens.txt'),
      ),
      indicTokens: File('$models/indic/tokens.txt'),
      indic: {Lang.gu: File('$models/indic/gu.int8.onnx'), Lang.hi: File('$models/indic/hi.int8.onnx')},
      speakers: File('$models/speakers/campplus.onnx'),
    );
  }

  final words = File('assets/english-words.txt').readAsStringSync();

  Float32List samplesOf(String name, {double silenceFirst = 0}) {
    final wav = File('$audio/$name').readAsBytesSync();
    final pcm = wav.buffer.asInt16List(kWavHeaderBytes, (wav.length - kWavHeaderBytes) ~/ 2);
    return Float32List.fromList([...List.filled((silenceFirst * 16000).round(), 0.0), for (final s in pcm) s / 32768]);
  }

  /// Runs [samples] through, [pushMs] at a time (the app pushes 10 s); prints the lines and the speed.
  Future<(List<Phrase>, int)> runSamples(String name, Float32List samples, SpeechSetup setup,
      {int startMs = 0, bool accurate = false, int pushMs = 1000}) async {
    final clock = Stopwatch()..start();
    final speech = await SherpaSpeech.start(files(accurate: accurate), setup,
        englishWords: words, startMs: startMs, threads: 4, libraryDir: lib);
    final phrases = <Phrase>[];
    final step = pushMs * 16;
    for (var at = 0; at < samples.length; at += step) {
      phrases.addAll((await speech.push(Float32List.sublistView(samples, at, (at + step).clamp(0, samples.length)))).phrases);
    }
    final last = await speech.finish();
    phrases.addAll(last.phrases);
    await speech.close();
    final seconds = samples.length / 16000;
    // ignore: avoid_print
    print('$name ${setup.key}: ${(clock.elapsedMilliseconds / 1000 / seconds).toStringAsFixed(3)}× real time');
    for (final p in phrases) {
      // ignore: avoid_print
      print('  ${p.startMs}-${p.endMs}: ${p.text}');
    }
    return (phrases, last.settledMs);
  }

  /// A whole recording, run through.
  Future<(List<Phrase>, int)> run(String name, SpeechSetup setup,
          {int startMs = 0, bool accurate = false, int pushMs = 1000}) =>
      runSamples(name, samplesOf(name), setup, startMs: startMs, accurate: accurate, pushMs: pushMs);

  test('transcribes the Parakeet test file, in order, after its start', () async {
    final (phrases, settled) = await run('parakeet-0.wav', SpeechSetup.englishOnly, startMs: 5000);
    expect(phrases, isNotEmpty);
    expect(phrases.every((p) => p.startMs >= 5000 && p.text.isNotEmpty), isTrue);
    final all = [for (final p in phrases) ...p.words];
    for (var i = 1; i < all.length; i++) {
      expect(all[i].startMs, greaterThanOrEqualTo(all[i - 1].startMs));
    }
    expect(settled, 5000 + samplesOf('parakeet-0.wav').length * 1000 ~/ 16000);
  }, skip: skip);

  test('an engine that cannot start reports SpeechEngineFailed', () async {
    final missing = SpeechFiles(vad: File('no/such/silero_vad.onnx'));
    await expectLater(
      SherpaSpeech.start(missing, SpeechSetup.englishOnly,
          englishWords: '', startMs: 0, threads: 1, libraryDir: 'no/such/library'),
      throwsA(isA<SpeechEngineFailed>()),
    );
  });

  test('settled never passes the start of a phrase still being confirmed', () async {
    // A second of quiet first, so the phrase starts after audio already settled.
    final samples = samplesOf('parakeet-0.wav', silenceFirst: 1);
    final speech = await SherpaSpeech.start(files(), SpeechSetup.englishOnly,
        englishWords: words, startMs: 0, threads: 2, libraryDir: lib);
    var settledSoFar = 0;
    for (var at = 0; at < samples.length; at += 1600) {
      final t = await speech.push(Float32List.sublistView(samples, at, (at + 1600).clamp(0, samples.length)));
      for (final p in t.phrases) {
        expect(p.startMs, greaterThanOrEqualTo(settledSoFar), reason: 'a resume at $settledSoFar would skip the start of "${p.text}"');
      }
      settledSoFar = t.settledMs;
    }
    await speech.close();
  }, skip: skip);

  test("recording 17's \"fine\" is heard as fine", () async {
    final (phrases, _) = await run('rec17.wav', SpeechSetup.englishOnly);
    expect(phrases.map((p) => p.text).join(' ').toLowerCase(), contains('fine'));
    expect(phrases.where((p) => p.text.toLowerCase().replaceAll(RegExp('[^a-z]'), '') == 'by'), isEmpty);
  }, skip: skip);

  test('recording 2: good, good and stop it, with confidences', () async {
    final (phrases, _) = await run('rec2.wav', SpeechSetup.englishOnly);
    final text = phrases.map((p) => p.text).join(' ');
    // Padding every phrase turned this into "Dave."; only unsure ones are padded now.
    expect(text, contains('Good, good'));
    // Read a phrase at a time, the transducer writes "Letters stop it…" ("Let's" when it
    // reads the whole recording): a known error for the test set (Task 9).
    expect(text, contains('stop it from the notification bar'));
    expect([for (final p in phrases) ...p.words].every((w) => w.conf != null), isTrue);
  }, skip: skip);

  test('Gujarati with English mixed comes out in both scripts', () async {
    final (phrases, _) = await run('gujarati-test.wav', const SpeechSetup(languages: {Lang.en, Lang.gu}));
    final all = [for (final p in phrases) ...p.words];
    expect(all.where((w) => RegExp(r'[઀-૿]').hasMatch(w.text)), isNotEmpty, reason: 'Gujarati script');
    expect(all.where((w) => RegExp('[A-Za-z]').hasMatch(w.text)), isNotEmpty, reason: 'English words');
  }, skip: skip);

  test('pushing 10 s at a time, as the app does, keeps the start of long phrases', () async {
    final (small, _) = await run('gujarati-test.wav', SpeechSetup.englishOnly);
    final (big, _) = await run('gujarati-test.wav', SpeechSetup.englishOnly, pushMs: 10000);
    String words(List<Phrase> ps) => ps.map((p) => p.text).join(' ');
    expect(words(big), words(small));
    expect([for (final p in big) p.startMs], [for (final p in small) p.startMs]);
  }, skip: skip);

  test('closing an engine frees its models (no memory left behind per job)', () async {
    final samples = samplesOf('rec17.wav');
    Future<void> job() async {
      final speech = await SherpaSpeech.start(files(), const SpeechSetup(languages: {Lang.en, Lang.gu}),
          englishWords: words, startMs: 0, threads: 4, libraryDir: lib);
      await speech.push(Float32List.sublistView(samples, 0, 16000 * 20));
      await speech.finish();
      await speech.close();
    }

    await job();
    final after1 = ProcessInfo.currentRss;
    for (var i = 0; i < 3; i++) {
      await job();
    }
    final growth = (ProcessInfo.currentRss - after1) ~/ (1024 * 1024);
    // ignore: avoid_print
    print('memory growth over 3 more jobs: $growth MB');
    // Each job loads ~330 MB of models; left behind, three jobs would add ~1 GB.
    expect(growth, lessThan(250));
  }, skip: skip);

  test("a phrase's voice prints come back from the engine", () async {
    final (phrases, _) = await run('rec2.wav', const SpeechSetup(languages: {Lang.en}, speakers: true));
    for (final p in phrases.where((p) => p.endMs - p.startMs >= 400)) {
      expect(p.voices, isNotEmpty, reason: p.text);
      expect(p.voices.every((v) => v.print.length == 192), isTrue);
    }
    // Without speaker detection, none.
    final (plain, _) = await run('rec2.wav', SpeechSetup.englishOnly);
    expect(plain.every((p) => p.voices.isEmpty), isTrue);
  }, skip: skip);

  /// Windows' David and Zira taking turns; some gaps are under the VAD's 0.5 s,
  /// so two turns become one phrase (as measured on the PC, Plan 3). Its
  /// samples, and who speaks when (ms).
  (Float32List, List<(int, int, String)>) conversation() {
    const gaps = [0.25, 0.8, 0.3, 0.6, 0.2, 1.0, 0.4, 0.3, 0.9, 0.25, 0.7];
    final clips = Directory('$audio/spk').listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList()
      ..sort();
    final samples = <double>[];
    final truth = <(int, int, String)>[];
    for (final (k, name) in clips.indexed) {
      final from = samples.length ~/ 16;
      samples.addAll(samplesOf('spk/$name'));
      truth.add((from, samples.length ~/ 16, name.contains('David') ? 'David' : 'Zira'));
      if (k < gaps.length) samples.addAll(List.filled((gaps[k] * 16000).round(), 0.0));
    }
    return (Float32List.fromList(samples), truth);
  }

  const withSpeakers = SpeechSetup(languages: {Lang.en}, speakers: true);

  test('two voices in a conversation make two people', () async {
    final (samples, truth) = conversation();
    final (phrases, _) = await runSamples('conversation', samples, withSpeakers);
    final r = groupSpeakers(phrases);
    for (final l in r.lines) {
      // ignore: avoid_print
      print('  ${l.startMs}-${l.endMs} ${l.speaker}: ${l.text}');
    }
    expect(r.groups, hasLength(2));
    // The speech time each line gets right, with the better of the two ways
    // of matching the groups to David and Zira.
    int overlap(Phrase l, (int, int, String) t) => (l.endMs < t.$2 ? l.endMs : t.$2) - (l.startMs > t.$1 ? l.startMs : t.$1);
    var heard = 0;
    final right = [0, 0];
    for (final l in r.lines) {
      for (final t in truth) {
        final o = overlap(l, t);
        if (o <= 0) continue;
        heard += o;
        if ((l.speaker == 'Person 1') == (t.$3 == 'David')) right[0] += o;
        if ((l.speaker == 'Person 1') == (t.$3 == 'Zira')) right[1] += o;
      }
    }
    final share = (right[0] > right[1] ? right[0] : right[1]) / heard;
    // ignore: avoid_print
    print('right: ${(share * 100).toStringAsFixed(1)}% of ${heard / 1000} s');
    expect(share, greaterThanOrEqualTo(0.95));
  }, skip: skip);

  test("your voice trained from one recording is Me in another, and not in someone else's", () async {
    final reading = samplesOf('rec2.wav');
    final (me, heard) = await sherpaVoicePrint(Float32List.sublistView(reading, 0, (25 * 16000).clamp(0, reading.length)),
        vad: '$models/silero_vad.onnx', speakers: '$models/speakers/campplus.onnx', libraryDir: lib);
    // ignore: avoid_print
    print('trained from ${heard / 1000} s of speech');
    expect(me, isNotNull);
    final (mine, _) = await run('rec16.wav', withSpeakers);
    final r = groupSpeakers(mine, me: me);
    for (final l in r.lines) {
      // ignore: avoid_print
      print('  ${l.speaker}: ${l.text}');
    }
    expect(r.lines.every((l) => l.speaker == 'Me'), isTrue);
    final (theirs, _) = await runSamples('conversation', conversation().$1, withSpeakers);
    expect(groupSpeakers(theirs, me: me).lines.where((l) => l.speaker == 'Me'), isEmpty);
  }, skip: skip);
}
