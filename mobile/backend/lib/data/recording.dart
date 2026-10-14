import 'package:intl/intl.dart';

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

  /// How much of it is turned into text, 0..1.
  double get progress {
    final total = duration?.inMilliseconds ?? 0;
    if (total <= 0) return 0;
    return (processedMs / total).clamp(0.0, 1.0);
  }
}

/// "Recording · Oct 12, 14:05".
String defaultTitle(DateTime startedAt) => 'Recording · ${DateFormat('MMM dd, HH:mm').format(startedAt)}';
