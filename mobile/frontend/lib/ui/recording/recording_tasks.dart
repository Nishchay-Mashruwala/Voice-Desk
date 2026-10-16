import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/tasks_repository.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/speakers/voice_training.dart';
import 'package:mobile_backend/engine/tasks/task_mode.dart';
import 'package:mobile_backend/engine/tasks/task_settings.dart';

import '../settings/model_download.dart';
import '../tasks/task_row.dart';
import '../theme.dart';

/// A finished recording's "Summary" and "Your tasks" (with the Tasks tab's
/// row actions), "Find tasks", and how finding them is going.
class RecordingTasks extends ConsumerWidget {
  const RecordingTasks({super.key, required this.recording, required this.lines, required this.onWhere});

  final Recording recording;
  final List<Phrase> lines;
  final void Function(TaskItem task) onWhere;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = recording;
    if (r.status != RecordingStatus.done) return const SizedBox.shrink();
    final vd = context.vd;
    final hidden = ref.watch(pendingTaskDeletesProvider);
    final tasks = [
      for (final t in ref.watch(recordingTasksProvider(r.id)).value ?? const <TaskItem>[])
        if (!hidden.contains(t.id)) t,
    ];
    final trained = ref.watch(myVoiceProvider).value?.$1 != null;
    final finding = r.tasksStatus == TasksStatus.waiting || r.tasksStatus == TasksStatus.finding;
    // Strict: with no line said to be his, only what is said to him is found.
    final hint = lines.isNotEmpty && !trained && !hasMe(lines) && taskMode(lines, voiceTrained: trained) == TaskMode.meeting;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );

    Future<void> find() async {
      final model = await ref.read(chosenTaskModelProvider.future);
      if (!context.mounted) return;
      if (await askToDownload(context, ref.read(modelsProvider.notifier), model)) {
        await ref.read(processorProvider.notifier).findTasks(r.id);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r.summary case final summary? when r.tasksStatus != TasksStatus.none) ...[
            heading('Summary'),
            Text(summary),
            const SizedBox(height: 12),
            heading('Your tasks'),
            if (tasks.isEmpty)
              Text('No tasks for you in this recording.', style: TextStyle(color: vd.muted))
            else
              Card(child: Column(children: [for (final t in tasks) TaskRow(key: ValueKey(t.id), task: t, onWhere: onWhere)])),
            if (hint) ...[
              const SizedBox(height: 6),
              Text('Train your voice so your own promises are found too.', style: TextStyle(color: vd.muted)),
            ],
            const SizedBox(height: 8),
          ],
          if (finding)
            Row(
              children: [
                Icon(Icons.hourglass_top, size: 18, color: vd.muted),
                const SizedBox(width: 10),
                Text('Finding tasks…', style: TextStyle(color: vd.muted)),
              ],
            )
          else if (r.tasksStatus == TasksStatus.failed) ...[
            Text("Couldn't find tasks.", style: TextStyle(color: vd.muted)),
            Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: find, child: const Text('Try again'))),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: find,
                icon: const Icon(Icons.checklist, size: 18),
                label: const Text('Find tasks'),
              ),
            ),
        ],
      ),
    );
  }
}
