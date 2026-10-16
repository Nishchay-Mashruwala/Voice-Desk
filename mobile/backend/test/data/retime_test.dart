import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/retime.dart';
import 'package:mobile_backend/data/transcript.dart';

/// The desktop's `retime_words` tests (transcript.rs), in ms.
void main() {
  test('edited text keeps the times of unchanged words', () {
    final old = [const Word('send', 0, 500, 0.9), const Word('the', 500, 700), const Word('report', 700, 1200, 0.8)];
    final out = retimeWords(old, 'Send the final report.', 0, 2000);
    expect(out.map((w) => w.text), ['Send', 'the', 'final', 'report.']);
    expect(out[0], const Word('Send', 0, 500, 0.9)); // kept: time and confidence
    // The new word fills the time between its neighbours.
    expect((out[2].startMs, out[2].endMs, out[2].conf), (700, 700, null));
    expect(out[3], const Word('report.', 700, 1200, 0.8));
  });

  test('new words at the end share the rest of the time', () {
    final out = retimeWords([const Word('hello', 0, 1000)], 'hello there friend', 0, 3000);
    expect([for (final w in out) (w.startMs, w.endMs)], [(0, 1000), (1000, 2000), (2000, 3000)]);
  });

  test('Gujarati words match by their letters and signs', () {
    final old = [const Word('હા', 0, 300), const Word('એનું', 300, 600), const Word('background', 600, 1200, 0.99)];
    final out = retimeWords(old, 'હા, એનું બેકગ્રાઉન્ડ', 0, 1200);
    expect([for (final w in out) (w.text, w.startMs, w.endMs)], [('હા,', 0, 300), ('એનું', 300, 600), ('બેકગ્રાઉન્ડ', 600, 1200)]);
  });

  test('words compare without case or punctuation', () {
    expect(norm('Hello,'), 'hello');
    expect(norm('“Don\'t”'), 'dont');
    expect(norm('કર્યું।'), 'કર્યું');
    expect(norm('...'), '');
  });
}
