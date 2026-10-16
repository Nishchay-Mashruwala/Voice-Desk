import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/permissions.dart';
import 'package:mobile_backend/engine/setup_flag.dart';
import 'package:mobile_backend/engine/speakers/voice_training.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/speech/your_words.dart';

import '../settings/voice_training_screen.dart';
import '../theme.dart';
import '../widgets/badge.dart';
import '../widgets/orb.dart';
import '../wording.dart';

/// The first start, once, before the tabs: welcome, permissions, about you,
/// your voice, the downloads. On a phone already in use it comes filled in.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

const _steps = 5;

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _pages = PageController();
  final _name = TextEditingController();
  final _aliases = TextEditingController();
  YourWords? _words;
  int _step = 0;

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    _aliases.dispose();
    super.dispose();
  }

  Future<void> _go(int step) async {
    if (_step == 2) await _saveAboutYou();
    setState(() => _step = step);
    await _pages.animateToPage(step, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _saveAboutYou() async {
    final was = _words;
    if (was == null) return;
    final name = _name.text.trim(), aliases = _aliases.text.trim();
    if (name == was.name && aliases == was.aliases) return;
    _words = YourWords(name: name, aliases: aliases, vocabulary: was.vocabulary, leaveOut: was.leaveOut);
    await ref
        .read(yourWordsProvider.notifier)
        .set(name: name == was.name ? null : name, aliases: aliases == was.aliases ? null : aliases);
  }

  @override
  Widget build(BuildContext context) {
    final words = ref.watch(yourWordsProvider).value;
    if (words != null && _words == null) {
      _words = words;
      _name.text = words.name;
      _aliases.text = words.aliases;
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Welcome(onStart: () => _go(1)),
                  const _Permissions(),
                  _AboutYou(name: _name, aliases: _aliases),
                  _YourVoice(onSkip: () => _go(4)),
                  const _Download(),
                ],
              ),
            ),
            if (_step > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    TextButton(onPressed: () => _go(_step - 1), child: const Text('Back')),
                    const Spacer(),
                    if (_step < _steps - 1) FilledButton(onPressed: () => _go(_step + 1), child: const Text('Next')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A step's page: a heading, then its content, scrolling if need be.
class _Step extends StatelessWidget {
  const _Step({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      ...children,
    ],
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Orb(state: OrbState.idle, onPressed: onStart, size: 110),
        const SizedBox(height: 32),
        Text('Speak, and it writes.', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(
          'Voice Desk records your meetings and turns them into text — all on this phone, even offline.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.vd.muted),
        ),
        const SizedBox(height: 32),
        FilledButton(onPressed: onStart, child: const Text('Get started')),
      ],
    ),
  );
}

class _Permissions extends ConsumerStatefulWidget {
  const _Permissions();

  @override
  ConsumerState<_Permissions> createState() => _PermissionsState();
}

class _PermissionsState extends ConsumerState<_Permissions> with WidgetsBindingObserver {
  static const _why = {
    'microphone': ('Microphone', 'to record'),
    'notifications': ('Notifications', 'to show and stop a recording'),
    'battery_unrestricted': ('Unrestricted battery', "so Android doesn't stop a long recording"),
  };
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

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return _Step(
      title: 'Permissions',
      children: [
        if (status != null)
          Card(
            child: Column(
              children: [
                for (final MapEntry(key: id, value: (name, why)) in _why.entries)
                  ListTile(
                    title: Text(name),
                    subtitle: Text(why, style: TextStyle(color: context.vd.muted)),
                    trailing: status[id] == true
                        ? Text('Allowed', style: TextStyle(color: VdColors.ok, fontWeight: FontWeight.w600))
                        : FilledButton.tonal(
                            onPressed: () async {
                              await ref.read(permissionsProvider).request(id);
                              await _check();
                            },
                            child: const Text('Allow'),
                          ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text('Anything not allowed now is asked again when it is needed.', style: TextStyle(color: context.vd.muted)),
      ],
    );
  }
}

class _AboutYou extends ConsumerWidget {
  const _AboutYou({required this.name, required this.aliases});
  final TextEditingController name;
  final TextEditingController aliases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(speechSettingsProvider).value ?? const SpeechSettings();
    final speech = ref.read(speechSettingsProvider.notifier);
    final muted = TextStyle(color: context.vd.muted);
    return _Step(
      title: 'About you',
      children: [
        TextField(
          key: const Key('setup-name'),
          controller: name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'e.g. Nishchay',
            helperText: 'How people say your name in meetings.',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('setup-aliases'),
          controller: aliases,
          decoration: const InputDecoration(
            labelText: 'Other names people call you',
            hintText: 'Nicknames or spellings, comma separated.',
          ),
        ),
        const SizedBox(height: 24),
        const Text('Languages you speak', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final l in Lang.values)
              FilterChip(
                label: Text(languageName(l)),
                selected: settings.languages.contains(l),
                onSelected: (on) {
                  final now = {...settings.languages};
                  on ? now.add(l) : now.remove(l);
                  if (now.isNotEmpty) speech.setLanguages(now);
                },
              ),
          ],
        ),
        Text('Their speech models download at the last step.', style: muted),
        if (settings.languages.containsAll({Lang.hi, Lang.gu})) ...[
          const SizedBox(height: 16),
          const Text('Hindi or Gujarati — which do you speak more?', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          SegmentedButton<Lang>(
            segments: const [
              ButtonSegment(value: Lang.hi, label: Text('Hindi')),
              ButtonSegment(value: Lang.gu, label: Text('Gujarati')),
            ],
            selected: {settings.prefer},
            onSelectionChanged: (s) => speech.setPrefer(s.single),
          ),
        ],
      ],
    );
  }
}

class _YourVoice extends ConsumerWidget {
  const _YourVoice({required this.onSkip});
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (voice, savedAt) = ref.watch(myVoiceProvider).value ?? (null, null);
    return _Step(
      title: 'Your voice',
      children: [
        Text(
          'Voice Desk learns your voice from a short reading, so your lines show as Me. You can do this later in Settings.',
          style: TextStyle(color: context.vd.muted),
        ),
        const SizedBox(height: 16),
        if (voice != null) ...[
          Text(voiceSavedText(savedAt), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VoiceTrainingScreen())),
              child: Text(voice == null ? 'Train my voice' : 'Re-train'),
            ),
            const SizedBox(width: 12),
            if (voice == null) TextButton(onPressed: onSkip, child: const Text('Skip')),
          ],
        ),
      ],
    );
  }
}

class _Download extends ConsumerWidget {
  const _Download();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(modelsProvider);
    final models = ref.read(modelsProvider.notifier);
    final ids = ref.watch(neededModelIdsProvider);
    final needed = ref.watch(neededModelsProvider);
    final missing = [for (final id in ids) if (!models.isReady(id)) id];
    final total = missing.fold(0, (sum, id) => sum + models.bytesToDownload(id));
    final muted = TextStyle(color: context.vd.muted);
    void done() => ref.read(setupDoneProvider.notifier).finish();
    return _Step(
      title: 'Download',
      children: [
        if (missing.isNotEmpty || needed.phase != ModelPhase.ready) ...[
          Card(
            child: Column(
              children: [
                for (final id in ids)
                  if (id != ModelId.indicTokens)
                    ListTile(
                      dense: true,
                      title: Text(modelName(id)),
                      trailing: models.isReady(id)
                          ? const VdBadge('Downloaded', kind: BadgeKind.ok)
                          : Text('${megabytes(models.bytesToDownload(id))} MB'),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text("Wi-Fi recommended. If it's interrupted, it continues where it stopped.", style: muted),
          const SizedBox(height: 16),
          if (needed.phase == ModelPhase.downloading) ...[
            LinearProgressIndicator(value: needed.total == 0 ? null : needed.done / needed.total),
            const SizedBox(height: 8),
            Text(speechModelsText(needed), style: muted),
          ] else ...[
            if (needed.phase == ModelPhase.failed) ...[
              Text(speechModelsText(needed)),
              const SizedBox(height: 8),
            ],
            FilledButton(onPressed: models.downloadNeeded, child: Text('Download (${megabytes(total)} MB)')),
          ],
          const SizedBox(height: 12),
          TextButton(onPressed: done, child: const Text('Use the app while it downloads')),
        ] else ...[
          Card(
            child: Column(
              children: [
                for (final id in ids)
                  if (id != ModelId.indicTokens)
                    ListTile(
                      dense: true,
                      title: Text(modelName(id)),
                      trailing: const VdBadge('Downloaded', kind: BadgeKind.ok),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Voice Desk is ready — it works offline from now on.'),
          const SizedBox(height: 16),
          FilledButton(onPressed: done, child: const Text('Start')),
        ],
      ],
    );
  }
}
