import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
// The package's own result reader drops the tokens' scores; its native
// result JSON has them (`ys_log_probs`).
// ignore: implementation_imports
import 'package:sherpa_onnx/src/sherpa_onnx_bindings.dart' show SherpaOnnxBindings;

import '../../data/transcript.dart';
import 'mixed.dart';
import '../speakers/voice_print.dart';
import 'phrase_writer.dart';
import 'speech_setup.dart';
import 'speech_to_text.dart';
import 'words.dart';

const _rate = 16000;
const _window = 512;

/// Silero needs this much speech (2 windows + its 0.25 s minimum) before it
/// says speech started — and then dates the start back by as much.
const _confirmSamples = 2 * _window + _rate ~/ 4;

/// A phrase the English reader was unsure of is read again from this much
/// earlier (300 ms): a late start clipped a soft first sound ("fine" heard as
/// "by"). Not always: on a sure phrase the extra audio made things worse
/// ("Good, good" → "Dave", the owner's recording 2).
const kPadSamples = 4800;

/// Below this mean word confidence (or hearing nothing) a phrase is read again.
/// Measured on the owner's recordings (Plan 2b Task 9): 0.9 re-read a phrase
/// that was right and lost "then we"; 0.8 and lower gave the fewest wrong words.
const kSureConf = int.fromEnvironment('VD_SURE', defaultValue: 80) / 100;

/// The English transducer's search. Beam search kept repeated words greedy
/// search dropped ("Good, good, good"), at the same speed.
/// (Tuning: `flutter test --dart-define=VD_SURE=85 --dart-define=VD_DECODING=greedy_search tool/measure_test.dart`.)
const _decoding = String.fromEnvironment('VD_DECODING', defaultValue: 'modified_beam_search');

/// Audio kept for the padding before a phrase. A phrase comes out of the VAD
/// up to its 60 s buffer after it started, plus a push of 10 s fed at once.
const _historySamples = 71 * _rate;

/// A phrase's samples with its padding before it: never before [floor] (the
/// phrase before, or the engine's first sample), never past the audio [fed].
(int, int) paddedRange({required int start, required int end, required int floor, required int fed, int pad = kPadSamples}) =>
    (max(start - pad, max(floor, 0)), min(end, fed));

double _meanConf(Phrase p) {
  final cs = [for (final w in p.words) w.conf ?? 1.0];
  return cs.isEmpty ? 0.0 : cs.reduce((a, b) => a + b) / cs.length;
}

/// Whether the reading of a phrase as cut is unsure enough to read it again, padded.
bool readAgainPadded(Phrase? plain) => plain == null || plain.words.isEmpty || _meanConf(plain) < kSureConf;

/// The reading the recognizer was surer of; the [first] one on a tie.
Phrase moreSure(Phrase first, Phrase second) => _meanConf(second) > _meanConf(first) ? second : first;

/// The last [maxSamples] samples given, addressed by their number since the
/// first: a ring buffer, so adding costs only the samples added.
class SampleHistory {
  SampleHistory({required this.maxSamples}) : _buf = Float32List(maxSamples);
  final int maxSamples;
  final Float32List _buf;

  /// Samples given so far.
  var _end = 0;

  /// The number of the oldest sample kept.
  int get start => max(0, _end - maxSamples);

  /// One past the newest sample.
  int get end => _end;

  void add(Float32List samples) {
    // More than the buffer holds: only the newest count.
    final skip = max(0, samples.length - maxSamples);
    _end += skip;
    for (var i = skip; i < samples.length;) {
      final at = _end % maxSamples;
      final n = min(samples.length - i, maxSamples - at);
      _buf.setRange(at, at + n, samples, i);
      i += n;
      _end += n;
    }
  }

  /// Samples [from]..[to] (as far as they are kept).
  Float32List slice(int from, int to) {
    final a = max(from, start), b = min(to, _end);
    final out = Float32List(max(0, b - a));
    for (var i = 0; i < out.length;) {
      final at = (a + i) % maxSamples;
      final n = min(out.length - i, maxSamples - at);
      out.setRange(i, i + n, _buf, at);
      i += n;
    }
    return out;
  }
}

/// The English transducer's files.
class TransducerFiles {
  const TransducerFiles({required this.encoder, required this.decoder, required this.joiner, required this.tokens});
  final File encoder;
  final File decoder;
  final File joiner;
  final File tokens;
}

/// What the engine runs: voice activity, the English reader (if English is
/// on), the ticked Indian models (with their shared tokens) and, with speaker
/// detection, the voice-print model.
class SpeechFiles {
  const SpeechFiles({required this.vad, this.english, this.indicTokens, this.indic = const {}, this.speakers});
  final File vad;
  final TransducerFiles? english;
  final File? indicTokens;
  final Map<Lang, File> indic;
  final File? speakers;
}

/// Silero voice activity + Parakeet (and the Indian models), in an isolate of
/// its own so the screens never wait for it.
class SherpaSpeech implements SpeechToText {
  SherpaSpeech._(this._isolate, this._toIsolate, this._replies);

  final Isolate _isolate;
  final SendPort _toIsolate;
  final StreamIterator<Object?> _replies;
  Future<void> _last = Future.value();

  /// [englishWords]: the bundled word list's text (for mixing the languages).
  /// [libraryDir]: where `sherpa-onnx-c-api` is (null on the phone: the app's own libraries).
  static Future<SpeechToText> start(
    SpeechFiles files,
    SpeechSetup setup, {
    required String englishWords,
    required int startMs,
    required int threads,
    String? libraryDir,
  }) async {
    final fromIsolate = ReceivePort();
    final Isolate isolate;
    try {
      // A crash in the isolate (onError) or its end (onExit) arrives as a reply,
      // so a request never waits for an engine that is gone.
      isolate = await Isolate.spawn(
        _run,
        _Start(fromIsolate.sendPort, _paths(files), setup, englishWords, startMs, threads, libraryDir),
        errorsAreFatal: true,
        onError: fromIsolate.sendPort,
        onExit: fromIsolate.sendPort,
      );
    } on Object catch (e) {
      fromIsolate.close();
      throw SpeechEngineFailed('$e');
    }
    final replies = StreamIterator<Object?>(fromIsolate);
    final first = await replies.moveNext() ? replies.current : null;
    if (first is! SendPort) {
      await replies.cancel();
      isolate.kill();
      throw SpeechEngineFailed('did not start: $first');
    }
    return SherpaSpeech._(isolate, first, replies);
  }

  static Map<String, String> _paths(SpeechFiles f) => {
        'vad': f.vad.path,
        if (f.english case final e?) ...{
          'encoder': e.encoder.path,
          'decoder': e.decoder.path,
          'joiner': e.joiner.path,
          'tokens': e.tokens.path,
        },
        if (f.indicTokens case final t?) 'indicTokens': t.path,
        for (final MapEntry(:key, :value) in f.indic.entries) 'indic.${key.name}': value.path,
        if (f.speakers case final v?) 'speakers': v.path,
      };

  /// One request at a time; replies come back in order.
  Future<Transcribed> _ask(Object message) {
    final reply = _last.then((_) async {
      _toIsolate.send(message);
      final r = await _replies.moveNext() ? _replies.current : null;
      if (r is Transcribed) return r;
      throw SpeechEngineFailed('$r');
    });
    _last = reply.then((_) {}, onError: (_) {});
    return reply;
  }

  @override
  Future<Transcribed> push(Float32List samples) => _ask(TransferableTypedData.fromList([samples]));

  @override
  Future<Transcribed> finish() => _ask('finish');

  @override
  Future<void> close() async {
    await _last;
    _toIsolate.send('close');
    // The models live in native memory: the isolate frees them and says so
    // before it ends. Killed straight away, it often never got to (on the
    // phone, each job left ~0.7 GB behind).
    try {
      await _replies.moveNext().timeout(const Duration(seconds: 10));
    } on Object {
      // Gone already, or stuck: end it anyway.
    }
    await _replies.cancel();
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _returnFreedMemory();
  }
}

/// The models' memory, once freed, stays with the app's allocator for reuse
/// (on the M31: 780 MB "free" but still the app's after each job). Hands it
/// back to the phone. Android only (bionic's `mallopt`).
void _returnFreedMemory() {
  if (!Platform.isAndroid) return;
  try {
    final mallopt = DynamicLibrary.process().lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('mallopt');
    mallopt(-101, 0); // M_PURGE
    mallopt(-104, 0); // M_PURGE_ALL (Android 13+; ignored before)
  } on Object {
    // Not available: the memory is still reused by the next job.
  }
}

class _Start {
  const _Start(this.replyTo, this.paths, this.setup, this.englishWords, this.startMs, this.threads, this.libraryDir);
  final SendPort replyTo;
  final Map<String, String> paths;
  final SpeechSetup setup;
  final String englishWords;
  final int startMs, threads;
  final String? libraryDir;
}

/// A recognizer's result, with the tokens' scores the package's reader drops.
({List<String> tokens, List<double> timestamps, List<double> logProbs}) _decode(so.OfflineRecognizer r, Float32List samples) {
  final stream = r.createStream();
  try {
    stream.acceptWaveform(samples: samples, sampleRate: _rate);
    r.decode(stream);
    final json = SherpaOnnxBindings.getOfflineStreamResultAsJson!(stream.ptr);
    final bytes = json.cast<Uint8>();
    var n = 0;
    while (bytes[n] != 0) {
      n++;
    }
    final parsed = jsonDecode(utf8.decode(bytes.asTypedList(n), allowMalformed: true)) as Map<String, dynamic>;
    SherpaOnnxBindings.destroyOfflineStreamResultJson!(json);
    return (
      tokens: List<String>.from(parsed['tokens'] as List? ?? const []),
      timestamps: [for (final t in parsed['timestamps'] as List? ?? const []) (t as num).toDouble()],
      logProbs: [for (final p in parsed['ys_log_probs'] as List? ?? const []) (p as num).toDouble()],
    );
  } finally {
    stream.free();
  }
}

void _run(_Start s) {
  final inbox = ReceivePort();
  late final so.VoiceActivityDetector vad;
  so.OfflineRecognizer? english;
  final indic = <Lang, so.OfflineRecognizer>{};
  so.SpeakerEmbeddingExtractor? voices;
  late final EnglishWords dict;
  final setup = s.setup;

  so.OfflineRecognizer indicReader(Lang l) => indic[l] ??= so.OfflineRecognizer(so.OfflineRecognizerConfig(
        model: so.OfflineModelConfig(
          nemoCtc: so.OfflineNemoEncDecCtcModelConfig(model: s.paths['indic.${l.name}']!),
          tokens: s.paths['indicTokens']!,
          numThreads: s.threads,
          debug: false,
        ),
      ));

  // Hindi or Gujarati first: the one spoken more, if it is ticked.
  final indian = setup.indian;
  final first = indian.isEmpty ? null : (indian.contains(setup.prefer) ? setup.prefer : indian.first);

  try {
    // On a PC (tests): Windows would take System32's 3 kB onnxruntime.dll stub
    // before the one next to sherpa-onnx, so load that one first.
    if (Platform.isWindows && s.libraryDir != null) DynamicLibrary.open('${s.libraryDir}/onnxruntime.dll');
    so.initBindings(s.libraryDir);
    dict = EnglishWords.parse(s.englishWords);
    vad = so.VoiceActivityDetector(
      config: so.VadModelConfig(
        sileroVad: so.SileroVadModelConfig(
          model: s.paths['vad']!,
          threshold: 0.5,
          minSilenceDuration: 0.5,
          minSpeechDuration: 0.25,
          maxSpeechDuration: 20,
          windowSize: _window,
        ),
        sampleRate: _rate,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 60,
    );
    if (setup.hasEnglish) {
      english = so.OfflineRecognizer(so.OfflineRecognizerConfig(
        model: so.OfflineModelConfig(
          transducer: so.OfflineTransducerModelConfig(
            encoder: s.paths['encoder']!,
            decoder: s.paths['decoder']!,
            joiner: s.paths['joiner']!,
          ),
          tokens: s.paths['tokens']!,
          modelType: 'nemo_transducer',
          numThreads: s.threads,
          debug: false,
        ),
        decodingMethod: _decoding,
        maxActivePaths: 4,
      ));
    }
    if (first != null) indicReader(first);
    if (setup.speakers && s.paths['speakers'] != null) {
      voices = so.SpeakerEmbeddingExtractor(
        config: so.SpeakerEmbeddingExtractorConfig(model: s.paths['speakers']!, numThreads: s.threads, debug: false),
      );
    }
  } catch (e) {
    s.replyTo.send('$e');
    return;
  }
  s.replyTo.send(inbox.sendPort);

  int ms(int samples) => s.startMs + samples * 1000 ~/ _rate;
  var fed = 0; // samples given to the VAD
  var settled = s.startMs;
  var rest = Float32List(0); // under one window, waiting for more
  var floor = 0; // where the phrase before ended, padding included
  final history = SampleHistory(maxSamples: _historySamples);

  Phrase read(so.OfflineRecognizer r, Float32List audio, int startMs, int endMs) {
    final d = _decode(r, audio);
    return phraseFromTokens(d.tokens, d.timestamps, startMs: startMs, endMs: endMs, logProbs: d.logProbs);
  }

  /// One phrase: its [samples] from sample [start] to [end], or with the
  /// audio [before] it (from sample [padded]) when that reads better.
  Phrase? recognize(Float32List samples, Float32List before, int padded, int start, int end) {
    Float32List withBefore() => before.isEmpty
        ? samples
        : (Float32List(before.length + samples.length)
          ..setAll(0, before)
          ..setAll(before.length, samples));
    Phrase? heard;
    final e = english;
    if (e != null) {
      heard = read(e, samples, ms(start), ms(end));
      if (before.isNotEmpty && readAgainPadded(heard)) {
        heard = moreSure(heard, read(e, withBefore(), ms(padded), ms(end)));
      }
    }
    Phrase? indianLine;
    if (first != null) {
      // No confidence to choose by: the Indian models read the padded phrase.
      final audio = withBefore();
      indianLine = read(indicReader(first), audio, ms(padded), ms(end));
      if (indian.length > 1 && worthTryingOther(indianLine, first)) {
        final other = indian.firstWhere((l) => l != first);
        final second = read(indicReader(other), audio, ms(padded), ms(end));
        if (pickIndic(indianLine, second, first) == other) indianLine = second;
      }
    }
    return writePhrase(english: heard, indic: indianLine, dict: dict);
  }

  /// Voice prints of a phrase's own samples (whole, or in windows when long).
  List<VoicePiece> prints(Float32List samples, int start) {
    final v = voices;
    if (v == null) return const [];
    final from = ms(start);
    final out = <VoicePiece>[];
    for (final (a, b) in printPieces(from, from + samples.length * 1000 ~/ _rate)) {
      final stream = v.createStream();
      try {
        final i = (a - from) * _rate ~/ 1000, j = min(samples.length, (b - from) * _rate ~/ 1000);
        stream.acceptWaveform(samples: Float32List.sublistView(samples, i, j), sampleRate: _rate);
        stream.inputFinished();
        if (v.isReady(stream)) out.add(VoicePiece(a, b, normalised(v.compute(stream))));
      } finally {
        stream.free();
      }
    }
    return out;
  }

  List<Phrase> takeSegments() {
    final out = <Phrase>[];
    while (!vad.isEmpty()) {
      final seg = vad.front();
      vad.pop();
      // The phrase itself is the VAD's (always whole); only the audio before
      // it comes from the history, when the history still has it.
      final start = seg.start, end = seg.start + seg.samples.length;
      final (a, _) = paddedRange(start: start, end: end, floor: max(floor, history.start), fed: fed);
      final padded = min(a, start);
      floor = end;
      final p = recognize(seg.samples, history.slice(padded, start), padded, start, end);
      if (p != null && p.text.isNotEmpty) out.add(voices == null ? p : p.withVoices(prints(seg.samples, start)));
      settled = max(settled, ms(end));
    }
    return out;
  }

  void feed(Float32List samples) {
    vad.acceptWaveform(samples);
    history.add(samples);
    fed += samples.length;
  }

  void handle(Object? message) {
    if (message is TransferableTypedData) {
      final pushed = message.materialize().asFloat32List();
      final all = Float32List(rest.length + pushed.length)
        ..setAll(0, rest)
        ..setAll(rest.length, pushed);
      var at = 0;
      for (; at + _window <= all.length; at += _window) {
        feed(Float32List.sublistView(all, at, at + _window));
      }
      rest = Float32List.fromList(Float32List.sublistView(all, at));
      final phrases = takeSegments();
      // With no speech going on, everything fed so far is settled — except the
      // last moment, where speech may be starting but not yet confirmed, and
      // the padding a phrase starting there takes from before it.
      if (!vad.isDetected()) settled = max(settled, ms(max(0, fed - _confirmSamples - kPadSamples)));
      s.replyTo.send(Transcribed(phrases, settled));
    } else if (message == 'finish') {
      if (rest.isNotEmpty) {
        feed(rest);
        rest = Float32List(0);
      }
      vad.flush();
      final phrases = takeSegments();
      settled = max(settled, ms(fed));
      s.replyTo.send(Transcribed(phrases, settled));
    } else if (message == 'close') {
      vad.free();
      english?.free();
      for (final r in indic.values) {
        r.free();
      }
      voices?.free();
      inbox.close();
      s.replyTo.send('closed');
    }
  }

  inbox.listen((message) {
    try {
      handle(message);
    } on Object catch (e) {
      s.replyTo.send('failed: $e');
    }
  });
}
