import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/speakers/voice_training.dart';

import '../theme.dart';
import '../wording.dart';

/// What you read aloud to train your voice.
const kTrainingPassage =
    "The quick brown fox jumps over the lazy dog. I'm teaching Voice Desk what my voice sounds like, so it can tell "
    "my lines from everyone else's. Tomorrow I will send the report, review the design, and call the team at three.";

/// The models training uses: the speech finder and the voice model.
const _trainingModels = [ModelId.vad, ModelId.speakers];

/// Settings → Your voice: a short reading, so your lines show as "Me".
class VoiceTrainingScreen extends ConsumerWidget {
  const VoiceTrainingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceTrainingProvider);
    final (voice, savedAt) = ref.watch(myVoiceProvider).value ?? (null, null);
    final vd = context.vd;
    final reading = s.phase == TrainingPhase.recording;
    // While the voice is worked out (a moment), Back waits: leaving would lose the reading.
    return PopScope(
      canPop: s.phase != TrainingPhase.working,
      child: Scaffold(
        appBar: AppBar(title: const Text('Your voice')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (reading) ..._reading(context, ref, s) else if (s.phase == TrainingPhase.working)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Text(voiceSavedText(voice == null ? null : savedAt), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Voice Desk learns your voice from a short reading, so your lines show as Me.',
                style: TextStyle(color: vd.muted),
              ),
              if (s.message != null) ...[
                const SizedBox(height: 16),
                Text(trainingMessageText(s), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              _TrainButton(label: voice == null ? 'Train my voice' : 'Re-train'),
              if (voice != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: () => _forget(context, ref), child: const Text('Forget my voice')),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _reading(BuildContext context, WidgetRef ref, TrainingState s) {
    final training = ref.read(voiceTrainingProvider.notifier);
    final vd = context.vd;
    final seconds = s.elapsed.inSeconds;
    return [
      const Text('Read this aloud in your normal voice:'),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(kTrainingPassage, style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.5)),
        ),
      ),
      const SizedBox(height: 16),
      LinearProgressIndicator(value: s.level),
      const SizedBox(height: 8),
      Text(
        '0:${seconds.toString().padLeft(2, '0')}',
        style: TextStyle(color: vd.muted, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          FilledButton(
            onPressed: s.canFinish ? training.done : null,
            child: Text(s.canFinish ? 'Done' : 'Keep reading…'),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: training.cancel, child: const Text('Cancel')),
        ],
      ),
    ];
  }

  Future<void> _forget(BuildContext context, WidgetRef ref) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget your voice?'),
        content: const Text(
          'Voice Desk deletes what it learned about your voice. Until you train it again, your lines show as Person 1, 2…',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Forget')),
        ],
      ),
    );
    if (yes == true) await ref.read(voiceTrainingProvider.notifier).forget();
  }
}

/// Starts the reading; the models it needs come first when they're missing.
class _TrainButton extends ConsumerWidget {
  const _TrainButton({required this.label});
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(modelsProvider);
    final models = ref.read(modelsProvider.notifier);
    final missing = [for (final id in _trainingModels) if (!models.isReady(id)) id];
    final downloading = missing.any((id) => states[id]?.phase == ModelPhase.downloading);
    final failed = [for (final id in missing) if (states[id]?.phase == ModelPhase.failed) states[id]!];
    final bytes = missing.fold(0, (sum, id) => sum + models.bytesToDownload(id));
    Future<void> train() async {
      for (final id in missing) {
        await models.download(id);
      }
      if (_trainingModels.every(models.isReady)) await ref.read(voiceTrainingProvider.notifier).start();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton(onPressed: downloading ? null : train, child: Text(label)),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 8),
          if (downloading)
            const LinearProgressIndicator()
          else if (failed.isNotEmpty)
            Text(modelFailureText(failed.first.message), style: TextStyle(color: Theme.of(context).colorScheme.error))
          else
            Text('Downloads ${megabytes(bytes)} MB first.', style: TextStyle(color: context.vd.muted)),
        ],
      ],
    );
  }
}
