import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/data/transcript_text.dart';

Recording rec({Duration duration = const Duration(minutes: 32, seconds: 10)}) => Recording(
      id: 1,
      title: 'Weekly review',
      kind: 'recording',
      startedAt: DateTime(2026, 10, 14, 14, 5),
      duration: duration,
      status: RecordingStatus.done,
    );

Phrase line(int ms, String text, [String? speaker]) =>
    Phrase(startMs: ms, endMs: ms + 1000, text: text, words: const [], speaker: speaker, speakerGroup: speaker == null ? null : 1);

void main() {
  test("one speaker's lines join, a change starts a new line", () {
    expect(
        transcriptText(rec(), [
          line(2000, 'Good morning,', 'Me'),
          line(3500, 'shall we start?', 'Me'),
          line(5000, 'Yes. હા, આજે બે વાત છે.', 'Kiran'),
          line(9000, 'Okay.', 'Me'),
        ]),
        'Weekly review\n'
        '14 Oct 2026, 14:05 · 32 min\n'
        '\n'
        '[00:02] Me: Good morning, shall we start?\n'
        '[00:05] Kiran: Yes. હા, આજે બે વાત છે.\n'
        '[00:09] Me: Okay.\n');
  });

  test('times past an hour have hours', () {
    expect(transcriptText(rec(duration: const Duration(minutes: 75)), [line(3723000, 'Late on.', 'Me')]),
        endsWith('[1:02:03] Me: Late on.\n'));
  });

  test('lines without speakers are each a line', () {
    expect(transcriptText(rec(), [line(2000, 'First.'), line(3000, 'Second.')]), endsWith('\n\n[00:02] First.\n[00:03] Second.\n'));
  });

  test('the length reads 32 min, 1 min, 1 h 05 min', () {
    expect(lengthText(const Duration(minutes: 32, seconds: 10)), '32 min');
    expect(lengthText(const Duration(seconds: 12)), '1 min');
    expect(lengthText(const Duration(hours: 1, minutes: 5, seconds: 20)), '1 h 05 min');
  });
}
