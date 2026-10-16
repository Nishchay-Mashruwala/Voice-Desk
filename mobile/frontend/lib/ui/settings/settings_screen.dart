import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:mobile_backend/engine/permissions.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/speech/your_words.dart';

import '../theme.dart';
import 'credits_screen.dart';
import 'speech_card.dart';
import 'storage_screen.dart';
import 'tasks_card.dart';
import 'people_screen.dart';

final appVersionProvider = FutureProvider<String>((ref) async => (await PackageInfo.fromPlatform()).version);

/// Settings: permissions for now (more sections come with later plans).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

const _labels = {
  'microphone': 'Microphone',
  'notifications': 'Notifications',
  'battery_unrestricted': 'Run unrestricted in the background',
};

class _SettingsScreenState extends ConsumerState<SettingsScreen> with WidgetsBindingObserver {
  Map<String, bool>? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from Android's settings: look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final status = await ref.read(permissionsProvider).check();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _allow(String id) async {
    await ref.read(permissionsProvider).request(id);
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(appVersionProvider).value;
    final status = _status;
    final vd = context.vd;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w700, color: vd.muted),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        heading('You and your words'),
        const Card(child: _YourWordsCard()),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            title: const Text('People'),
            subtitle: Text('Your voice, and the voices recognised in recordings', style: TextStyle(color: vd.muted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PeopleScreen())),
          ),
        ),
        heading('Permissions'),
        Card(
          child: Column(
            children: [
              if (status != null)
                for (final e in _labels.entries)
                  ListTile(
                    title: Text(e.value),
                    trailing: status[e.key] == true
                        ? Text(
                            'Allowed',
                            style: TextStyle(color: VdColors.ok, fontWeight: FontWeight.w600),
                          )
                        : FilledButton.tonal(onPressed: () => _allow(e.key), child: const Text('Allow')),
                  ),
            ],
          ),
        ),
        heading('Speech'),
        const Card(child: SpeechCard()),
        heading('Storage'),
        Card(
          child: ListTile(
            title: const Text('Storage'),
            subtitle: Text('Recordings, models and free space', style: TextStyle(color: vd.muted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StorageScreen())),
          ),
        ),
        heading('Processing'),
        Card(
          child: SwitchListTile(
            title: const Text('Only process while charging'),
            subtitle: Text('Recordings wait until the phone is plugged in.', style: TextStyle(color: vd.muted)),
            value: ref.watch(onlyWhileChargingProvider).value ?? false,
            onChanged: (on) => ref.read(onlyWhileChargingProvider.notifier).set(on),
          ),
        ),
        const SizedBox(height: 8),
        const Card(child: TasksCard()),
        heading('About'),
        Card(
          child: ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: VdColors.grad),
              child: const Icon(Icons.mic, color: Colors.white, size: 20),
            ),
            title: Text(version == null ? 'Voice Desk' : 'Voice Desk $version'),
            subtitle: Text('Everything stays on this phone.', style: TextStyle(color: vd.muted)),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Licences & credits'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreditsScreen())),
          ),
        ),
      ],
    );
  }
}

/// Your name, vocabulary and Leave out (as on the desktop), each saved when
/// you leave its field; they apply to transcripts made from now on.
class _YourWordsCard extends ConsumerStatefulWidget {
  const _YourWordsCard();

  @override
  ConsumerState<_YourWordsCard> createState() => _YourWordsCardState();
}

class _YourWordsCardState extends ConsumerState<_YourWordsCard> {
  final _name = TextEditingController();
  final _aliases = TextEditingController();
  final _vocabulary = TextEditingController();
  final _leaveOut = TextEditingController();
  YourWords? _saved;

  @override
  void dispose() {
    _name.dispose();
    _aliases.dispose();
    _vocabulary.dispose();
    _leaveOut.dispose();
    super.dispose();
  }

  void _save() {
    final saved = _saved;
    if (saved == null) return;
    final now = YourWords(
      name: _name.text.trim(),
      aliases: _aliases.text.trim(),
      vocabulary: _vocabulary.text.trim(),
      leaveOut: _leaveOut.text.trim(),
    );
    if (now == saved) return;
    _saved = now;
    ref
        .read(yourWordsProvider.notifier)
        .set(
          name: now.name == saved.name ? null : now.name,
          aliases: now.aliases == saved.aliases ? null : now.aliases,
          vocabulary: now.vocabulary == saved.vocabulary ? null : now.vocabulary,
          leaveOut: now.leaveOut == saved.leaveOut ? null : now.leaveOut,
        );
  }

  Widget _field(Key key, TextEditingController controller, String label, String hint, {int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Focus(
      onFocusChange: (focused) => focused ? null : _save(),
      child: TextField(
        key: key,
        controller: controller,
        minLines: 1,
        maxLines: maxLines,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onSubmitted: (_) => _save(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final words = ref.watch(yourWordsProvider).value;
    if (words != null && _saved == null) {
      _saved = words;
      _name.text = words.name;
      _aliases.text = words.aliases;
      _vocabulary.text = words.vocabulary;
      _leaveOut.text = words.leaveOut;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(const Key('your-name'), _name, 'Your name', 'Nishchay'),
          _field(
            const Key('your-aliases'),
            _aliases,
            'Other names people call you',
            'Nicknames or spellings, comma separated.',
          ),
          _field(
            const Key('your-vocabulary'),
            _vocabulary,
            'Vocabulary',
            'Names and words to get right: Priya, Voice Desk',
            maxLines: 3,
          ),
          _field(
            const Key('your-leave-out'),
            _leaveOut,
            'Leave out',
            'Words never written: umm, uh, the the',
            maxLines: 3,
          ),
          Text('Used for recordings made from now on.', style: TextStyle(color: context.vd.muted, fontSize: 12.5)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
