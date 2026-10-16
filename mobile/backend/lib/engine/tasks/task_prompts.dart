import 'dart:convert';

import '../../data/transcript.dart';
import '../speech/your_words.dart';
import 'task_mode.dart';

/// The desktop's rules (desktop/backend/core/src/llm.rs SYSTEM), without the
/// example sentences: the small models copied "Send the Q3 deck to Priya" and
/// "by Friday" into meetings where nobody said them (the 2026-10-15 comparison).
const kMeetingSystem = 'You are an assistant that reads meeting transcripts and extracts the action items '
    'that belong to ONE specific person (the user). Transcripts come from speech recognition and may contain '
    'errors. Lines labelled "Me" are the user; other labels are other participants. The conversation may mix '
    'English, Hindi and Gujarati; understand all of them, but always write the summary and tasks in English.\n'
    'Include a task only when:\n'
    '- someone asks or tells the user to do something (by name, or by talking to them directly), or\n'
    '- the user says they will do something.\n'
    'Do NOT include tasks that other people will do, general discussion, or things already done.\n'
    'For each task:\n'
    '- description: what the user has to do, as a short phrase starting with a verb, with the details said in '
    'the transcript.\n'
    '- assigned_by: the speaker who asked, "Self" if the user offered, or null if unclear.\n'
    "- due: the deadline in the transcript's own words, or null if none was said.\n"
    '- quote: the shortest exact excerpt of the transcript that shows the task.\n'
    'summary: 2-4 sentences on what the meeting covered and decided.\n'
    "If nothing is the user's to do, return an empty tasks array. Every task must come from the transcript.";

/// The desktop's own-notes rules (SYSTEM_SELF), without the example sentences.
const kTodoSystem = 'You are an assistant that turns what a person dictated to themselves into a to-do list. '
    'The text comes from speech recognition and may contain errors, and may mix English, Hindi and Gujarati; '
    'always write the summary and tasks in English. Lines labelled "Me" are the user.\n'
    'Extract every task, to-do, or reminder the user mentions for themselves.\n'
    'For each task:\n'
    '- description: what to do, as a short phrase starting with a verb, with the details said.\n'
    '- assigned_by: "Self".\n'
    "- due: when it should happen, in the user's own words, or null if not said.\n"
    '- quote: the shortest exact excerpt the task comes from.\n'
    'summary: one sentence describing what the user noted.\n'
    'If nothing is a task, return an empty tasks array. Every task must come from the text.';

const kMergeSystem = 'You merge meeting notes. Output only the requested JSON.';

String systemFor(TaskMode mode) => mode == TaskMode.meeting ? kMeetingSystem : kTodoSystem;

String _ask(TaskMode mode) =>
    mode == TaskMode.meeting ? "Extract the user's action items and summarize." : "Extract the user's to-dos and summarize.";

String _time(int ms) {
  final s = ms ~/ 1000;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// The transcript as the desktop gives it to the model (`format_transcript`):
/// `[mm:ss] Speaker: text`, one speaker's lines in a row joined; lines without
/// a speaker as `[mm:ss] text`.
String transcriptForAi(List<Phrase> lines) {
  final out = StringBuffer();
  Object? last = const Object();
  for (final l in lines) {
    if (l.speaker != last) {
      out.write('\n[${_time(l.startMs)}] ${l.speaker == null ? '' : '${l.speaker}: '}');
      last = l.speaker;
    } else {
      out.write(' ');
    }
    out.write(l.text);
  }
  return out.toString().trim();
}

/// The owner's name, then his other names.
List<String> ownerNames(YourWords w) => [
      if (w.name.trim().isNotEmpty) w.name.trim(),
      for (final a in w.aliases.split(','))
        if (a.trim().isNotEmpty) a.trim(),
    ];

/// The desktop's `who_am_i`.
String whoAmI(YourWords w) {
  final name = w.name.trim().isEmpty ? 'the user' : w.name.trim();
  final s = StringBuffer('The user\'s name is "$name".');
  if (w.aliases.trim().isNotEmpty) s.write(' People may also call them: ${w.aliases.trim()}.');
  s.write(' Lines labelled "Me" were spoken by the user.');
  return s.toString();
}

/// The user prompt for part [index] of [count] (the desktop's).
String partPrompt({
  required String me,
  required String title,
  required String part,
  required int index,
  required int count,
  required TaskMode mode,
}) {
  final which = count > 1 ? ' (part ${index + 1} of $count)' : '';
  return '$me\nTitle: "$title"$which\n\nTranscript:\n"""\n$part\n"""\n\n${_ask(mode)}';
}

/// The desktop's merge prompt, for several parts' answers.
String mergePrompt({
  required String me,
  required String title,
  required List<String> summaries,
  required List<Map<String, Object?>> tasks,
}) =>
    '$me\nThese are partial results from consecutive parts of one recording ("$title").\n'
    'Partial summaries:\n${summaries.map((s) => '- $s').join('\n')}\n\n'
    'Candidate tasks (JSON):\n${const JsonEncoder.withIndent('  ').convert(tasks)}\n\n'
    'Write one combined summary and return the task list with duplicates merged. '
    'Keep every distinct task; do not add new ones.';

/// Qwen3's chat template for one system and one user message, as
/// llama-server writes it with thinking off.
String chatPrompt(String system, String user) => '<|im_start|>system\n$system<|im_end|>\n'
    '<|im_start|>user\n$user<|im_end|>\n'
    '<|im_start|>assistant\n<think>\n\n</think>\n\n';
