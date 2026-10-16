import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/retention.dart';
import 'package:mobile_backend/engine/audio/recorder_controller.dart' show freeSpaceProvider;
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';

import '../theme.dart';
import '../widgets/badge.dart';
import '../wording.dart';

final _freeProvider = FutureProvider.autoDispose<int>((ref) => ref.read(freeSpaceProvider).bytesFree());

/// Settings → Storage: what is on the phone; the recordings' audio (how long
/// it is kept, the largest, Delete); and every model the app downloads
/// (besides itself), its size, and Download or Delete. (The shared
/// Hindi/Gujarati words are counted with those two models.)
class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  static const _listed = [
    ModelId.vad,
    ModelId.englishFaster,
    ModelId.englishAccurate,
    ModelId.gujarati,
    ModelId.hindi,
    ModelId.speakers,
    ModelId.taskFaster,
    ModelId.taskAccurate,
  ];

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  /// Deleted here, waiting for the Undo time to run out (as on the Record screen).
  final _hidden = <int>{};

  Future<void> _deleteRecording(Recording r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this recording?'),
        content: const Text('Its audio is removed from the phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _hidden.add(r.id));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final repo = ref.read(recordingsRepositoryProvider);
    // Undo still counts once the page is closed (the snack outlives it).
    var undone = false;
    messenger
        .showSnackBar(
          SnackBar(
            content: const Text('Recording deleted'),
            duration: const Duration(seconds: 5),
            persist: false,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                undone = true;
                if (mounted) setState(() => _hidden.remove(r.id));
              },
            ),
          ),
        )
        .closed
        .then((reason) async {
          if (undone || reason == SnackBarClosedReason.action) return;
          await repo.delete(r.id);
          if (mounted) ref.invalidate(_freeProvider);
        });
  }

  /// A shorter period deletes audio at once: it asks first, saying how much.
  Future<void> _keepFor(int days, int now) async {
    final shorter = days != 0 && (now == 0 || days < now);
    if (shorter) {
      final old = await ref
          .read(recordingsRepositoryProvider)
          .audioOlderThan(DateTime.now().subtract(Duration(days: days)));
      if (!mounted) return;
      if (old.isNotEmpty) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(
              'Delete the audio of ${old.length} recording${old.length == 1 ? '' : 's'} older than '
              '${keepAudioName(days)} now? Their text stays.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
    }
    await ref.read(keepAudioProvider.notifier).set(days);
    // Upkeep applies it now.
    ref.read(processingTriggerProvider).conditionsChanged();
  }

  @override
  Widget build(BuildContext context) {
    final states = ref.watch(modelsProvider);
    final models = ref.read(modelsProvider.notifier);
    final vd = context.vd;
    final onPhone = ModelId.values.fold(0, (sum, id) => sum + models.bytesOnDisk(id));
    final free = ref.watch(_freeProvider).value;
    final withAudio = [
      for (final (r, bytes) in ref.watch(audioSizesProvider).value ?? const <(Recording, int)>[])
        if (!_hidden.contains(r.id)) (r, bytes),
    ];
    final audioBytes = withAudio.fold(0, (sum, e) => sum + e.$2);
    final keep = ref.watch(keepAudioProvider).value;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: vd.muted)),
    );
    Widget total(String what, String value) => ListTile(
      dense: true,
      title: Text(what),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    );

    /// A recording being made or processed may be reading the model now.
    bool inUse() {
      final recording = (ref.read(recordingsProvider).value ?? const <Recording>[])
          .any((r) => r.status == RecordingStatus.recording);
      if (!recording && ref.read(processorProvider).recordingId == null) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("It's in use right now — try again when processing has finished")),
      );
      return true;
    }

    Future<void> delete(ModelId id) async {
      if (inUse()) return;
      final size = megabytes(models.bytesOnDisk(id));
      final needed = ref.read(neededModelIdsProvider).contains(id);
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${modelName(id)}?'),
          content: Text(needed
              ? 'Frees $size MB, but the speech settings or a recording waiting to be processed need it: '
                  'they wait until it is downloaded again.'
              : 'Frees $size MB. You can download it again here.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      );
      // Processing may have started while the question was open.
      if (ok != true || !context.mounted || inUse()) return;
      await models.delete(id);
      ref.invalidate(_freeProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted — $size MB freed')));
      }
    }

    final needed = ref.watch(neededModelIdsProvider);
    final bigPhone = ref.watch(phoneClassProvider).value?.canRunLargeTaskAi ?? false;

    Widget row(ModelId id) {
      final st = states[id] ?? const ModelState(ModelPhase.missing);
      final size = st.phase == ModelPhase.ready ? models.bytesOnDisk(id) : models.bytesToDownload(id);
      // Safe to delete: nothing set up now, and no recording waiting, uses it.
      final unused = st.phase == ModelPhase.ready && !needed.contains(id);
      return ListTile(
        title: Text(modelName(id)),
        subtitle: switch (st.phase) {
          ModelPhase.downloading => Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(value: st.total == 0 ? null : st.done / st.total),
          ),
          ModelPhase.failed => Text(modelFailureText(st.message), style: TextStyle(color: vd.muted)),
          _ => Text('${megabytes(size)} MB${unused ? ' · Not used by your settings' : ''}', style: TextStyle(color: vd.muted)),
        },
        trailing: switch (st.phase) {
          ModelPhase.ready => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const VdBadge('Downloaded', kind: BadgeKind.ok),
              IconButton(
                key: Key('delete-${id.name}'),
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => delete(id),
              ),
            ],
          ),
          ModelPhase.downloading => Text('${percent(st)}%'),
          ModelPhase.failed => TextButton(onPressed: () => models.download(id), child: const Text('Try again')),
          ModelPhase.missing => FilledButton.tonal(
            key: Key('download-${id.name}'),
            onPressed: () => models.download(id),
            child: const Text('Download'),
          ),
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          heading('On this phone'),
          Card(
            child: Column(
              children: [
                total('Recordings', sizeText(audioBytes)),
                total('Models', sizeText(onPhone)),
                total('App data', sizeText(ref.watch(appDataBytesProvider).value ?? 0)),
                total('Free space', free == null ? '' : '${(free / 1e9).toStringAsFixed(1)} GB'),
              ],
            ),
          ),
          heading('Recordings'),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  title: const Text('Keep recordings for'),
                  subtitle: Text("Older recordings' audio is deleted; their text stays.", style: TextStyle(color: vd.muted)),
                  trailing: keep == null
                      ? null
                      : DropdownButton<int>(
                          key: const Key('keep-audio'),
                          value: keep,
                          underline: const SizedBox(),
                          items: [
                            for (final d in kKeepAudioChoices) DropdownMenuItem(value: d, child: Text(keepAudioName(d))),
                          ],
                          onChanged: (d) => d == null || d == keep ? null : _keepFor(d, keep),
                        ),
                ),
                if (withAudio.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      '${withAudio.length} recording${withAudio.length == 1 ? '' : 's'} with audio · '
                      '${sizeText(audioBytes)}',
                      style: TextStyle(color: vd.muted),
                    ),
                  ),
                for (final (r, bytes) in withAudio)
                  ListTile(
                    title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${sizeText(bytes)} · ${DateFormat('d MMM yyyy').format(r.startedAt)}',
                      style: TextStyle(color: vd.muted),
                    ),
                    trailing: IconButton(
                      key: Key('delete-recording-${r.id}'),
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteRecording(r),
                    ),
                  ),
              ],
            ),
          ),
          heading('Downloaded models'),
          Card(
            child: Column(
              children: [
                for (final id in StorageScreen._listed)
                  // The 4B only where it can run, or while it is still here.
                  if (id != ModelId.taskAccurate || bigPhone || states[id]?.phase != ModelPhase.missing) row(id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
