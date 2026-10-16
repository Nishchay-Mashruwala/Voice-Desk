import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/speech/your_words.dart';
import 'package:mobile_backend/engine/tasks/task_mode.dart';
import 'package:mobile_backend/engine/tasks/task_prompts.dart';

import 'lines.dart';

void main() {
  test("the transcript groups a speaker's lines", () {
    final text = transcriptForAi([
      line(0, 'Person 1', 'Okay.'),
      line(2, 'Person 1', 'Shall we start?'),
      line(65, 'Me', 'Yes.'),
      line(70, 'Person 1', 'Good.'),
    ]);
    expect(text, '[00:00] Person 1: Okay. Shall we start?\n[01:05] Me: Yes.\n[01:10] Person 1: Good.');
  });

  test('lines without a speaker are written without a label', () {
    expect(transcriptForAi([line(0, null, 'Buy milk.'), line(3, null, 'Call the bank.')]), '[00:00] Buy milk. Call the bank.');
    expect(transcriptForAi([]), '');
  });

  test('who the owner is, as the desktop says it', () {
    expect(whoAmI(const YourWords(name: 'Nishchay', aliases: ' Nishu, NM ')),
        'The user\'s name is "Nishchay". People may also call them: Nishu, NM. Lines labelled "Me" were spoken by the user.');
    expect(whoAmI(const YourWords()), 'The user\'s name is "the user". Lines labelled "Me" were spoken by the user.');
    expect(ownerNames(const YourWords(name: 'Nishchay', aliases: 'Nishu, ,NM')), ['Nishchay', 'Nishu', 'NM']);
  });

  test('the ChatML has thinking off', () {
    expect(chatPrompt('SYS', 'USER'),
        '<|im_start|>system\nSYS<|im_end|>\n<|im_start|>user\nUSER<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n');
  });

  test("a part's prompt is the desktop's", () {
    expect(partPrompt(me: 'ME', title: 'Standup', part: 'TEXT', index: 0, count: 1, mode: TaskMode.meeting),
        'ME\nTitle: "Standup"\n\nTranscript:\n"""\nTEXT\n"""\n\nExtract the user\'s action items and summarize.');
    expect(partPrompt(me: 'ME', title: 'Notes', part: 'TEXT', index: 1, count: 3, mode: TaskMode.todo),
        'ME\nTitle: "Notes" (part 2 of 3)\n\nTranscript:\n"""\nTEXT\n"""\n\nExtract the user\'s to-dos and summarize.');
    expect(systemFor(TaskMode.meeting), contains('Lines labelled "Me" are the user'));
    expect(systemFor(TaskMode.todo), contains('to-do list'));
    expect(systemFor(TaskMode.meeting), isNot(contains('Priya')), reason: 'no example sentences (v2)');
  });

  test("the merge prompt is the desktop's", () {
    final p = mergePrompt(me: 'ME', title: 'Review', summaries: ['One.', 'Two.'], tasks: [
      {'description': 'Book the venue', 'assigned_by': 'Person 1', 'due': null, 'quote': 'book the venue'},
    ]);
    expect(
        p,
        startsWith('ME\nThese are partial results from consecutive parts of one recording ("Review").\n'
            'Partial summaries:\n- One.\n- Two.\n\nCandidate tasks (JSON):\n[\n  {\n    "description": "Book the venue",'));
    expect(
        p,
        endsWith('Write one combined summary and return the task list with duplicates merged. '
            'Keep every distinct task; do not add new ones.'));
    expect(kMergeSystem, 'You merge meeting notes. Output only the requested JSON.');
  });
}
