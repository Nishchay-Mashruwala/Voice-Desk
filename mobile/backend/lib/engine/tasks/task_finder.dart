import 'dart:convert';

import '../../data/recording.dart';
import '../../data/transcript.dart';
import '../speech/your_words.dart';
import 'llm_engine.dart';
import 'quote_check.dart';
import 'task_answer.dart';
import 'task_grammar.dart';
import 'task_mode.dart';
import 'task_parts.dart';
import 'task_prompts.dart';

/// Where finding a recording's tasks got to.
sealed class TaskStep {}

/// More to do: [next] is the part to run next (the merge once it equals
/// [ofParts]), [work] the answers so far, to save and carry on from.
class TaskPart extends TaskStep {
  TaskPart(this.next, this.work, this.ofParts);
  final int next;
  final String work;
  final int ofParts;
}

/// Finished: the summary, and the owner's tasks with where each quote starts.
class TaskDone extends TaskStep {
  TaskDone(this.summary, this.found);
  final String summary;
  final List<(FoundTask, int?)> found;
}

/// Finds a recording's summary and the owner's tasks, one part of its
/// transcript per [next], as the desktop's `extract` does in one go: so the
/// queue can save after each part and give way between them.
class TaskFinder {
  /// [seed]: the first answer's; a retry uses the next (tests vary it).
  TaskFinder(this._engine, {required this._words, required this._voiceTrained, this._seed = 1});

  final LlmEngine _engine;
  final YourWords _words;
  final bool _voiceTrained;
  final int _seed;

  /// Runs part [part] (or the merge, after the last), carrying on from [work]
  /// (`''` to start). Throws [LlmFailed] (`invalid_json` after a second try).
  Future<TaskStep> next(Recording r, List<Phrase> lines, {required int part, required String work}) async {
    final transcript = transcriptForAi(lines);
    if (transcript.trim().isEmpty) return TaskDone('No speech was detected.', const []);
    final parts = await transcriptParts(transcript, _engine.countTokens);
    final mode = taskMode(lines, voiceTrained: _voiceTrained);
    final me = whoAmI(_words);
    final so = _Work.parse(work);

    if (part < parts.length) {
      final a = await _ask(
          systemFor(mode), partPrompt(me: me, title: r.title, part: parts[part], index: part, count: parts.length, mode: mode));
      if (parts.length == 1) return _done(a.summary, a.tasks, lines, mode);
      final now = _Work([...so.summaries, a.summary], [...so.tasks, ...a.tasks]);
      return TaskPart(part + 1, now.encode(), parts.length);
    }
    // Several parts: merge the summaries and drop the overlaps' duplicates.
    final a = await _ask(kMergeSystem,
        mergePrompt(me: me, title: r.title, summaries: so.summaries, tasks: [for (final t in so.tasks) t.toJson()]));
    return _done(a.summary, a.tasks, lines, mode);
  }

  TaskDone _done(String summary, List<FoundTask> tasks, List<Phrase> lines, TaskMode mode) {
    final speakers = {for (final l in lines) ?l.speaker};
    final names = ownerNames(_words);
    return TaskDone(summary, [
      for (final t in snapLabels(tasks, speakers))
        // What he noted for himself is all his.
        if (mode == TaskMode.todo || keepTask(t, lines, ownerNames: names)) (t, quoteStartMs(t, lines)),
    ]);
  }

  /// The model's answer; invalid JSON is tried once more with another seed.
  Future<TaskAnswer> _ask(String system, String user) async {
    final prompt = chatPrompt(system, user);
    for (final seed in [_seed, _seed + 1]) {
      try {
        return TaskAnswer.parse(await _engine.generate(prompt: prompt, grammar: kTaskGrammar, seed: seed));
      } on FormatException {
        // Cut off at the answer's length, or not the schema: once more.
      }
    }
    throw const LlmFailed('invalid_json');
  }
}

/// The parts' answers so far, saved between parts (`meetings.tasksWork`).
class _Work {
  const _Work(this.summaries, this.tasks);
  final List<String> summaries;
  final List<FoundTask> tasks;

  factory _Work.parse(String work) {
    if (work.isEmpty) return const _Work([], []);
    final v = jsonDecode(work) as Map<String, dynamic>;
    return _Work([for (final s in v['summaries'] as List) s as String], [for (final t in v['tasks'] as List) FoundTask.fromJson(t)]);
  }

  String encode() => jsonEncode({'summaries': summaries, 'tasks': [for (final t in tasks) t.toJson()]});
}
