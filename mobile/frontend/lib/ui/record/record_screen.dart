import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/engine/audio/recorder_controller.dart';
import 'package:mobile_backend/engine/audio/recording_notification.dart' show clock;
import 'package:mobile_backend/engine/permissions.dart';

import '../recording/recording_detail_screen.dart';

import 'package:mobile_backend/engine/pipeline/processor.dart';

import '../theme.dart';
import '../widgets/orb.dart';
import '../widgets/page_header.dart';
import '../wording.dart';
import 'recording_tile.dart';
import 'speech_model_banner.dart';

/// Record button on top, every recording below it (like the PC's Listen page).
class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  final _title = TextEditingController();

  /// Swiped away, waiting for the Undo time to run out.
  final _hidden = <int>{};

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final recorder = ref.read(recorderProvider.notifier);
    if (ref.read(recorderProvider).phase != RecorderPhase.idle) {
      await recorder.stop();
      return;
    }
    await _askOnce();
    await recorder.start(title: _title.text);
  }

  /// Before the first recording: notifications (Android 13+) and running unrestricted.
  Future<void> _askOnce() async {
    final settings = ref.read(settingsRepositoryProvider);
    final permissions = ref.read(permissionsProvider);
    final status = await permissions.check();
    if (status['notifications'] == false) await permissions.request('notifications');
    if (await settings.getBool('battery_asked') || status['battery_unrestricted'] == true) return;
    if (!mounted) return;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep recording in the background'),
        content: const Text(
          'Samsung and other phones stop apps in the background. Allow Voice Desk to run unrestricted '
          "so long recordings aren't cut off.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Allow')),
        ],
      ),
    );
    if (allow == true) await permissions.request('battery_unrestricted');
    await settings.setBool('battery_asked', true);
  }

  void _delete(Recording r) {
    setState(() => _hidden.add(r.id));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: const Text('Recording deleted'),
            duration: const Duration(seconds: 5),
            // With an action a SnackBar stays until tapped by default; it must time out for the delete to happen.
            persist: false,
            action: SnackBarAction(label: 'Undo', onPressed: () => setState(() => _hidden.remove(r.id))),
          ),
        )
        .closed
        .then((reason) {
          if (reason != SnackBarClosedReason.action && _hidden.contains(r.id)) {
            ref.read(recordingsRepositoryProvider).delete(r.id);
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final rec = ref.watch(recorderProvider);
    // A recording ended (here or from the notification): the next one starts
    // untitled. A start that didn't happen keeps the title for the next try.
    ref.listen(recorderProvider, (before, now) {
      final ran = before?.phase == RecorderPhase.recording || before?.phase == RecorderPhase.paused;
      if (ran && now.phase == RecorderPhase.idle) _title.clear();
    });
    final recordings = ref.watch(recordingsProvider).value ?? const <Recording>[];
    final active = rec.phase != RecorderPhase.idle;
    final shown = recordings.where((r) => !_hidden.contains(r.id)).toList();
    final vd = context.vd;
    final orbState = switch (rec.phase) {
      RecorderPhase.idle => OrbState.idle,
      RecorderPhase.paused => OrbState.paused,
      RecorderPhase.starting || RecorderPhase.recording => OrbState.recording,
    };
    final hero = Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          children: [
            TextField(
              key: const Key('title-field'),
              controller: _title,
              enabled: !active,
              decoration: const InputDecoration(labelText: 'Title (optional)', isDense: true),
            ),
            const SizedBox(height: 4),
            Orb(key: const Key('record-button'), state: orbState, level: rec.level, size: 100, onPressed: _record),
            Text(
              recorderPhaseText(rec.phase),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4),
            ),
            if (active) ...[
              const SizedBox(height: 2),
              Text(
                clock(rec.elapsed),
                style: TextStyle(fontSize: 15, color: vd.muted, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => rec.phase == RecorderPhase.paused
                    ? ref.read(recorderProvider.notifier).resume()
                    : ref.read(recorderProvider.notifier).pause(),
                icon: Icon(rec.phase == RecorderPhase.paused ? Icons.play_arrow : Icons.pause, size: 18),
                label: Text(rec.phase == RecorderPhase.paused ? 'Resume' : 'Pause'),
              ),
            ] else
              Text('It keeps recording with the screen off.', style: TextStyle(color: vd.muted)),
            if (rec.message != null) ...[
              const SizedBox(height: 8),
              Text(recorderMessageText(rec.message!), textAlign: TextAlign.center),
              if (rec.message == 'microphone_denied')
                TextButton(
                  onPressed: () => ref.read(permissionsProvider).openSettings(),
                  child: const Text('Open settings'),
                ),
            ],
          ],
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const PageHeader(
          lead: 'Speak, and it ',
          highlight: 'writes',
          tail: '.',
          subtitle: 'Record a meeting or a note. Voice Desk turns it into text and tasks, on this phone.',
        ),
        const SizedBox(height: 16),
        hero,
        const _ProcessingLine(),
        const SizedBox(height: 12),
        const SpeechModelBanner(),
        const SizedBox(height: 8),
        Text(
          'Recordings',
          style: TextStyle(fontWeight: FontWeight.w700, color: vd.muted),
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: vd.border),
            ),
            child: Text(
              'Your recordings appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: vd.muted),
            ),
          )
        else
          for (final r in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Dismissible(
                key: ValueKey(r.id),
                direction: r.status == RecordingStatus.recording ? DismissDirection.none : DismissDirection.endToStart,
                background: Container(
                  decoration: BoxDecoration(
                    color: VdColors.danger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete_outline, color: VdColors.danger),
                ),
                onDismissed: (_) => _delete(r),
                child: RecordingTile(
                  recording: r,
                  onTap: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => RecordingDetailScreen(recordingId: r.id))),
                ),
              ),
            ),
      ],
    );
  }
}

/// What processing is doing ("Turning “Weekly review” into text · 40%…").
class _ProcessingLine extends ConsumerWidget {
  const _ProcessingLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(processorProvider);
    final line = processingLine(state);
    if (line == null) return const SizedBox.shrink();
    final vd = context.vd;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
      child: Row(
        children: [
          if (state.recordingId != null)
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: vd.accent))
          else
            Icon(state.waiting == 'cool' ? Icons.thermostat : Icons.battery_charging_full, size: 16, color: vd.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(line, style: TextStyle(color: vd.muted)),
          ),
        ],
      ),
    );
  }
}
