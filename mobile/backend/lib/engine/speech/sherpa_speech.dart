import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import '../../data/transcript.dart';
import '../models/speech_model.dart';
import 'speech_to_text.dart';
import 'words.dart';

const _rate = 16000;
const _window = 512;

/// Silero needs this much speech (2 windows + its 0.25 s minimum) before it
/// says speech started — and then dates the start back by as much.
const _confirmSamples = 2 * _window + _rate ~/ 4;

/// Silero voice activity + Parakeet (sherpa-onnx), in an isolate of its own so
/// the screens never wait for it.
class SherpaSpeech implements SpeechToText {
  SherpaSpeech._(this._isolate, this._toIsolate, this._replies);

  final Isolate _isolate;
  final SendPort _toIsolate;
  final StreamIterator<Object?> _replies;
  Future<void> _last = Future.value();

  /// [libraryDir]: where `sherpa-onnx-c-api` is (null on the phone: the app's own libraries).
  static Future<SpeechToText> start(SpeechModelFiles files,
      {required int startMs, required int threads, String? libraryDir}) async {
    final fromIsolate = ReceivePort();
    final Isolate isolate;
    try {
      // A crash in the isolate (onError) or its end (onExit) arrives as a reply,
      // so a request never waits for an engine that is gone.
      isolate = await Isolate.spawn(
        _run,
        _Start(fromIsolate.sendPort, files.vad.path, files.model.path, files.tokens.path, startMs, threads, libraryDir),
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
    await _replies.cancel();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

class _Start {
  const _Start(this.replyTo, this.vad, this.model, this.tokens, this.startMs, this.threads, this.libraryDir);
  final SendPort replyTo;
  final String vad, model, tokens;
  final int startMs, threads;
  final String? libraryDir;
}

void _run(_Start s) {
  final inbox = ReceivePort();
  late final so.VoiceActivityDetector vad;
  late final so.OfflineRecognizer recognizer;
  try {
    // On a PC (tests): Windows would take System32's 3 kB onnxruntime.dll stub
    // before the one next to sherpa-onnx, so load that one first.
    if (Platform.isWindows && s.libraryDir != null) DynamicLibrary.open('${s.libraryDir}/onnxruntime.dll');
    so.initBindings(s.libraryDir);
    vad = so.VoiceActivityDetector(
      config: so.VadModelConfig(
        sileroVad: so.SileroVadModelConfig(
          model: s.vad,
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
    recognizer = so.OfflineRecognizer(so.OfflineRecognizerConfig(
      model: so.OfflineModelConfig(
        nemoCtc: so.OfflineNemoEncDecCtcModelConfig(model: s.model),
        tokens: s.tokens,
        numThreads: s.threads,
        debug: false,
      ),
    ));
  } catch (e) {
    s.replyTo.send('$e');
    return;
  }
  s.replyTo.send(inbox.sendPort);

  int ms(int samples) => s.startMs + samples * 1000 ~/ _rate;
  var fed = 0; // samples given to the VAD
  var settled = s.startMs;
  var rest = Float32List(0); // under one window, waiting for more

  List<Phrase> takeSegments() {
    final out = <Phrase>[];
    while (!vad.isEmpty()) {
      final seg = vad.front();
      vad.pop();
      final stream = recognizer.createStream();
      stream.acceptWaveform(samples: seg.samples, sampleRate: _rate);
      recognizer.decode(stream);
      final r = recognizer.getResult(stream);
      stream.free();
      final p = phraseFromTokens(r.tokens, r.timestamps, startMs: ms(seg.start), endMs: ms(seg.start + seg.samples.length));
      if (p.text.isNotEmpty) out.add(p);
      settled = max(settled, ms(seg.start + seg.samples.length));
    }
    return out;
  }

  void handle(Object? message) {
    if (message is TransferableTypedData) {
      final pushed = message.materialize().asFloat32List();
      final all = Float32List(rest.length + pushed.length)
        ..setAll(0, rest)
        ..setAll(rest.length, pushed);
      var at = 0;
      for (; at + _window <= all.length; at += _window) {
        vad.acceptWaveform(Float32List.sublistView(all, at, at + _window));
        fed += _window;
      }
      rest = Float32List.fromList(Float32List.sublistView(all, at));
      final phrases = takeSegments();
      // With no speech going on, everything fed so far is settled — except the
      // last moment, where speech may be starting but not yet confirmed.
      if (!vad.isDetected()) settled = max(settled, ms(max(0, fed - _confirmSamples)));
      s.replyTo.send(Transcribed(phrases, settled));
    } else if (message == 'finish') {
      if (rest.isNotEmpty) {
        vad.acceptWaveform(rest);
        fed += rest.length;
        rest = Float32List(0);
      }
      vad.flush();
      final phrases = takeSegments();
      settled = max(settled, ms(fed));
      s.replyTo.send(Transcribed(phrases, settled));
    } else if (message == 'close') {
      vad.free();
      recognizer.free();
      inbox.close();
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


