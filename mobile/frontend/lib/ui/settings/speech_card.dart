import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/pipeline/speed_book.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';

import '../theme.dart';
import '../widgets/badge.dart';
import '../wording.dart';
import 'model_download.dart';

/// How long a 30-minute recording takes with a setup, on this phone.
final _estimateProvider = FutureProvider.family<Duration, SpeechSetup>(
  (ref, setup) => ref.read(speedBookProvider).estimateFor(setup, const Duration(minutes: 30)),
);

/// Settings → Speech: the languages, Hindi or Gujarati, and the English model.
class SpeechCard extends ConsumerWidget {
  const SpeechCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(speechSettingsProvider).value ?? const SpeechSettings();
    final states = ref.watch(modelsProvider);
    final needed = ref.watch(neededModelsProvider);
    final auto = (ref.watch(phoneClassProvider).value ?? const PhoneClass(totalRamBytes: 0, dotProduct: false)).auto;
    final vd = context.vd;
    final notifier = ref.read(speechSettingsProvider.notifier);
    final models = ref.read(modelsProvider.notifier);

    EnglishModel english(Accuracy a) => switch (a) {
      Accuracy.auto => auto,
      Accuracy.faster => EnglishModel.faster,
      Accuracy.accurate => EnglishModel.accurate,
    };
    ModelId englishModel(Accuracy a) =>
        english(a) == EnglishModel.faster ? ModelId.englishFaster : ModelId.englishAccurate;
    ModelId modelOf(Lang l) => switch (l) {
      Lang.en => englishModel(settings.accuracy),
      Lang.hi => ModelId.hindi,
      Lang.gu => ModelId.gujarati,
    };

    Future<bool> getModel(ModelId id) => askToDownload(context, models, id);

    Future<void> toggle(Lang l, bool on) async {
      final now = settings.languages;
      if (!on) {
        if (now.length > 1) await notifier.setLanguages({...now}..remove(l));
        return;
      }
      if (await getModel(modelOf(l))) await notifier.setLanguages({...now, l});
    }

    Future<void> choose(Accuracy? a) async {
      if (a == null || a == settings.accuracy) return;
      final needsModel = settings.languages.contains(Lang.en);
      if (!needsModel || await getModel(englishModel(a))) await notifier.setAccuracy(a);
    }

    Widget accuracyLine(Accuracy a) {
      final muted = TextStyle(color: vd.muted);
      if (a == Accuracy.auto) return Text('Now: ${englishChoiceName(auto)}', style: muted);
      final id = englishModel(a);
      final st = states[id];
      final setup = SpeechSetup(languages: settings.languages, prefer: settings.prefer, english: english(a));
      final time = ref.watch(_estimateProvider(setup)).value;
      final when = time == null ? '' : estimateText(time);
      if (st?.phase == ModelPhase.ready) {
        return Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [const VdBadge('Downloaded', kind: BadgeKind.ok), if (when.isNotEmpty) Text(when, style: muted)],
        );
      }
      final where = st?.phase == ModelPhase.downloading
          ? 'Downloading · ${percent(st!)}%'
          : 'Downloads ${megabytes(models.bytesToDownload(id))} MB';
      return Text(when.isEmpty ? where : '$where · $when', style: muted);
    }

    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
    Widget hint(String text) => Text(text, style: TextStyle(color: vd.muted, fontSize: 12.5));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (needed.phase != ModelPhase.ready) ...[
            Row(
              children: [
                Expanded(child: Text(speechModelsText(needed))),
                if (needed.phase == ModelPhase.missing || needed.phase == ModelPhase.failed)
                  FilledButton(
                    onPressed: models.downloadNeeded,
                    child: Text(needed.phase == ModelPhase.failed ? 'Try again' : 'Download'),
                  ),
              ],
            ),
            const Divider(height: 28),
          ],
          title('Languages you speak'),
          Wrap(
            spacing: 8,
            children: [
              for (final l in Lang.values)
                FilterChip(
                  label: Text(languageName(l)),
                  selected: settings.languages.contains(l),
                  onSelected: (on) => toggle(l, on),
                ),
            ],
          ),
          for (final l in const [Lang.hi, Lang.gu])
            if (states[modelOf(l)] case final st? when st.phase == ModelPhase.downloading || st.phase == ModelPhase.failed)
              Row(
                children: [
                  Expanded(child: Text(languageModelLine(l, st), style: TextStyle(color: vd.muted))),
                  if (st.phase == ModelPhase.failed)
                    TextButton(onPressed: () => models.download(modelOf(l)), child: const Text('Try again')),
                ],
              ),
          hint('Each phrase is recognised in whichever of these you speak — mix them freely.'),
          if (settings.languages.containsAll({Lang.hi, Lang.gu})) ...[
            const SizedBox(height: 16),
            title('Hindi or Gujarati — which do you speak more?'),
            SegmentedButton<Lang>(
              segments: const [
                ButtonSegment(value: Lang.hi, label: Text('Hindi')),
                ButtonSegment(value: Lang.gu, label: Text('Gujarati')),
              ],
              selected: {settings.prefer},
              onSelectionChanged: (s) => notifier.setPrefer(s.single),
            ),
            const SizedBox(height: 4),
            hint("Written as spoken, Hindi and Gujarati are told apart by sound, and this one wins when it's unclear."),
          ],
          const Divider(height: 28),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Speaker detection'),
            subtitle: Text('Who said what, after each recording', style: TextStyle(color: vd.muted)),
            value: settings.speakers,
            onChanged: notifier.setSpeakers,
          ),
          const Divider(height: 28),
          title('Accuracy (speech model)'),
          RadioGroup<Accuracy>(
            groupValue: settings.accuracy,
            onChanged: choose,
            child: Column(
              children: [
                for (final a in Accuracy.values)
                  RadioListTile<Accuracy>(
                    value: a,
                    contentPadding: EdgeInsets.zero,
                    title: Text(accuracyName(a)),
                    subtitle: accuracyLine(a),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
