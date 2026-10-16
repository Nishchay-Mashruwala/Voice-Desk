import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/tasks_repository.dart';

import '../theme.dart';

/// Tasks deleted on a screen, hidden while their Undo is offered.
final pendingTaskDeletesProvider = NotifierProvider<PendingTaskDeletes, Set<int>>(PendingTaskDeletes.new);

class PendingTaskDeletes extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  void add(int id) => state = {...state, id};
  void remove(int id) => state = {...state}..remove(id);
}

/// One task, as on the Tasks tab and a recording's screen: tick it, tap to
/// change its words and due date, and its menu (Copy, Where it was said,
/// Delete with Undo). [dragIndex]: its place in a reorderable list (a handle).
class TaskRow extends ConsumerWidget {
  const TaskRow({super.key, required this.task, this.showRecording = false, this.dragIndex, required this.onWhere});

  final TaskItem task;

  /// Says which recording it came from (on the Tasks tab).
  final bool showRecording;
  final int? dragIndex;

  /// "Where it was said": plays the recording from its line.
  final void Function(TaskItem task) onWhere;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vd = context.vd;
    final tasks = ref.read(tasksRepositoryProvider);
    final details = [
      ?task.due,
      if (task.assignedBy case final by? when by != 'Self') by,
      if (showRecording) ?task.meetingTitle,
    ];
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 4, right: 0),
      leading: Checkbox(
        key: Key('task-done-${task.id}'),
        value: task.done,
        onChanged: (v) => tasks.setDone(task.id, v ?? false),
      ),
      title: Text(
        task.description,
        style: task.done ? TextStyle(decoration: TextDecoration.lineThrough, color: vd.muted) : null,
      ),
      subtitle: details.isEmpty ? null : Text(details.join(' · '), style: TextStyle(color: vd.muted)),
      onTap: () => _edit(context, tasks),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            key: Key('task-menu-${task.id}'),
            tooltip: 'More',
            onSelected: (choice) async {
              switch (choice) {
                case 'copy':
                  await Clipboard.setData(ClipboardData(text: task.description));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task copied')));
                  }
                case 'where':
                  onWhere(task);
                case 'delete':
                  _delete(context, ref, tasks);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'copy', child: Text('Copy')),
              if (task.meetingId != null) const PopupMenuItem(value: 'where', child: Text('Where it was said')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
          if (dragIndex case final i?)
            ReorderableDragStartListener(
              index: i,
              child: Tooltip(
                message: 'Drag to reorder',
                child: Padding(
                  key: Key('task-drag-${task.id}'),
                  padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
                  child: Icon(Icons.drag_handle, color: vd.faint),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, TasksRepository tasks) async {
    final changed = await showDialog<(String, String)>(context: context, builder: (_) => _EditTaskDialog(task));
    if (changed == null) return;
    final (words, due) = changed;
    if (words.trim().isEmpty) return;
    await tasks.edit(task.id, description: words, due: due);
  }

  /// Hidden at once; deleted when the Undo time runs out (as recordings are).
  void _delete(BuildContext context, WidgetRef ref, TasksRepository tasks) {
    final pending = ref.read(pendingTaskDeletesProvider.notifier);
    pending.add(task.id);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: const Text('Task deleted'),
            duration: const Duration(seconds: 5),
            // With an action a SnackBar stays until tapped by default; it must time out for the delete to happen.
            persist: false,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => pending.remove(task.id),
            ),
          ),
        )
        .closed
        .then((reason) async {
          if (reason == SnackBarClosedReason.action) return;
          await tasks.delete(task.id);
          pending.remove(task.id);
        });
  }
}

/// Its words and "Due (e.g. Friday)".
class _EditTaskDialog extends StatefulWidget {
  const _EditTaskDialog(this.task);
  final TaskItem task;

  @override
  State<_EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<_EditTaskDialog> {
  late final _words = TextEditingController(text: widget.task.description);
  late final _due = TextEditingController(text: widget.task.due ?? '');

  @override
  void dispose() {
    _words.dispose();
    _due.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Task'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(key: const Key('task-words'), controller: _words, autofocus: true, maxLines: null),
        const SizedBox(height: 12),
        TextField(
          key: const Key('task-due'),
          controller: _due,
          decoration: const InputDecoration(labelText: 'Due (e.g. Friday)'),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, (_words.text, _due.text)), child: const Text('Save')),
    ],
  );
}
