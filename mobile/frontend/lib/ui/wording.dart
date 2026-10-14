import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/engine/audio/recorder_controller.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';

/// Words for what the engine and data report as ids.
String statusText(RecordingStatus s) => switch (s) {
  RecordingStatus.recording => 'Recording…',
  RecordingStatus.queued => 'Waiting to be processed',
  RecordingStatus.processing => 'Processing…',
  RecordingStatus.waitingCharge => 'Waiting for charging',
  RecordingStatus.done => 'Done',
  RecordingStatus.error => 'Failed',
};

String recorderMessageText(String id) => switch (id) {
  'microphone_denied' => 'Voice Desk needs the microphone to record. Allow it in Settings.',
  'storage_low' => 'Not enough free storage to start recording.',
  'storage_full_stopped' => 'Storage is full, so the recording stopped. It was saved.',
  'too_short' => 'That recording was too short to keep.',
  'start_failed' => "Recording couldn't start. Try again.",
  'recording_failed' => "Recording stopped: the audio couldn't be saved. What was recorded is kept.",
  _ => id,
};

/// The line under the round mic, like the desktop's state title.
String recorderPhaseText(RecorderPhase p) => switch (p) {
  RecorderPhase.idle => 'Ready to record',
  RecorderPhase.starting => 'Starting…',
  RecorderPhase.recording => 'Recording',
  RecorderPhase.paused => 'Paused',
};

/// Bytes as whole megabytes (as download sizes are usually shown).
int megabytes(int bytes) => (bytes / 1000000).round();

/// What the speech-model banner says.
String speechModelText(SpeechModelState m) => switch (m.phase) {
  SpeechModelPhase.missing => 'Turn recordings into text: download the speech model (105 MB, Wi-Fi recommended).',
  SpeechModelPhase.downloading =>
    m.total > 0 && m.done >= m.total
        ? 'Preparing the speech model…'
        : 'Downloading the speech model · ${megabytes(m.done)} of ${megabytes(m.total)} MB',
  SpeechModelPhase.ready => 'The speech model is ready.',
  SpeechModelPhase.failed => switch (m.message) {
    'storage_low' => 'Not enough free storage for the speech model (300 MB needed).',
    'corrupt' => 'The download was damaged. Try again.',
    _ => 'The download stopped. Check the connection and try again.',
  },
};

/// "about 3 min left" (at least 1).
String _minutesLeft(Duration left) => 'about ${(left.inSeconds / 60).ceil().clamp(1, 1 << 30)} min left';

/// The line under the round mic about processing; null when there's nothing to say.
String? processingLine(ProcessingState s) {
  if (s.recordingId != null) {
    final left = s.left == null ? '' : ' · ${_minutesLeft(s.left!)}';
    return 'Turning “${s.title}” into text · ${(s.progress * 100).floor()}%$left';
  }
  return switch (s.waiting) {
    'charge' => 'Waiting for charging to turn recordings into text',
    'cool' => 'Waiting for the phone to cool down',
    _ => null, // 'model': the download banner says it
  };
}

/// A recording's badge: its status, with the percent while processing.
String recordingBadgeText(Recording r) =>
    r.status == RecordingStatus.processing ? 'Processing ${(r.progress * 100).floor()}%' : statusText(r.status);

/// Why a recording couldn't be turned into text.
String transcriptErrorText(String? error) => switch (error) {
  'speech_crashed' =>
    'Turning this into text stopped the app twice. Close other apps and allow Unrestricted battery, then try again.',
  _ => "Couldn't turn this into text.",
};
