import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mobile_backend/engine/models/speech_model.dart';

import '../theme.dart';
import '../wording.dart';

/// Shown until the speech model is on the phone: download it, its progress, or why it failed.
class SpeechModelBanner extends ConsumerWidget {
  const SpeechModelBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(speechModelProvider);
    if (model.phase == SpeechModelPhase.ready) return const SizedBox.shrink();
    final vd = context.vd;
    final download = ref.read(speechModelProvider.notifier).download;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.text_snippet_outlined, color: vd.accent),
                const SizedBox(width: 10),
                Expanded(child: Text(speechModelText(model))),
              ],
            ),
            if (model.phase == SpeechModelPhase.downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: model.total == 0 ? null : model.done / model.total),
            ],
            if (model.phase == SpeechModelPhase.missing || model.phase == SpeechModelPhase.failed) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: download,
                  child: Text(model.phase == SpeechModelPhase.failed ? 'Try again' : 'Download'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
