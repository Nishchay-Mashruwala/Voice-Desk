import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/speakers_repository.dart';
import 'package:mobile_backend/engine/speakers/grouping.dart';
import 'package:mobile_backend/engine/speakers/voice_training.dart';

import '../theme.dart';
import '../wording.dart';
import 'voice_training_screen.dart';

/// Settings → People: your voice, then the people whose voices are recognised
/// in new recordings (rename or forget them).
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (voice, savedAt) = ref.watch(myVoiceProvider).value ?? (null, null);
    final people = ref.watch(peopleProvider).value ?? const <RememberedPerson>[];
    final vd = context.vd;
    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Card(
            child: ListTile(
              title: const Text('Your voice'),
              subtitle: Text(voiceSavedText(voice == null ? null : savedAt), style: TextStyle(color: vd.muted)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VoiceTrainingScreen())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
            child: Text(
              'Recognised in new recordings',
              style: TextStyle(fontWeight: FontWeight.w700, color: vd.muted),
            ),
          ),
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'No one yet. Tap a speaker’s name in a recording, rename them and tick '
                '“Recognise this voice in future recordings”.',
                style: TextStyle(color: vd.muted),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final p in people)
                    ListTile(
                      title: Text(p.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            key: Key('rename-${p.id}'),
                            onPressed: () => _rename(context, ref, p),
                            child: const Text('Rename'),
                          ),
                          TextButton(
                            key: Key('forget-${p.id}'),
                            onPressed: () => _forget(context, ref, p),
                            child: const Text('Forget'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, RememberedPerson p) async {
    final name = await showDialog<String>(context: context, builder: (_) => _RenamePersonDialog(p.name));
    if (name == null || name == p.name) return;
    await ref.read(speakersRepositoryProvider).renamePerson(p.id, name);
  }

  Future<void> _forget(BuildContext context, WidgetRef ref, RememberedPerson p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Forget ${p.name}'s voice?"),
        content: const Text('Their name stays on past recordings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Forget')),
        ],
      ),
    );
    if (yes == true) await ref.read(speakersRepositoryProvider).forgetPerson(p.id);
  }
}

/// "Rename Asha to": the name in a box ("Type a name" when empty).
class _RenamePersonDialog extends StatefulWidget {
  const _RenamePersonDialog(this.name);
  final String name;

  @override
  State<_RenamePersonDialog> createState() => _RenamePersonDialogState();
}

class _RenamePersonDialogState extends State<_RenamePersonDialog> {
  late final _text = TextEditingController(text: widget.name);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() {
    final name = _text.text.trim();
    if (name.isEmpty || name.toLowerCase() == kMeLabel.toLowerCase()) return setState(() => _error = 'Type a name');
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Rename ${widget.name} to'),
    content: TextField(
      key: const Key('person-name'),
      controller: _text,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(hintText: 'Their name', errorText: _error),
      onSubmitted: (_) => _done(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _done, child: const Text('Rename')),
    ],
  );
}

