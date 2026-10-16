import 'package:intl/intl.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/engine/audio/recorder_controller.dart';
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/speakers/voice_training.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/tasks/task_settings.dart';

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

/// A size on the phone: "1222 MB", or with a decimal under 10 MB ("0.4 MB",
/// not "0 MB").
String sizeText(int bytes) =>
    bytes < 9950000 ? '${(bytes / 1000000).toStringAsFixed(1)} MB' : '${megabytes(bytes)} MB';

/// What the models banner says: the speech models, the task model, or both.
String speechModelsText(SpeechModelsState m) {
  final (what, them) = switch (m.missing) {
    Missing.speech => ('the speech models', 'the speech models'),
    Missing.tasks => ('the task model', 'the task model'),
    Missing.both => ('the models', 'the models'),
  };
  return switch (m.phase) {
    ModelPhase.missing => switch (m.missing) {
      Missing.speech => 'Turn recordings into text: download $what (${megabytes(m.bytesToDownload)} MB, Wi-Fi recommended).',
      Missing.tasks => 'Find your tasks: download $what (${megabytes(m.bytesToDownload)} MB, Wi-Fi recommended).',
      Missing.both =>
        'Turn recordings into text and find your tasks: download $what (${megabytes(m.bytesToDownload)} MB, Wi-Fi recommended).',
    },
    ModelPhase.downloading => m.total > 0 && m.done >= m.total
        ? 'Preparing $them…'
        : m.missing == Missing.tasks
        ? 'Downloading the task model… ${megabytes(m.done)} of ${megabytes(m.total)} MB'
        : 'Downloading $what · ${megabytes(m.done)} of ${megabytes(m.total)} MB',
    ModelPhase.ready => 'The speech models are ready.',
    ModelPhase.failed => switch (m.message) {
      'storage_low' => 'Not enough free storage for $them (${megabytes(m.freeNeeded)} MB needed).',
      'corrupt' => 'The download was damaged. Try again.',
      _ => 'The download stopped. Check the connection and try again.',
    },
  };
}

/// "about 3 min left" (at least 1).
String _minutesLeft(Duration left) => 'about ${(left.inSeconds / 60).ceil().clamp(1, 1 << 30)} min left';

/// The line under the round mic about processing; null when there's nothing to say.
String? processingLine(ProcessingState s) {
  if (s.recordingId != null && s.step == 'speakers') return 'Finding who said what in “${s.title}”';
  if (s.recordingId != null && s.step == 'tasks') {
    return 'Finding tasks in “${s.title}”${s.parts > 1 ? ' · part ${s.part} of ${s.parts}' : ''}';
  }
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

/// A recording's badge: its status, with the percent while processing;
/// "Text only" once its audio was deleted.
String recordingBadgeText(Recording r) => r.status == RecordingStatus.processing
    ? 'Processing ${(r.progress * 100).floor()}%'
    : r.audioDeleted && r.status == RecordingStatus.done
    ? 'Text only'
    : statusText(r.status);

/// Why a recording couldn't be turned into text.
String transcriptErrorText(String? error) => switch (error) {
  'speech_crashed' =>
    'Turning this into text stopped the app twice. Close other apps and allow Unrestricted battery, then try again.',
  _ => "Couldn't turn this into text.",
};

/// The Languages chips.
String languageName(Lang l) => switch (l) {
  Lang.en => 'English',
  Lang.hi => 'हिन्दी Hindi',
  Lang.gu => 'ગુજરાતી Gujarati',
};

/// A model as the screens name it.
String modelName(ModelId id) => switch (id) {
  ModelId.vad => 'Voice activity',
  ModelId.englishFaster => 'English speech model (Faster)',
  ModelId.englishAccurate => 'English speech model (More accurate)',
  ModelId.indicTokens => 'Hindi/Gujarati words',
  ModelId.gujarati => 'Gujarati model',
  ModelId.hindi => 'Hindi model',
  ModelId.speakers => 'Speaker detection',
  ModelId.taskFaster => 'Task AI (Faster)',
  ModelId.taskAccurate => 'Task AI (More accurate)',
};

String taskAiName(TaskAi a) => switch (a) {
  TaskAi.faster => 'Faster',
  TaskAi.accurate => 'More accurate',
};

String accuracyName(Accuracy a) => switch (a) {
  Accuracy.auto => 'Auto — picks for this phone',
  Accuracy.faster => 'Faster',
  Accuracy.accurate => 'More accurate',
};

String englishChoiceName(EnglishModel m) => m == EnglishModel.faster ? 'Faster' : 'More accurate';

/// How far a download is, 0..100.
int percent(ModelState s) => s.total <= 0 ? 0 : (s.done * 100 ~/ s.total).clamp(0, 100);

/// Under the Languages chips, while a language's model downloads or after it failed.
String languageModelLine(Lang l, ModelState s) {
  final name = l == Lang.hi ? 'Hindi' : 'Gujarati';
  return s.phase == ModelPhase.failed
      ? "Couldn't download the $name model."
      : 'Downloading the $name model · ${percent(s)}%';
}

/// Why a model's download failed (Storage).
String modelFailureText(String? message) => switch (message) {
  'storage_low' => 'Not enough free storage.',
  'corrupt' => 'The download was damaged.',
  _ => 'The download stopped. Check the connection.',
};

/// "about 5 min for a 30-min recording" (at least 1).
String estimateText(Duration d) => 'about ${(d.inSeconds / 60).round().clamp(1, 1 << 30)} min for a 30-min recording';

/// "Keep recordings for" choices: Forever, 7 days, 30 days, 90 days, 1 year.
String keepAudioName(int days) => switch (days) {
  0 => 'Forever',
  365 => '1 year',
  _ => '$days days',
};

/// Settings → Your voice: when it was saved.
String voiceSavedText(DateTime? savedAt) =>
    savedAt == null ? 'Not trained yet' : 'Voice saved ${DateFormat('d MMM yyyy').format(savedAt)}';

/// Why training didn't save a voice.
String trainingMessageText(TrainingState s) => switch (s.message) {
  'too_little' => 'Only ${s.heardMs ~/ 1000}s of speech was heard. Please read the text aloud for about 15 seconds.',
  'microphone_denied' => 'Voice Desk needs the microphone to hear you. Allow it in Settings.',
  'busy' => 'Stop the recording first: it is using the microphone.',
  _ => "Your voice couldn't be learned. Try again.",
};
