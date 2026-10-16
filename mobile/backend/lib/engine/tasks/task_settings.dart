import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../models/catalogue.dart';
import '../speech/speech_setup.dart';

const kFindTasksKey = 'find_tasks';
const kTaskAiKey = 'task_ai';

/// Settings → Processing → "Task AI": "Faster" (Qwen3 1.7B) or "More
/// accurate" (4B, offered on phones with 8 GB).
enum TaskAi { faster, accurate }

@immutable
class TaskSettings {
  const TaskSettings({this.findTasks = true, this.ai = TaskAi.faster});

  /// "Find tasks": a summary and the owner's tasks after each recording.
  final bool findTasks;
  final TaskAi ai;

  TaskSettings copyWith({bool? findTasks, TaskAi? ai}) =>
      TaskSettings(findTasks: findTasks ?? this.findTasks, ai: ai ?? this.ai);
}

final taskSettingsProvider = AsyncNotifierProvider<TaskSettingsNotifier, TaskSettings>(TaskSettingsNotifier.new);

class TaskSettingsNotifier extends AsyncNotifier<TaskSettings> {
  @override
  Future<TaskSettings> build() async {
    final settings = ref.read(settingsRepositoryProvider);
    final ai = await settings.getString(kTaskAiKey, orElse: TaskAi.faster.name);
    return TaskSettings(
      findTasks: await settings.getBool(kFindTasksKey, orElse: true),
      ai: TaskAi.values.firstWhere((a) => a.name == ai, orElse: () => TaskAi.faster),
    );
  }

  Future<void> setFindTasks(bool on) async {
    final now = await future;
    await ref.read(settingsRepositoryProvider).setBool(kFindTasksKey, on);
    state = AsyncData(now.copyWith(findTasks: on));
  }

  Future<void> setAi(TaskAi ai) async {
    final now = await future;
    await ref.read(settingsRepositoryProvider).setString(kTaskAiKey, ai.name);
    state = AsyncData(now.copyWith(ai: ai));
  }
}

/// The task model chosen: the 4B only when chosen and the phone has the
/// memory for it (a choice kept from another phone, or a backup, falls back to
/// the 1.7B). A recording's Find tasks uses it even while Find tasks is off.
final chosenTaskModelProvider = FutureProvider<ModelId>((ref) async {
  final s = await ref.watch(taskSettingsProvider.future);
  final big = (await ref.watch(phoneClassProvider.future)).canRunLargeTaskAi;
  return s.ai == TaskAi.accurate && big ? ModelId.taskAccurate : ModelId.taskFaster;
});

/// The task model new recordings need: null while Find tasks is off.
final taskModelProvider = FutureProvider<ModelId?>((ref) async {
  final s = await ref.watch(taskSettingsProvider.future);
  return s.findTasks ? ref.watch(chosenTaskModelProvider.future) : null;
});
