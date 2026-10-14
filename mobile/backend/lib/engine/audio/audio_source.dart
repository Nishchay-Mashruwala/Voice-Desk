import 'dart:typed_data';

import 'package:record/record.dart';

import 'wav.dart';

/// Where recorded audio comes from: 16 kHz mono 16-bit PCM chunks.
abstract class AudioSource {
  /// Asks for the microphone if it hasn't been allowed yet.
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> start();
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();

  /// How loud it is right now, 0..1.
  Stream<double> get level;
}

/// How the microphone records: the models' input format. Other sounds don't
/// pause it: record's default pauses at any audio-focus loss (a video, a voice
/// note, a ringtone) and never resumes, silently losing the rest.
const micConfig = RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: kSampleRate,
  numChannels: 1,
  audioInterruption: AudioInterruptionMode.none,
);

/// The phone's microphone (package `record`).
class MicAudioSource implements AudioSource {
  final _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(micConfig);

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  /// dBFS (-60 quiet .. 0 loudest) mapped to 0..1.
  @override
  Stream<double> get level => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 150))
      .map((a) => ((a.current + 60) / 60).clamp(0.0, 1.0));
}
