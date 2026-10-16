import 'package:intl/intl.dart';

import 'recording.dart';
import 'transcript.dart';

/// A transcript as plain text, to copy or share:
///
/// ```
/// Weekly review
/// 14 Oct 2026, 14:05 · 32 min
///
/// [00:02] Me: Good morning, shall we start?
/// [00:05] Kiran: Yes. હા, આજે બે વાત છે.
/// ```
///
/// A new line each time the speaker changes (one speaker's lines joined with a
/// space); lines without a speaker are each a line.
String transcriptText(Recording r, List<Phrase> lines) {
  final out = StringBuffer()
    ..writeln(r.title)
    ..writeln([DateFormat('d MMM yyyy, HH:mm').format(r.startedAt), if (r.duration != null) lengthText(r.duration!)]
        .join(' · '))
    ..writeln();
  String? last;
  var open = false;
  for (final l in lines) {
    final who = l.speaker;
    if (open && who != null && who == last) {
      out.write(' ${l.text}');
      continue;
    }
    if (open) out.writeln();
    out.write('[${_time(l.startMs)}] ${who == null ? '' : '$who: '}${l.text}');
    open = true;
    last = who;
  }
  if (open) out.writeln();
  return out.toString();
}

/// "32 min", "1 min" (at least), "1 h 05 min".
String lengthText(Duration d) {
  final minutes = (d.inSeconds / 60).round().clamp(1, 1 << 30);
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';
}

/// `mm:ss`, or `h:mm:ss` past an hour.
String _time(int ms) {
  final s = ms ~/ 1000;
  String two(int n) => n.toString().padLeft(2, '0');
  return s >= 3600 ? '${s ~/ 3600}:${two(s % 3600 ~/ 60)}:${two(s % 60)}' : '${two(s ~/ 60)}:${two(s % 60)}';
}
