import '../../data/transcript.dart';
import '../speakers/grouping.dart' show kMeLabel;
import 'task_answer.dart';

/// "You", in English, Hindi and Gujarati.
final _secondPerson = RegExp(r'\b(you|your|yours)\b|तुम|आप|तू|तुझे|तुम्हें|तेरा|તું|તમે|તને|તમને|તારે|તમારે|તારું|તમારું');

/// Words a sentence can open with before a comma that aren't someone's name.
const _notNames = {
  'hello', 'hi', 'hey', 'okay', 'ok', 'thanks', 'yes', 'so', 'and', 'well', 'right', 'sure', 'great', 'good', //
  'last', 'also', 'then', 'now', 'fine', 'please', 'one', 'first',
};

/// A sentence opening with a capitalised (Latin) word and a comma: "Priya, …".
final _opening = RegExp(r'(?:^|[.!?]\s+)([A-Z][a-z]+)\s*,');

String _norm(String s) => s.replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}]', unicode: true), '').toLowerCase();

/// The quote without a leading "[mm:ss]" or a speaker's label.
String _bare(String quote, Set<String?> speakers) {
  var q = quote.replaceFirst(RegExp(r'^\s*\[\d+:\d\d\]\s*'), '');
  final m = RegExp(r'^\s*([^:]{1,30}):\s*(.*)$', dotAll: true).firstMatch(q);
  if (m != null && speakers.contains(m.group(1)!.trim())) q = m.group(2)!;
  return q;
}

/// The line [t]'s quote comes from, or null when it can't be found: the line
/// holding the whole quote, else the longest line within it that is at least
/// half of it (a quote across two lines). A short line ("OK.") is within
/// almost any quote, so it alone never decides.
Phrase? _quoted(FoundTask t, List<Phrase> lines) {
  final q = _norm(_bare(t.quote ?? '', {for (final l in lines) l.speaker}));
  if (q.isEmpty) return null;
  Phrase? within;
  var longest = 0;
  for (final l in lines) {
    final text = _norm(l.text);
    if (text.isEmpty) continue;
    if (text.contains(q)) return l;
    if (q.contains(text) && text.length * 2 >= q.length && text.length > longest) (within, longest) = (l, text.length);
  }
  return within;
}

/// Whether a meeting's task is the owner's, by the line it quotes (the
/// 2026-10-15 comparison: it removed most of other people's tasks, whatever
/// the model, and lost no real one). Kept when the line is his ("Me"), or is
/// said to him (one of [ownerNames], or "you"), and doesn't open with someone
/// else's name. A quote that isn't in the transcript is kept: it can't be
/// judged. With no "Me" line, his own promises can't be told from anyone's,
/// so only what is said to him is kept.
bool keepTask(FoundTask t, List<Phrase> lines, {required List<String> ownerNames}) {
  final line = _quoted(t, lines);
  if (line == null) return true;
  if (line.speaker == kMeLabel) return true;
  final mine = {for (final n in ownerNames) n.toLowerCase()};
  // Said to someone else by name: the quote opens with a name (Latin letters;
  // a name in Hindi or Gujarati script can't be compared) that isn't his.
  final quote = _bare(t.quote!, {for (final l in lines) l.speaker});
  for (final m in _opening.allMatches(quote)) {
    final word = m.group(1)!.toLowerCase();
    if (_notNames.contains(word)) continue;
    if (!mine.contains(word)) return false;
    break;
  }
  final text = line.text.toLowerCase();
  return mine.any(text.contains) || _secondPerson.hasMatch(text);
}

/// Where the line [t] quotes starts (for "Where it was said"), or null.
int? quoteStartMs(FoundTask t, List<Phrase> lines) => _quoted(t, lines)?.startMs;
