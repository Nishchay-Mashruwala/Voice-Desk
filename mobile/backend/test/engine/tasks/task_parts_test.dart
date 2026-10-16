import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/tasks/task_parts.dart';

/// A tokenizer for tests: one token per 4 characters.
Future<int> fourChars(String s) async => (s.length / 4).ceil();

void main() {
  test('a short transcript is one part', () async {
    expect(await transcriptParts('[00:00] Me: Buy milk.', fourChars), ['[00:00] Me: Buy milk.']);
  });

  test('long transcripts are cut at line ends with the last part carried over', () async {
    final lines = [for (var i = 0; i < 60; i++) '[${i.toString().padLeft(2, '0')}:00] Person 1: ${'word ' * 40}line $i.'];
    final parts = await transcriptParts(lines.join('\n'), fourChars, maxTokens: 1000, overlapTokens: 100);
    expect(parts.length, greaterThan(2));
    for (final p in parts) {
      expect(await fourChars(p), lessThanOrEqualTo(1000 + 100 + 20), reason: 'a part, and what it carries over');
    }
    for (final p in parts.skip(1)) {
      expect(p, startsWith('(…continued) '));
    }
    for (var i = 0; i < 60; i++) {
      expect(parts.where((p) => p.contains('line $i.\n') || p.endsWith('line $i.')), isNotEmpty, reason: 'line $i');
    }
    // After what is carried over, the part's own lines start at a line's start.
    expect(parts[1].split('\n')[1], matches(RegExp(r'^\[\d\d:00\] Person 1: ')));
  });

  test('a line longer than a part is cut at word ends', () async {
    final monologue = '[00:00] Me: ${List.generate(2000, (i) => 'w$i').join(' ')}';
    final parts = await transcriptParts(monologue, fourChars, maxTokens: 1000, overlapTokens: 100);
    expect(parts.length, greaterThan(2));
    final words = <String>{for (final p in parts) ...p.replaceFirst('(…continued) ', '').split(RegExp(r'\s+'))};
    for (var i = 0; i < 2000; i++) {
      expect(words.contains('w$i'), isTrue, reason: 'w$i');
    }
    for (final p in parts) {
      expect(await fourChars(p), lessThanOrEqualTo(1000 + 100 + 20));
    }
  });
}
