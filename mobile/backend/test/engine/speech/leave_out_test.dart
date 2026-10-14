import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/speech/leave_out.dart';

/// The desktop's tests (desktop/backend/core/src/omit.rs), same cases.
void main() {
  test('leaves out words and phrases', () {
    final o = LeaveOut('umm, uh,  The The \n');
    expect(o.text('so umm I think uh we should'), 'so I think we should');
    // Case and the punctuation around a word don't matter.
    expect(o.text('Send it, UMM, today'), 'Send it, today');
    // A repeated word is a stutter: one stays (however many were said).
    expect(o.text('check the the report and the numbers'), 'check the report and the numbers');
    expect(o.text('The the the plan'), 'The plan');
    // Other phrases go as a whole, and only those words in a row.
    final o2 = LeaveOut('you know');
    expect(o2.text("it's, you know, fine and I know you"), "it's, fine and I know you");
    // Only whole words: "umbrella", "uhh" and "thumm" stay.
    expect(o.text('umbrella uhh thumm'), 'umbrella uhh thumm');
    expect(o.text('umm uh'), '');
    expect(LeaveOut(' , \n').isEmpty, isTrue);
    expect(LeaveOut('').text('umm  hello'), 'umm  hello'); // nothing to leave out: untouched
  });

  test('sentences keep their end and capital', () {
    final o = LeaveOut('umm, uh');
    expect(o.text('Umm, the report is ready.'), 'The report is ready.');
    expect(o.text("It's done, umm. Uh, next one?"), "It's done. Next one?");
    expect(o.text('Is it ready, umm?'), 'Is it ready?');
    // Mid-sentence: no capital added.
    expect(o.text('we umm should go'), 'we should go');
    // A removed lowercase filler doesn't capitalise what follows.
    expect(o.text('umm we should'), 'we should');
  });

  test('a phrase loses the same words from its timings, so highlighting stays in step', () {
    final p = Phrase(startMs: 0, endMs: 3000, text: 'Umm, the report', words: const [
      Word('Umm,', 0, 400),
      Word('the', 400, 700),
      Word('report', 700, 3000),
    ]);
    final out = LeaveOut('umm').phrase(p)!;
    expect(out.text, 'The report');
    expect(out.words, const [Word('The', 400, 700), Word('report', 700, 3000)]);
  });

  test('a phrase with nothing left is dropped', () {
    final p = Phrase(startMs: 0, endMs: 500, text: 'umm', words: const [Word('umm', 0, 500)]);
    expect(LeaveOut('umm').phrase(p), isNull);
  });
}
