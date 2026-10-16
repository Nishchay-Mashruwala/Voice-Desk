import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/engine/speech/your_words.dart';
import 'package:mobile_backend/engine/tasks/llm_engine.dart';
import 'package:mobile_backend/engine/tasks/task_answer.dart';
import 'package:mobile_backend/engine/tasks/task_finder.dart';
import 'package:mobile_backend/engine/tasks/task_grammar.dart';
import 'package:mobile_backend/engine/tasks/task_mode.dart';
import 'package:mobile_backend/engine/tasks/task_prompts.dart';

import 'lines.dart';

/// A task model that answers from a list, one token per 4 characters.
class FakeLlm implements LlmEngine {
  FakeLlm(this.answers);
  final List<String> answers;
  final prompts = <String>[];
  final seeds = <int>[];

  @override
  Future<int> countTokens(String text) async => (text.length / 4).ceil();

  @override
  Future<String> generate({
    required String prompt,
    required String grammar,
    int maxTokens = 1536,
    double temperature = 0.1,
    int seed = 1,
  }) async {
    expect(grammar, kTaskGrammar);
    expect((maxTokens, temperature), (1536, 0.1));
    prompts.add(prompt);
    seeds.add(seed);
    return answers.removeAt(0);
  }

  @override
  void stop() {}

  @override
  Future<void> close() async {}
}

String answer(String summary, List<Map<String, Object?>> tasks) => jsonEncode({'summary': summary, 'tasks': tasks});

Map<String, Object?> task(String description, String quote, {String? by = 'Person 1'}) =>
    {'description': description, 'assigned_by': by, 'due': null, 'quote': quote};

void main() {
  const words = YourWords(name: 'Nishchay');
  final r = Recording(
    id: 1,
    title: 'Weekly review',
    kind: 'recording',
    startedAt: DateTime(2026, 10, 16),
    duration: const Duration(minutes: 1),
    status: RecordingStatus.done,
  );
  final lines = [
    line(0, 'Person 1', 'Nishchay, can you send the report by Friday?'),
    line(5, 'Me', 'Sure.'),
    line(9, 'Person 1', 'Priya, please update the slide.'),
  ];

  test('one part: the answer, checked and snapped', () async {
    final llm = FakeLlm([
      answer('A review.', [
        task('Send the report', 'Nishchay, can you send the report by Friday?', by: 'person 1'),
        task('Update the slide', 'Priya, please update the slide.'),
      ]),
    ]);
    final step = await TaskFinder(llm, words: words, voiceTrained: true).next(r, lines, part: 0, work: '');
    final done = step as TaskDone;
    expect(done.summary, 'A review.');
    expect(done.found, [(const FoundTask(description: 'Send the report', assignedBy: 'Person 1', quote: 'Nishchay, can you send the report by Friday?'), 0)]);
    expect(llm.prompts.single, chatPrompt(kMeetingSystem, partPrompt(
        me: whoAmI(words), title: 'Weekly review', part: transcriptForAi(lines), index: 0, count: 1, mode: TaskMode.meeting)));
  });

  test('three parts then one merge', () async {
    // About 250 tokens a line: three parts of 3,000.
    final long = [
      for (var i = 0; i < 30; i++)
        line(i * 10.0, i.isEven ? 'Person 1' : 'Me', '${i.isEven ? 'Nishchay, line' : 'Line'} $i ${'word ' * 200}'),
    ];
    final llm = FakeLlm([
      answer('Part one.', [task('Book the venue', 'Nishchay, line 0')]),
      answer('Part two.', []),
      answer('Part three.', [task('Write the plan', 'Nishchay, line 28')]),
      answer('The whole meeting.', [task('Book the venue', 'Nishchay, line 0'), task('Write the plan', 'Nishchay, line 28')]),
    ]);
    final finder = TaskFinder(llm, words: words, voiceTrained: true);
    TaskStep step = TaskPart(0, '', 0);
    final seen = <int>[];
    while (step is TaskPart) {
      seen.add(step.next);
      step = await finder.next(r, long, part: step.next, work: step.work);
    }
    expect(llm.prompts, hasLength(4));
    final parts = (llm.prompts.length - 1);
    expect(seen, [for (var i = 0; i <= parts; i++) i], reason: 'one call per part, then the merge');
    expect(llm.prompts[1], contains('(part 2 of 3)'));
    expect(llm.prompts.last, startsWith(chatPrompt(kMergeSystem, '').substring(0, 40)));
    expect(llm.prompts.last, contains('- Part one.\n- Part two.\n- Part three.'));
    expect(llm.prompts.last, contains('"description": "Write the plan"'));
    final done = step as TaskDone;
    expect(done.summary, 'The whole meeting.');
    expect([for (final (t, ms) in done.found) (t.description, ms)], [('Book the venue', 0), ('Write the plan', 280000)]);
  });

  test('the work so far is carried in the step', () async {
    final long = [for (var i = 0; i < 30; i++) line(i * 10.0, i.isEven ? 'Person 1' : 'Me', 'Line $i ${'word ' * 200}')];
    final first = FakeLlm([answer('Part one.', [task('Book the venue', 'Line 1', by: 'Self')])]);
    final step = await TaskFinder(first, words: words, voiceTrained: true).next(r, long, part: 0, work: '') as TaskPart;
    expect((step.next, step.ofParts), (1, 3));
    // The app was killed; a new finder carries on from the next part.
    final second = FakeLlm([
      answer('Part two.', []),
      answer('Part three.', []),
      answer('All.', [task('Book the venue', 'Line 1', by: 'Self')]),
    ]);
    final finder = TaskFinder(second, words: words, voiceTrained: true);
    final s2 = await finder.next(r, long, part: step.next, work: step.work) as TaskPart;
    final s3 = await finder.next(r, long, part: s2.next, work: s2.work) as TaskPart;
    final done = await finder.next(r, long, part: s3.next, work: s3.work) as TaskDone;
    expect(second.prompts.last, contains('- Part one.\n- Part two.\n- Part three.'));
    expect(second.prompts.last, contains('Book the venue'));
    expect(done.found.single.$1.description, 'Book the venue');
  });

  test('invalid JSON is tried once more, then fails', () async {
    final once = FakeLlm(['{"summary": "cut', answer('Fine.', [])]);
    final ok = await TaskFinder(once, words: words, voiceTrained: true).next(r, lines, part: 0, work: '') as TaskDone;
    expect(ok.summary, 'Fine.');
    expect(once.seeds, [1, 2]);
    final twice = FakeLlm(['{"summary": "cut', '[]']);
    await expectLater(TaskFinder(twice, words: words, voiceTrained: true).next(r, lines, part: 0, work: ''),
        throwsA(isA<LlmFailed>().having((f) => f.reason, 'reason', 'invalid_json')));
  });

  test('a to-do list uses the own-notes prompt, and keeps every to-do', () async {
    final notes = [line(0, 'Person 1', 'I need to call the bank.'), line(4, 'Person 1', 'And buy milk.')];
    final llm = FakeLlm([answer('Notes.', [task('Call the bank', 'call the bank', by: 'Self'), task('Buy milk', 'buy milk', by: 'Self')])]);
    final done = await TaskFinder(llm, words: words, voiceTrained: false).next(r, notes, part: 0, work: '') as TaskDone;
    expect(llm.prompts.single, startsWith('<|im_start|>system\n$kTodoSystem'));
    expect(llm.prompts.single, contains("Extract the user's to-dos and summarize."));
    expect(done.found, hasLength(2), reason: 'no quote check on what he noted for himself');
  });

  test("no speech gives the desktop's summary", () async {
    final llm = FakeLlm([]);
    final done = await TaskFinder(llm, words: words, voiceTrained: true).next(r, const [], part: 0, work: '') as TaskDone;
    expect(done.summary, 'No speech was detected.');
    expect(done.found, isEmpty);
    expect(llm.prompts, isEmpty);
  });
}
