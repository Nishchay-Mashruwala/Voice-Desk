import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/audio/audio_source.dart';
import 'package:record/record.dart';

void main() {
  test('records 16 kHz mono 16-bit, what the models read', () {
    expect(micConfig.encoder, AudioEncoder.pcm16bits);
    expect(micConfig.sampleRate, 16000);
    expect(micConfig.numChannels, 1);
  });

  test('other sounds (a video, a voice note, a ringtone) do not pause the recording', () {
    // record's default pauses at any audio-focus loss and never resumes.
    expect(micConfig.audioInterruption, AudioInterruptionMode.none);
  });
}
