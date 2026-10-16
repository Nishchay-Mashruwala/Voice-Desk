import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

/// One task as the model wrote it.
@immutable
class FoundTask {
  const FoundTask({required this.description, this.assignedBy, this.due, this.quote});

  final String description;

  /// The speaker who asked, "Self" when the owner offered, or null.
  final String? assignedBy;

  /// The deadline as said ("by Friday"), or null.
  final String? due;

  /// The words it came from, or null.
  final String? quote;

  FoundTask withAssignedBy(String? by) => FoundTask(description: description, assignedBy: by, due: due, quote: quote);

  Map<String, Object?> toJson() => {'description': description, 'assigned_by': assignedBy, 'due': due, 'quote': quote};

  /// Throws [FormatException] when [json] isn't a task.
  factory FoundTask.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('a task is not an object');
    String? text(String key) {
      final v = json[key];
      if (v == null || v is String) return v as String?;
      throw FormatException('$key is not text');
    }

    return FoundTask(description: text('description') ?? '', assignedBy: text('assigned_by'), due: text('due'), quote: text('quote'));
  }

  @override
  bool operator ==(Object other) =>
      other is FoundTask &&
      other.description == description &&
      other.assignedBy == assignedBy &&
      other.due == due &&
      other.quote == quote;

  @override
  int get hashCode => Object.hash(description, assignedBy, due, quote);

  @override
  String toString() => 'FoundTask(${jsonEncode(toJson())})';
}

/// The model's answer: `{summary, tasks}` (task_grammar.dart).
@immutable
class TaskAnswer {
  const TaskAnswer(this.summary, this.tasks);
  final String summary;
  final List<FoundTask> tasks;

  /// Tasks without words are dropped (as the desktop). Throws
  /// [FormatException] for anything that isn't such an answer.
  factory TaskAnswer.parse(String json) {
    final v = jsonDecode(json);
    if (v is! Map || v['summary'] is! String || v['tasks'] is! List) {
      throw const FormatException('not a summary and tasks');
    }
    return TaskAnswer(v['summary'] as String, [
      for (final t in v['tasks'] as List)
        if (FoundTask.fromJson(t) case final task when task.description.trim().isNotEmpty) task,
    ]);
  }
}

/// Small models garble labels ("Speaker :1"): snapped back to the recording's
/// own [speakers]; "me" and "self" become "Self" (the desktop's clean-up).
List<FoundTask> snapLabels(List<FoundTask> tasks, Set<String> speakers) {
  String key(String s) => s.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').toLowerCase();
  final byKey = {for (final s in speakers) key(s): s};
  return [
    for (final t in tasks)
      switch (t.assignedBy) {
        null => t,
        final by when key(by) == 'me' || key(by) == 'self' => t.withAssignedBy('Self'),
        final by => t.withAssignedBy(byKey[key(by)] ?? by),
      },
  ];
}
