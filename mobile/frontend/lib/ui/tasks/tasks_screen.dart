import 'package:flutter/material.dart';

import '../theme.dart';

/// All tasks. Empty until processing finds tasks (a later plan).
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vd = context.vd;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('Tasks', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: vd.border),
          ),
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
      ],
    );
  }
}
