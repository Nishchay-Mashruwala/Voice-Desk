import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/pipeline/speed_book.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/tasks/task_settings.dart';

import '../theme.dart';
import '../wording.dart';
import 'model_download.dart';

/// How much longer a 30-minute recording takes with its tasks, on this phone.
final _tasksEstimateProvider = FutureProvider.family<Duration, TaskAi>(
  (ref, ai) => ref.read(speedBookProvider).estimateTasks(ai, const Duration(minutes: 30)),
);

/// Settings → Processing: "Find tasks", and on phones with 8 GB, which task
/// model ("Task AI": Faster or More accurate).
class TasksCard extends ConsumerWidget {
  const TasksCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(taskSettingsProvider).value ?? const TaskSettings();
    final big = ref.watch(phoneClassProvider).value?.canRunLargeTaskAi ?? false;
    final notifier = ref.read(taskSettingsProvider.notifier);
    final models = ref.read(modelsProvider.notifier);
    final muted = TextStyle(color: context.vd.muted);
    ModelId model(TaskAi a) => a == TaskAi.accurate && big ? ModelId.taskAccurate : ModelId.taskFaster;

    Future<void> findTasks(bool on) async {
      if (!on) return notifier.setFindTasks(false);
      if (await askToDownload(context, models, model(settings.ai))) await notifier.setFindTasks(true);
    }

    Future<void> choose(TaskAi? a) async {
      if (a == null || a == settings.ai) return;
      if (await askToDownload(context, models, model(a))) await notifier.setAi(a);
    }

    return Column(
      children: [
        SwitchListTile(
          title: const Text('Find tasks'),
          subtitle: Text('A summary and your tasks, after each recording', style: muted),
          value: settings.findTasks,
          onChanged: findTasks,
        ),
        if (settings.findTasks)
          if (ref.watch(_tasksEstimateProvider(big ? settings.ai : TaskAi.faster)).value case final d?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('About ${(d.inSeconds / 60).ceil()} min more for a 30-minute recording', style: muted),
              ),
            ),
        if (big && settings.findTasks) ...[
          const Divider(height: 1),
          ListTile(title: const Text('Task AI')),
          RadioGroup<TaskAi>(
            groupValue: settings.ai,
            onChanged: choose,
            child: Column(
              children: [
                for (final a in TaskAi.values)
                  RadioListTile<TaskAi>(
                    value: a,
                    title: Text(taskAiName(a)),
                    subtitle: Text('${megabytes(kCatalogue[model(a)]!.download.size)} MB', style: muted),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
