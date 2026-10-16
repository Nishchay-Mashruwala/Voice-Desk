import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/tasks_repository.dart';

import '../recording/recording_detail_screen.dart';
import '../theme.dart';
import 'task_row.dart';

/// "My tasks" (the desktop's, phone-sized): the open tasks in the owner's
/// order (drag to reorder), the completed ones behind "Show N completed", and
/// "Add a task…".
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final _add = TextEditingController();
  bool _showDone = false;

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _addTask(String text) async {
    if (text.trim().isEmpty) return;
    _add.clear();
    await ref.read(tasksRepositoryProvider).add(text.trim());
  }

  void _where(TaskItem t) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RecordingDetailScreen(recordingId: t.meetingId!, playFromMs: t.quoteMs ?? 0),
      ));

  @override
  Widget build(BuildContext context) {
    final vd = context.vd;
    final hidden = ref.watch(pendingTaskDeletesProvider);
    final all = [for (final t in ref.watch(tasksProvider).value ?? const <TaskItem>[]) if (!hidden.contains(t.id)) t];
    final open = [for (final t in all) if (!t.done) t];
    final done = [for (final t in all) if (t.done) t];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('My tasks', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        TextField(
          key: const Key('add-task'),
          controller: _add,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Add a task…', prefixIcon: Icon(Icons.add)),
          onSubmitted: _addTask,
        ),
        const SizedBox(height: 12),
        if (all.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: vd.border)),
            child: Column(
              children: [
                Icon(Icons.checklist, size: 32, color: vd.faint),
                const SizedBox(height: 10),
                Text(
                  'Tasks appear here after your recordings are processed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: vd.muted),
                ),
              ],
            ),
          ),
        if (open.isNotEmpty)
          Card(
            child: ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) {
                final ids = [for (final t in open) t.id];
                ids.insert(to, ids.removeAt(from));
                ref.read(tasksRepositoryProvider).reorder(ids);
              },
              children: [
                for (final (i, t) in open.indexed)
                  TaskRow(key: ValueKey(t.id), task: t, showRecording: true, dragIndex: i, onWhere: _where),
              ],
            ),
          ),
        if (done.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showDone = !_showDone),
              child: Text('${_showDone ? 'Hide' : 'Show'} ${done.length} completed'),
            ),
          ),
          if (_showDone)
            Card(
              child: Column(
                children: [for (final t in done) TaskRow(key: ValueKey(t.id), task: t, showRecording: true, onWhere: _where)],
              ),
            ),
        ],
      ],
    );
  }
}
