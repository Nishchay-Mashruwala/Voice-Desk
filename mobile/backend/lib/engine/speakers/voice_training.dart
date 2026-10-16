import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../audio/audio_source.dart';
import '../audio/recorder_controller.dart';
import '../audio/wav.dart';
import '../models/catalogue.dart';
import '../models/speech_model.dart';
import 'sherpa_voice_print.dart';

/// The reading stops by itself after this long…
const kTrainingMaxMs = 25000;

/// …and Done can be pressed from this long.
const kTrainingDoneFromMs = 8000;

/// A voice is learned from at least this much speech.
const kMinTrainingSpeechMs = 6000;

/// The voice print is the mean of windows this long, this far apart.
const kTrainingWindowMs = 3000;
const kTrainingStepMs = 1500;

/// The windows of [speechMs] of speech the print is made of (ms).
List<(int, int)> trainingWindows(int speechMs) => [
      for (var at = 0; at + kTrainingWindowMs <= speechMs; at += kTrainingStepMs) (at, at + kTrainingWindowMs),
    ];

/// The voice print of what was said in [samples] (16 kHz), and how much speech
/// it heard (ms); no print under [kMinTrainingSpeechMs].
typedef VoicePrinter = Future<(Float32List?, int)> Function(Float32List samples);

final voicePrinterProvider = Provider<VoicePrinter>((ref) {
  final store = ref.watch(modelStoreProvider);
  return (samples) => sherpaVoicePrint(samples,
      vad: store.file(ModelId.vad, 'silero_vad.onnx').path, speakers: store.file(ModelId.speakers, 'campplus.onnx').path);
});

/// Your trained voice and when it was saved; (null, null) until trained.
final myVoiceProvider = FutureProvider<(Float32List?, DateTime?)>((ref) async {
  final speakers = ref.watch(speakersRepositoryProvider);
  return (await speakers.myVoice(), await speakers.myVoiceSavedAt());
});

enum TrainingPhase { idle, recording, working, saved, failed }

/// Training "Me". [message] is an id the screen words: `too_little`,
/// `microphone_denied`, `busy` (a recording is running), `failed`.
@immutable
class TrainingState {
  const TrainingState(
      {this.phase = TrainingPhase.idle, this.elapsed = Duration.zero, this.level = 0, this.message, this.heardMs = 0});
  final TrainingPhase phase;
  final Duration elapsed;
  final double level;
  final String? message;

  /// How much speech the reading had (once worked out).
  final int heardMs;

  bool get canFinish => phase == TrainingPhase.recording && elapsed.inMilliseconds >= kTrainingDoneFromMs;

  TrainingState copyWith({Duration? elapsed, double? level}) => TrainingState(
      phase: phase, elapsed: elapsed ?? this.elapsed, level: level ?? this.level, message: message, heardMs: heardMs);
}

final voiceTrainingProvider = NotifierProvider.autoDispose<VoiceTraining, TrainingState>(VoiceTraining.new);

/// Records a short reading and learns your voice from it.
class VoiceTraining extends Notifier<TrainingState> {
  final _pcm = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _audio;
  StreamSubscription<double>? _levels;
  bool _micOn = false;

  /// The microphone of this reading, kept: it is stopped even after the
  /// screen (and with it this notifier's ref) is gone.
  AudioSource? _source;

  @override
  TrainingState build() {
    ref.onDispose(() {
      // The screen closed mid-reading: the microphone goes off.
      unawaited(_stopMic());
    });
    return const TrainingState();
  }

  Future<void> start() async {
    if (state.phase == TrainingPhase.recording || state.phase == TrainingPhase.working) return;
    // The microphone is the recording's.
    if (ref.read(recorderProvider).phase != RecorderPhase.idle) {
      state = const TrainingState(phase: TrainingPhase.failed, message: 'busy');
      return;
    }
    state = const TrainingState(phase: TrainingPhase.recording);
    final source = ref.read(audioSourceProvider);
    _source = source;
    final allowed = await source.hasPermission();
    if (!ref.mounted) return;
    if (!allowed) {
      state = const TrainingState(phase: TrainingPhase.failed, message: 'microphone_denied');
      return;
    }
    _pcm.clear();
    try {
      final stream = await source.start();
      _micOn = true;
      if (!ref.mounted) return await _stopMic(); // closed while the microphone was starting
      _audio = stream.listen(_add, onError: (Object _) => unawaited(_fail()));
      _levels = source.level.listen((l) {
        if (ref.mounted && state.phase == TrainingPhase.recording) state = state.copyWith(level: l);
      });
    } on Object {
      await _fail();
    }
  }

  void _add(Uint8List pcm) {
    if (!ref.mounted || state.phase != TrainingPhase.recording) return;
    _pcm.add(pcm);
    final ms = _pcm.length * 1000 ~/ kBytesPerSecond;
    state = state.copyWith(elapsed: Duration(milliseconds: ms));
    if (ms >= kTrainingMaxMs) unawaited(done());
  }

  /// The reading is over: its voice print is worked out and saved.
  Future<void> done() async {
    if (state.phase != TrainingPhase.recording) return;
    state = TrainingState(phase: TrainingPhase.working, elapsed: state.elapsed);
    await _stopMic();
    final bytes = _pcm.takeBytes();
    final pcm = bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.length ~/ 2);
    final samples = Float32List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      samples[i] = pcm[i] / 32768;
    }
    try {
      final (print, heard) = await ref.read(voicePrinterProvider)(samples);
      if (!ref.mounted) return;
      if (print == null) {
        state = TrainingState(phase: TrainingPhase.failed, message: 'too_little', heardMs: heard);
        return;
      }
      await ref.read(speakersRepositoryProvider).saveMyVoice(print, at: DateTime.now());
      ref.invalidate(myVoiceProvider);
      if (ref.mounted) state = TrainingState(phase: TrainingPhase.saved, heardMs: heard);
    } on Object {
      if (ref.mounted) state = const TrainingState(phase: TrainingPhase.failed, message: 'failed');
    }
  }

  /// Stops without keeping anything.
  Future<void> cancel() async {
    await _stopMic();
    _pcm.clear();
    if (ref.mounted) state = const TrainingState();
  }

  /// Deletes what was learned about your voice.
  Future<void> forget() async {
    await ref.read(speakersRepositoryProvider).forgetMyVoice();
    ref.invalidate(myVoiceProvider);
    if (ref.mounted) state = const TrainingState();
  }

  Future<void> _fail() async {
    await _stopMic();
    if (ref.mounted) state = const TrainingState(phase: TrainingPhase.failed, message: 'failed');
  }

  Future<void> _stopMic() async {
    final source = _source;
    if (!_micOn || source == null) return;
    _micOn = false;
    await _levels?.cancel();
    try {
      await source.stop();
    } on Object {
      // Already off.
    }
    await _audio?.cancel();
  }
}
