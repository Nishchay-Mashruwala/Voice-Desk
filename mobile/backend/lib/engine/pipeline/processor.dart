import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/recording.dart';
import '../../data/recordings_repository.dart';
import '../../data/transcript_repository.dart';
import '../audio/pcm_reader.dart';
import '../models/speech_model.dart';
import '../speech/speech_to_text.dart';
import '../speech/your_words.dart';
import 'conditions.dart';
import 'processing_notice.dart';

/// What processing is doing, for the screens.
class ProcessingState {
  const ProcessingState({this.recordingId, this.title, this.progress = 0, this.left, this.waiting});

  /// The recording being turned into text, if any.
  final int? recordingId;
  final String? title;

  /// 0..1 of that recording.
  final double progress;

  /// About how long it still takes (null until it can be estimated).
  final Duration? left;

  /// Why nothing runs although recordings wait: `model`, `charge`, `cool`.
  final String? waiting;
}

/// A job cut off this many times (the app killed while processing) stops with a message.
const _maxAttempts = 2;

final processorProvider = NotifierProvider<Processor, ProcessingState>(Processor.new);

/// How the recorder tells processing about new audio (tests replace it).
class ProcessingTrigger {
  ProcessingTrigger(this._ref);
  final Ref _ref;

  void pieceFinished(int recordingId, int finishedPieces) =>
      _ref.read(processorProvider.notifier).pieceFinished(recordingId, finishedPieces);

  void recordingStopped(String title) => _ref.read(processorProvider.notifier).recordingStopped(title);

  /// A setting that decides when processing runs was changed.
  void conditionsChanged() => _ref.read(processorProvider.notifier).kick();
}

final processingTriggerProvider = Provider<ProcessingTrigger>(ProcessingTrigger.new);

/// The "Only process while charging" setting.
final onlyWhileChargingProvider = AsyncNotifierProvider<OnlyWhileCharging, bool>(OnlyWhileCharging.new);

class OnlyWhileCharging extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.read(settingsRepositoryProvider).getBool(kOnlyWhileChargingKey);

  Future<void> set(bool on) async {
    await ref.read(settingsRepositoryProvider).setBool(kOnlyWhileChargingKey, on);
    state = AsyncData(on);
    ref.read(processingTriggerProvider).conditionsChanged();
  }
}

/// Speech to text running on a recording that is still being recorded.
class _LiveJob {
  _LiveJob(this.recordingId, this.speech, this.fedMs);
  final int recordingId;
  final SpeechToText speech;
  int fedMs;
}

/// Turns recordings into text, one at a time, oldest first, each from where it
/// last stopped (`processedMs`).
class Processor extends Notifier<ProcessingState> {
  bool _busy = false;
  bool _again = false;
  Timer? _coolTimer;
  _LiveJob? _live;
  Future<void> _liveWork = Future.value();

  RecordingsRepository get _recordings => ref.read(recordingsRepositoryProvider);
  TranscriptRepository get _transcripts => ref.read(transcriptRepositoryProvider);

  /// Whether the job loop is running.
  bool get busy => _busy;

  @override
  ProcessingState build() {
    final changes = ref.read(deviceStateProvider).changes.listen((_) => kick());
    ref.listen(speechModelProvider, (before, now) {
      if (now.phase == SpeechModelPhase.ready) kick();
    });
    ref.onDispose(() {
      changes.cancel();
      _coolTimer?.cancel();
      _live?.speech.close();
    });
    Future.microtask(kick);
    return const ProcessingState();
  }

  void _set(ProcessingState s) {
    if (ref.mounted) state = s;
  }

  /// Looks for work; safe to call any time.
  void kick() {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    unawaited(_loop().catchError((Object e, StackTrace st) {
      // Work for an app that's gone (the processor disposed mid-job) just stops.
      if (ref.mounted) Error.throwWithStackTrace(e, st);
    }).whenComplete(() => _busy = false));
  }

  /// A recording's piece was finished (by the recorder): turn the finished
  /// pieces into text now, on 2 threads — unless a job after Stop is running or
  /// processing must wait (then it's all done after Stop).
  void pieceFinished(int recordingId, int finishedPieces) {
    if (_busy) return;
    _liveWork = _liveWork.then((_) => _liveStep(recordingId, finishedPieces)).catchError((Object _) {});
  }

  Future<void> _liveStep(int id, int finished) async {
    if (_busy || !ref.mounted || !ref.read(speechModelProvider.notifier).isReady) return;
    final gate = await _decide(live: true);
    if (gate.gate != Gate.go) return;
    try {
      var job = _live;
      if (job == null || job.recordingId != id) {
        await _closeLive();
        final from = await _transcripts.processedMs(id);
        job = _live = _LiveJob(id, await ref.read(speechToTextFactoryProvider)(startMs: from, threads: gate.threads), from);
      }
      final pieces = (await _recordings.pieces(id)).take(finished).toList();
      final polish = await ref.read(transcriptPolishProvider.future);
      await for (final chunk in readSamples(pieces, fromMs: job.fedMs)) {
        final t = await job.speech.push(chunk);
        job.fedMs += chunk.length * 1000 ~/ 16000;
        await _transcripts.save(id, polish.apply(t.phrases), processedMs: t.settledMs);
      }
    } on Object {
      if (!ref.mounted) return;
      // Gone or failed: whatever is left is done after Stop.
      await _closeLive();
    }
  }

  Future<void> _closeLive() async {
    final job = _live;
    _live = null;
    await job?.speech.close();
  }

  Future<({Gate gate, int threads})> _decide({required bool live}) async {
    final device = ref.read(deviceStateProvider);
    return decide(
      battery: await device.battery(),
      charging: await device.charging(),
      onlyWhileCharging: await ref.read(settingsRepositoryProvider).getBool(kOnlyWhileChargingKey),
      thermal: await device.thermal(),
      live: live,
    );
  }

  /// A recording just stopped: its processing notice goes up at once, so the
  /// foreground service passes from recording to processing without stopping
  /// (Android may refuse to start one again from the background).
  void recordingStopped(String title) {
    unawaited(ref.read(processingNoticeProvider).show(title, 0, null));
    kick();
  }

  /// Tries a failed recording again.
  Future<void> retry(int id) async {
    await _recordings.clearAttempts(id);
    await _recordings.setStatus(id, RecordingStatus.queued);
    kick();
  }

  Future<void> _loop() async {
    // Live work in progress finishes first; then one engine at a time.
    await _liveWork;
    do {
      _again = false;
      var waiting = false; // a "Plug in to continue" style notice stays up
      while (ref.mounted) {
        final next = await _recordings.nextToProcess();
        if (next == null) {
          _set(const ProcessingState());
          break;
        }
        if (!ref.read(speechModelProvider.notifier).isReady) {
          _set(const ProcessingState(waiting: 'model'));
          break;
        }
        final gate = await _decide(live: false);
        if (gate.gate == Gate.waitCharge) {
          await _recordings.setStatus(next.id, RecordingStatus.waitingCharge);
          _set(const ProcessingState(waiting: 'charge'));
          await ref.read(processingNoticeProvider).showWaiting(next.title, 'charge');
          waiting = true;
          break;
        }
        if (gate.gate == Gate.waitCool) {
          _set(const ProcessingState(waiting: 'cool'));
          await ref.read(processingNoticeProvider).showWaiting(next.title, 'cool');
          waiting = true;
          _coolTimer?.cancel();
          _coolTimer = Timer(const Duration(minutes: 1), kick);
          break;
        }
        await _process(next, gate.threads);
      }
      if (ref.mounted && !waiting) await ref.read(processingNoticeProvider).hide();
    } while (_again && ref.mounted);
  }

  Future<void> _process(Recording r, int threads) async {
    // A stopped recording's live engine (2 threads) makes way for this one;
    // the job goes on from the last saved line.
    await _closeLive();
    if (await _recordings.startAttempt(r.id) > _maxAttempts) {
      await _recordings.setStatus(r.id, RecordingStatus.error, error: 'speech_crashed');
      return;
    }
    await _recordings.setStatus(r.id, RecordingStatus.processing);
    final notice = ref.read(processingNoticeProvider);
    final pieces = await _recordings.pieces(r.id);
    final total = max(1, totalMs(pieces));
    final from = await _transcripts.processedMs(r.id);
    var fed = from;
    var shownPercent = -1;
    final clock = Stopwatch()..start();

    Future<void> report() async {
      final progress = (fed / total).clamp(0.0, 1.0);
      final done = fed - from;
      final left = done <= 0 ? null : Duration(microseconds: clock.elapsedMicroseconds * (total - fed) ~/ done);
      _set(ProcessingState(recordingId: r.id, title: r.title, progress: progress, left: left));
      final percent = (progress * 100).floor();
      if (percent != shownPercent) {
        shownPercent = percent;
        await notice.show(r.title, progress, left);
      }
    }

    SpeechToText? speech;
    try {
      await report();
      final polish = await ref.read(transcriptPolishProvider.future);
      speech = await ref.read(speechToTextFactoryProvider)(startMs: from, threads: threads);
      await for (final chunk in readSamples(pieces, fromMs: from)) {
        final t = await speech.push(chunk);
        fed += chunk.length * 1000 ~/ 16000;
        await _transcripts.save(r.id, polish.apply(t.phrases), processedMs: t.settledMs);
        await report();
        // Battery, charging or heat may change during a job: stop at the last
        // saved line; the loop decides again and resumes from there.
        final now = await _decide(live: false);
        if (now.gate != Gate.go || now.threads < threads) {
          await _recordings.clearAttempts(r.id); // a clean stop, not a crash
          await _recordings.setStatus(r.id, RecordingStatus.queued);
          return;
        }
      }
      final t = await speech.finish();
      await _transcripts.save(r.id, polish.apply(t.phrases), processedMs: total);
      await _recordings.setStatus(r.id, RecordingStatus.done);
      await _recordings.clearAttempts(r.id);
    } on RecordingGone {
      // Deleted while being processed: nothing left to do.
    } on Object {
      if (!ref.mounted) rethrow; // the app is going away
      // The engine failed (SpeechEngineFailed, or an Error from a broken model).
      await _recordings.setStatus(r.id, RecordingStatus.error, error: 'speech_failed');
    } finally {
      await speech?.close();
      _set(const ProcessingState());
    }
  }
}
