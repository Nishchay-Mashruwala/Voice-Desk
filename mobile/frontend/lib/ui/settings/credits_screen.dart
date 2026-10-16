import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';
import 'settings_screen.dart' show appVersionProvider;

/// What the app is built on: (credit, licence, where it's from).
const _credits = [
  (
    'Speech model by NVIDIA (Parakeet), CC BY 4.0; converted to ONNX int8 by the sherpa-onnx project.',
    'CC BY 4.0',
    'https://huggingface.co/nvidia/parakeet-tdt_ctc-110m',
  ),
  ('Hindi and Gujarati speech models: IndicConformer, by AI4Bharat.', 'MIT', 'https://github.com/AI4Bharat/IndicConformerASR'),
  (
    'Their phone versions (sherpa-onnx), by Parismita Global Solutions.',
    'Apache-2.0',
    'https://huggingface.co/parismitaglobalsolutions/indicconformer-sherpa-onnx',
  ),
  ('Voice activity: Silero VAD, by the Silero Team.', 'MIT', 'https://github.com/snakers4/silero-vad'),
  ('Speaker detection: the CAM++ voice model, from 3D-Speaker.', 'Apache-2.0', 'https://github.com/modelscope/3D-Speaker'),
  ('Speech engine: sherpa-onnx, by the k2-fsa project.', 'Apache-2.0', 'https://github.com/k2-fsa/sherpa-onnx'),
  (
    'English word list: from the en_US Hunspell dictionary (SCOWL size 60, wordlist.aspell.net), by Kevin Atkinson and others.',
    'SCOWL licence',
    'http://wordlist.aspell.net/',
  ),
];

/// Settings → About → Licences & credits.
class CreditsScreen extends ConsumerWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vd = context.vd;
    final version = ref.watch(appVersionProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Licences & credits')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (final (credit, licence, link) in _credits)
            Card(
              key: const Key('credit'),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(credit),
                    const SizedBox(height: 6),
                    Text(licence, style: const TextStyle(fontWeight: FontWeight.w600)),
                    SelectableText(link, style: TextStyle(color: vd.muted, fontSize: 12.5)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: () => showLicensePage(context: context, applicationName: 'Voice Desk', applicationVersion: version),
              child: const Text('All licences'),
            ),
          ),
        ],
      ),
    );
  }
}
