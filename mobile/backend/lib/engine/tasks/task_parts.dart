/// Cuts a transcript ([transcriptForAi]) into parts the task model can read
/// with room for its answer: about [maxTokens] each, counted with the model's
/// own tokenizer ([countTokens]), cut at line ends, the last ~[overlapTokens]
/// of a part carried into the next as "(…continued) …" (the desktop's
/// `chunk`, by tokens instead of bytes: Gujarati takes about twice the
/// tokens per byte of English). A line longer than a part is cut at word ends.
/// A part can go over by what it carries over: it always gets one new line.
Future<List<String>> transcriptParts(
  String transcript,
  Future<int> Function(String text) countTokens, {
  int maxTokens = 3000,
  int overlapTokens = 400,
}) async {
  if (await countTokens(transcript) <= maxTokens) return [transcript];
  final lines = <(String, int)>[];
  for (final line in transcript.split('\n')) {
    final n = await countTokens(line);
    lines.addAll(n <= maxTokens ? [(line, n)] : await _cut(line, n, countTokens, maxTokens));
  }
  final parts = <String>[];
  var current = StringBuffer();
  var tokens = 0;
  var hasNew = false;
  for (final (line, n) in lines) {
    if (hasNew && tokens + n + 1 > maxTokens) {
      final text = current.toString();
      parts.add(text);
      current = StringBuffer('(…continued) ${_tail(text, tokens, overlapTokens)}\n');
      tokens = await countTokens(current.toString());
      hasNew = false;
    }
    current
      ..write(line)
      ..write('\n');
    tokens += n + 1;
    hasNew = true;
  }
  if (hasNew) parts.add(current.toString());
  return parts;
}

/// About the last [overlap] tokens of [text] (of [tokens]), from a word's start.
String _tail(String text, int tokens, int overlap) {
  if (tokens <= overlap) return text.trim();
  var cut = text.length - (text.length * overlap / tokens).round();
  while (cut < text.length && text[cut].trim().isNotEmpty) {
    cut++;
  }
  return text.substring(cut).trim();
}

/// A line of [n] tokens cut at word ends into pieces of at most [max].
Future<List<(String, int)>> _cut(String line, int n, Future<int> Function(String) count, int max) async {
  final words = line.split(' ');
  final perChar = n / line.length;
  final pieces = <(String, int)>[];
  var start = 0;
  while (start < words.length) {
    var end = start, chars = 0;
    while (end < words.length && (chars + words[end].length + 1) * perChar <= max * 0.95) {
      chars += words[end].length + 1;
      end++;
    }
    if (end == start) end = start + 1;
    var piece = words.sublist(start, end).join(' ');
    var tokens = await count(piece);
    while (tokens > max && end - start > 1) {
      end = start + (end - start) * 9 ~/ 10;
      piece = words.sublist(start, end).join(' ');
      tokens = await count(piece);
    }
    pieces.add((piece, tokens));
    start = end;
  }
  return pieces;
}
