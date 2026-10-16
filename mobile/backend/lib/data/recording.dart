import 'package:intl/intl.dart';

import '../engine/speech/speech_setup.dart';

/// Where a recording is. Stored as its [id].
enum RecordingStatus {
  recording('recording'),
  queued('queued'),
  processing('processing'),
  waitingCharge('waiting_charge'),
  done('done'),
  error('error');

  const RecordingStatus(this.id);
  final String id;

  static RecordingStatus fromId(String id) => values.firstWhere((s) => s.id == id);
}

/// Where a recording's summary and tasks are: none (Find tasks off, or made
/// before Plan 4), waiting (after its text), finding, found, failed.
enum TasksStatus {
  none,
  waiting,
  finding,
  found,
  failed;

  static TasksStatus fromId(String id) => values.firstWhere((s) => s.name == id, orElse: () => none);
}

/// A recording or a call, as the screens see it.
class Recording {
  const Recording({
    required this.id,
    required this.title,
    required this.kind,
    required this.startedAt,
    required this.duration,
    required this.status,
    this.error,
    this.processedMs = 0,
    this.setup = SpeechSetup.englishOnly,
    this.reprocessing = false,
    this.audioDeleted = false,
    this.compressFailed = false,
    this.audioPath,
    this.summary,
    this.tasksStatus = TasksStatus.none,
    this.tasksPart = 0,
    this.tasksWork = '',
  });

  final int id;
  final String title;
  /// `recording` or `call`.
  final String kind;
  final DateTime startedAt;
  final Duration? duration;
  final RecordingStatus status;
  final String? error;

  /// Speech to text is done up to here (ms).
  final int processedMs;

  /// How it is turned into text (fixed when it was made, or chosen for Process again).
  final SpeechSetup setup;

  /// Being processed again (its old text shows until the new is complete).
  final bool reprocessing;

  /// Its audio was deleted by "Keep recordings for": text only.
  final bool audioDeleted;

  /// Its FLAC didn't match three times: the pieces are kept as they were.
  final bool compressFailed;

  /// Its checked FLAC once compressed (null while it is WAV pieces).
  final String? audioPath;

  /// The task AI's summary, once found.
  final String? summary;

  final TasksStatus tasksStatus;

  /// The part the task step continues from, and its answers so far (or why
  /// it failed).
  final int tasksPart;
  final String tasksWork;

  /// How much of it is turned into text, 0..1.
  double get progress {
    final total = duration?.inMilliseconds ?? 0;
    if (total <= 0) return 0;
    return (processedMs / total).clamp(0.0, 1.0);
  }
}

/// "Recording · Oct 12, 14:05".
String defaultTitle(DateTime startedAt) => 'Recording · ${DateFormat('MMM dd, HH:mm').format(startedAt)}';
