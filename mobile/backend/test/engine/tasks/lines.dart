import 'package:mobile_backend/data/transcript.dart';

/// A transcript line at [seconds], said by [who] (null: no speaker detection).
Phrase line(double seconds, String? who, String text) {
  final ms = (seconds * 1000).round();
  return Phrase(startMs: ms, endMs: ms + 1000, text: text, words: const [], speaker: who);
}
