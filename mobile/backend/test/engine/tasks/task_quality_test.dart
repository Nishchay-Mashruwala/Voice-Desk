import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/speech/your_words.dart';
import 'package:mobile_backend/engine/tasks/llm_engine.dart';
import 'package:mobile_backend/engine/tasks/task_answer.dart';
import 'package:mobile_backend/engine/tasks/task_finder.dart';

/// The task AI's quality gate (Plan 4): the phone's whole path (prompts,
/// parts by tokens, the merge, the quote check) with the real model, on the
/// 2026-10-15 comparison's cases and Plan 4's new ones, 3 seeds each. Needs:
/// - VOICEDESK_LLM_MODEL: the task model (Qwen3 1.7B or 4B, Q4_K_M);
/// - VOICEDESK_LLM_LIB: vd_llm.dll (mobile/native/llm/build_windows.ps1);
/// - VOICEDESK_TASK_CASES: the cases as JSON (outside the repository: two are
///   the owner's own meetings).
/// The 12 comparison cases must find 57/57 tasks with at most 5 of other
/// people's in 36 runs (1.7B with v2 and the quote check, measured in Python).
void main() {
  final model = Platform.environment['VOICEDESK_LLM_MODEL'];
  final lib = Platform.environment['VOICEDESK_LLM_LIB'];
  final casesFile = Platform.environment['VOICEDESK_TASK_CASES'];
  final skip = model == null || lib == null || casesFile == null
      ? 'set VOICEDESK_LLM_MODEL, VOICEDESK_LLM_LIB and VOICEDESK_TASK_CASES'
      : false;

  test('the comparison cases and the new ones', () async {
    final cases = jsonDecode(File(casesFile!).readAsStringSync()) as List;
    final engine = await LlamaEngine.start(File(model!), libraryPath: lib);
    addTearDown(engine.close);
    final totals = <bool, _Score>{false: _Score(), true: _Score()};
    final report = StringBuffer('| case | found | others\' | not asked | fully right | parts |\n|---|---|---|---|---|---|\n');
    for (final c in cases.cast<Map<String, dynamic>>()) {
      final score = _Score();
      final lines = [
        for (final s in (c['segments'] as List).cast<List>())
          Phrase(
            startMs: ((s[0] as num) * 1000).round(),
            endMs: ((s[0] as num) * 1000).round() + 1000,
            text: s[2] as String,
            words: const [],
            speaker: s[1] as String,
          ),
      ];
      final r = Recording(
        id: 1,
        title: c['title'] as String,
        kind: 'recording',
        startedAt: DateTime(2026, 10, 16),
        duration: Duration(milliseconds: lines.last.endMs),
        status: RecordingStatus.done,
      );
      final words = YourWords(name: c['user'] as String, aliases: c['aliases'] as String);
      var parts = 0;
      for (final seed in [1, 3, 5]) {
        final finder = TaskFinder(engine, words: words, voiceTrained: c['trained'] as bool, seed: seed);
        TaskStep step = TaskPart(0, '', 0);
        while (step is TaskPart) {
          parts = step.ofParts;
          step = await finder.next(r, lines, part: step.next, work: step.work);
        }
        score.add(c, [for (final (t, _) in (step as TaskDone).found) t]);
      }
      totals[c['new'] as bool]!.addAll(score);
      report.writeln('| ${c['name']} | ${score.found}/${score.want} | ${score.wrong} | ${score.extra} | ${score.perfect}/3 | $parts |');
    }
    final old = totals[false]!, fresh = totals[true]!;
    report
      ..writeln('| **comparison cases** | ${old.found}/${old.want} | ${old.wrong} | ${old.extra} | ${old.perfect}/${old.runs} | |')
      ..writeln('| **new cases** | ${fresh.found}/${fresh.want} | ${fresh.wrong} | ${fresh.extra} | ${fresh.perfect}/${fresh.runs} | |');
    // ignore: avoid_print
    print(report);
    expect(old.found, old.want, reason: 'every task of the comparison cases');
    expect(old.wrong, lessThanOrEqualTo(5), reason: "other people's tasks, in ${old.runs} runs");
  }, skip: skip, timeout: const Timeout(Duration(hours: 2)));
}

/// As the comparison's `score` (taskai/compare.py): wanted tasks found by
/// keyword, other people's tasks by keyword, the rest not asked for.
class _Score {
  int found = 0, want = 0, wrong = 0, extra = 0, perfect = 0, runs = 0;

  void add(Map<String, dynamic> c, List<FoundTask> tasks) {
    final descs = [for (final t in tasks) t.description.toLowerCase()];
    final used = <int>{};
    var hits = 0;
    final wanted = (c['want'] as List).cast<List>();
    for (final w in wanted) {
      final keys = (w[1] as List).cast<String>();
      final i = [for (var i = 0; i < descs.length; i++) i].where((i) => !used.contains(i) && keys.any(descs[i].contains)).firstOrNull;
      if (i == null) continue;
      used.add(i);
      hits++;
    }
    final not = (c['not_'] as List).cast<String>();
    final wrongHere = [for (var i = 0; i < descs.length; i++) if (not.any(descs[i].contains)) i];
    final extraHere = [for (var i = 0; i < descs.length; i++) if (!used.contains(i) && !wrongHere.contains(i)) i];
    final exact = c['exact'] as int?;
    found += hits;
    want += wanted.length;
    wrong += wrongHere.length;
    extra += extraHere.length;
    runs++;
    if (hits == wanted.length && wrongHere.isEmpty && extraHere.isEmpty && (exact == null || tasks.length == exact)) perfect++;
  }

  void addAll(_Score o) {
    found += o.found;
    want += o.want;
    wrong += o.wrong;
    extra += o.extra;
    perfect += o.perfect;
    runs += o.runs;
  }
}
