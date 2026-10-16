import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/retention.dart';
import '../../data/recording.dart';
import '../../data/recordings_repository.dart';
import '../../data/transcript_repository.dart';
import '../audio/compress.dart';
import '../audio/pcm_reader.dart';
import '../models/catalogue.dart';
import '../models/speech_model.dart';
import '../speakers/grouping.dart';
import '../speech/speech_setup.dart';
import '../speech/speech_to_text.dart';
import '../speech/your_words.dart';
import '../tasks/llm_engine.dart';
import '../tasks/task_finder.dart';
import '../tasks/task_settings.dart';
import 'conditions.dart';
import 'processing_notice.dart';
import 'speed_book.dart';

/// What processing is doing, for the screens.
class ProcessingState {
  const ProcessingState(
      {this.recordingId, this.title, this.progress = 0, this.left, this.waiting, this.step, this.part = 0, this.parts = 0});

  /// The recording being turned into text, if any.
  final int? recordingId;
  final String? title;

  /// 0..1 of that recording.
  final double progress;

  /// About how long it still takes (null until it can be estimated).
  final Duration? left;

  /// Why nothing runs although recordings wait: `model`, `charge`, `cool`;
  /// `task_model` when only their tasks wait, for the task model.
  final String? waiting;

  /// After the text: `speakers` (finding who said what), `tasks` (its summary
  /// and tasks).
  final String? step;

  /// The tasks step's part (1, 2, …) of [parts] (0: not known yet, or one).
  final int part;
  final int parts;
}

/// A job cut off this many times (the app killed while processing) stops with a message.
const _maxAttempts = 2;

/// Jobs over at least this much audio (ms) count for this phone's speed.
const _minMeasuredMs = 60000;

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

final speakerGrouperProvider = Provider<SpeakerGrouper>((ref) => groupInBackground);

/// Starts the task model (tests replace it).
final llmEngineFactoryProvider = Provider<Future<LlmEngine> Function(File model)>((ref) => (model) => LlamaEngine.start(model));

/// Compresses a finished recording's pieces into its checked FLAC, away from
/// the screens' thread (tests replace it).
final audioCompressorProvider = Provider<Future<bool> Function(List<File> pieces, Directory dir)>(
  (ref) => (pieces, dir) => Isolate.run(() => compressPieces(pieces, dir)),
);

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

  /// The task model while a tasks pass runs.
  LlmEngine? _taskEngine;

  /// Recordings whose compression failed since the app started (tried again
  /// at the next start).
  final _compressFailed = <int>{};

  RecordingsRepository get _recordings => ref.read(recordingsRepositoryProvider);
  TranscriptRepository get _transcripts => ref.read(transcriptRepositoryProvider);

  /// Whether every model a recording's setup needs is on the phone.
  bool _readyFor(SpeechSetup setup) {
    final models = ref.read(modelsProvider.notifier);
    return setup.models.every(models.isReady);
  }

  /// Whether the job loop is running.
  bool get busy => _busy;

  @override
  ProcessingState build() {
    final changes = ref.read(deviceStateProvider).changes.listen((_) => kick());
    ref.listen(modelsProvider, (before, now) {
      if (now.entries.any((e) => e.value.phase == ModelPhase.ready && before?[e.key]?.phase != ModelPhase.ready)) kick();
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
    if (_busy) {
      // A tasks part takes minutes on a phone: it gives way to the recording
      // now, and is done again afterwards.
      if (_taskEngine case final engine?) {
        engine.stop();
        _again = true;
      }
      return;
    }
    _liveWork = _liveWork.then((_) => _liveStep(recordingId, finishedPieces)).catchError((Object _) {});
  }

  Future<void> _liveStep(int id, int finished) async {
    if (_busy || !ref.mounted) return;
    final setup = (await _recordings.get(id))?.setup;
    if (setup == null || !_readyFor(setup)) return;
    final gate = await _decide(live: true);
    if (gate.gate != Gate.go) return;
    try {
      var job = _live;
      if (job == null || job.recordingId != id) {
        await _closeLive();
        final from = await _transcripts.processedMs(id);
        job = _live = _LiveJob(
            id, await ref.read(speechToTextFactoryProvider)(setup: setup, startMs: from, threads: gate.threads), from);
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

  /// Turns a finished recording into text again with [setup]; its old text
  /// shows until the new one is complete.
  Future<void> processAgain(int id, SpeechSetup setup) async {
    await _recordings.processAgain(id, setup);
    kick();
  }

  /// Finds a finished recording's summary and tasks (again), after any speech
  /// waiting; the owner's own changes to its tasks stay.
  Future<void> findTasks(int id) async {
    await _recordings.setTasksStatus(id, TasksStatus.waiting);
    kick();
  }

  /// Tries a failed recording again (a Process again run continues).
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
      var idle = false; // no speech job can run now: time for upkeep
      while (ref.mounted) {
        final waitingNow = await _recordings.toProcess();
        if (waitingNow.isEmpty) {
          _set(const ProcessingState());
          idle = true;
          break;
        }
        // The oldest whose models are here: one waiting for a download (or a
        // language turned off since) doesn't hold up the others.
        final next = waitingNow.where((r) => _readyFor(r.setup)).firstOrNull;
        if (next == null) {
          _set(const ProcessingState(waiting: 'model'));
          idle = true;
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
      // The notice (the foreground service) stays up into the tasks step:
      // Android may refuse to start it again from the background.
      final tasksNext = ref.mounted && idle && !_again && await _tasksCanRun();
      if (ref.mounted && !waiting && !tasksNext) await ref.read(processingNoticeProvider).hide();
      if (ref.mounted && idle) await _upkeep();
      if (tasksNext) await _tasks();
    } while (_again && ref.mounted);
  }

  /// When no speech job can run: finished recordings' pieces become their
  /// checked FLAC, one at a time, and audio older than "Keep recordings for"
  /// is deleted. Stops as soon as a job comes in (the loop then runs it and
  /// comes back here).
  Future<void> _upkeep() async {
    try {
      // Not while recording: live text and the recording's own storage come first.
      if (await _recordings.anyRecording()) return;
      for (final r in await _recordings.toCompress()) {
        if (_again || !ref.mounted) return;
        if (_compressFailed.contains(r.id)) continue;
        final dir = await _recordings.audioDir(r.id);
        // A FLAC already there (its pieces kept for a job) is checked again too.
        final ok = await ref.read(audioCompressorProvider)(await _recordings.wavPieces(r.id), dir);
        if (!ref.mounted) return;
        if (ok) {
          await _recordings.compressed(r.id);
        } else {
          _compressFailed.add(r.id);
          await _recordings.countCompressFailure(r.id);
        }
      }
      if (_again || !ref.mounted) return;
      await applyRetention(_recordings, await ref.read(keepAudioProvider.future), DateTime.now());
    } on Object {
      // Never in the way of processing: tried again at the next pass.
      if (!ref.mounted) return;
    }
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
    if (pieces.isEmpty && r.reprocessing) {
      // Its audio went after Process again was asked for: the old text stays.
      await _recordings.cancelProcessAgain(r.id);
      return;
    }
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
      speech = await ref.read(speechToTextFactoryProvider)(setup: r.setup, startMs: from, threads: threads);
      await for (final chunk in readSamples(pieces, fromMs: from)) {
        final t = await speech.push(chunk);
        fed += chunk.length * 1000 ~/ 16000;
        await _transcripts.save(r.id, polish.apply(t.phrases), processedMs: t.settledMs, draft: r.reprocessing);
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
      await _transcripts.save(r.id, polish.apply(t.phrases), processedMs: total, draft: r.reprocessing);
      // The speech models make way for the speakers step.
      await speech.close();
      speech = null;
      final named = !r.setup.speakers || await _findSpeakers(r);
      if (r.reprocessing) await _transcripts.commitDraft(r.id);
      await _recordings.setStatus(r.id, RecordingStatus.done, error: named ? null : 'speakers_failed');
      await _recordings.clearAttempts(r.id);
      // Its summary and tasks come after any other recording's text.
      if ((await ref.read(taskSettingsProvider.future)).findTasks) {
        await _recordings.setTasksStatus(r.id, TasksStatus.waiting);
      }
      // This phone's speed for the estimates: a job on 4 threads over a minute or more.
      if (threads == 4 && total - from >= _minMeasuredMs) {
        await ref.read(speedBookProvider).record(r.setup, clock.elapsedMicroseconds / 1000 / (total - from));
      }
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

  /// Who said what, over the job's lines; false when it failed (the text stays).
  Future<bool> _findSpeakers(Recording r) async {
    _set(ProcessingState(recordingId: r.id, title: r.title, progress: 1, step: 'speakers'));
    final speakers = ref.read(speakersRepositoryProvider);
    try {
      final lines = await _transcripts.linesForGrouping(r.id, draft: r.reprocessing);
      final result = await ref.read(speakerGrouperProvider)(lines,
          me: await speakers.myVoice(), people: await speakers.people());
      await speakers.saveGroups(r.id, result, draft: r.reprocessing);
      return true;
    } on RecordingGone {
      rethrow;
    } on Object {
      if (!ref.mounted) rethrow;
      return false;
    }
  }

  /// When no speech job can run: finds the summary and tasks of the recordings
  /// waiting for them, oldest first, one part at a time, saving after each. It
  /// gives way between parts to a recording being made, to speech waiting, and
  /// to the battery and heat rules; the next pass goes on from the next part.
  /// Whether a tasks pass has work it can do now (else it says why it waits).
  Future<bool> _tasksCanRun() async {
    if (await _recordings.anyRecording()) return false;
    if ((await _recordings.tasksWaiting()).isEmpty) return false;
    if (!ref.read(modelsProvider.notifier).isReady(await ref.read(chosenTaskModelProvider.future))) {
      _set(const ProcessingState(waiting: 'task_model'));
      return false;
    }
    return true;
  }

  /// Takes the processing notice down at the end, whichever way it ends
  /// (unless it now says what it waits for).
  Future<void> _tasks() async {
    final notice = ref.read(processingNoticeProvider);
    try {
      final model = await ref.read(chosenTaskModelProvider.future);
      var waiting = await _recordings.tasksWaiting();
      while (waiting.isNotEmpty && ref.mounted) {
        if (!await _findTasksOf(waiting.first, model, notice)) return;
        waiting = await _recordings.tasksWaiting();
      }
    } finally {
      await _taskEngine?.close();
      _taskEngine = null;
      if (ref.mounted) {
        if (state.step == 'tasks') _set(const ProcessingState());
        if (state.waiting == null) await notice.hide();
      }
    }
  }

  /// One recording's tasks, part by part. False when it gave way (the pass ends).
  Future<bool> _findTasksOf(Recording r, ModelId model, ProcessingNotice notice) async {
    final lines = await _transcripts.watch(r.id).first;
    final words = await ref.read(yourWordsProvider.future);
    final trained = await ref.read(speakersRepositoryProvider).myVoice() != null;
    var part = r.tasksStatus == TasksStatus.finding ? r.tasksPart : 0;
    var work = r.tasksStatus == TasksStatus.finding ? r.tasksWork : '';
    var parts = 0;
    // A whole step in one go is timed for this phone's estimates.
    final timed = part == 0 ? (Stopwatch()..start()) : null;
    while (ref.mounted) {
      // Speech first: a recording being made, or one waiting for its text.
      if (_again || await _recordings.anyRecording()) return false;
      final gate = await _decide(live: false);
      if (gate.gate == Gate.waitCharge) {
        _set(const ProcessingState(waiting: 'charge'));
        await notice.showWaiting(r.title, 'charge');
        return false;
      }
      if (gate.gate == Gate.waitCool) {
        _set(const ProcessingState(waiting: 'cool'));
        await notice.showWaiting(r.title, 'cool');
        _coolTimer?.cancel();
        _coolTimer = Timer(const Duration(minutes: 1), kick);
        return false;
      }
      // A step cut off twice at the same place (the app killed) stops there.
      if (await _recordings.startAttempt(r.id) > _maxAttempts) {
        await _recordings.clearAttempts(r.id);
        await _recordings.tasksFailed(r.id, 'tasks_crashed');
        return true;
      }
      _set(ProcessingState(recordingId: r.id, title: r.title, progress: 1, step: 'tasks', part: part + 1, parts: parts));
      await notice.show(r.title, parts == 0 ? 0 : part / parts, null);
      try {
        final engine = _taskEngine ??= await ref.read(llmEngineFactoryProvider)(
            ref.read(modelStoreProvider).file(model, kCatalogue[model]!.fileName!));
        final step = await TaskFinder(engine, words: words, voiceTrained: trained).next(r, lines, part: part, work: work);
        if (await _recordings.get(r.id) == null) return true; // deleted meanwhile
        await _recordings.clearAttempts(r.id);
        switch (step) {
          case TaskPart(:final next, work: final now, :final ofParts):
            await _recordings.saveTasksPart(r.id, next, now);
            (part, work, parts) = (next, now, ofParts);
          case TaskDone(:final summary, :final found):
            await ref.read(tasksRepositoryProvider).saveFound(r.id, summary, found);
            await _recordings.setTasksStatus(r.id, TasksStatus.found);
            final audio = r.duration?.inMilliseconds ?? 0;
            if (timed != null && audio >= _minMeasuredMs) {
              final ai = model == ModelId.taskAccurate ? TaskAi.accurate : TaskAi.faster;
              await ref.read(speedBookProvider).recordTasks(ai, timed.elapsedMicroseconds / 1000 / audio);
            }
            return true;
        }
      } on LlmFailed catch (e) {
        if (!ref.mounted) rethrow;
        await _recordings.clearAttempts(r.id);
        if (e.reason == 'stopped') return false; // gave way: the part is done again later
        if (e.reason == 'gone') {
          // Its isolate ended: the next recording gets a new one.
          await _taskEngine?.close();
          _taskEngine = null;
        }
        await _recordings.tasksFailed(r.id, e.reason);
        return true;
      } on Object {
        if (!ref.mounted) rethrow;
        // Deleted meanwhile (its tasks went with it), or the step failed.
        if (await _recordings.get(r.id) != null) {
          await _recordings.clearAttempts(r.id);
          await _recordings.tasksFailed(r.id, 'tasks_failed');
        }
        return true;
      }
    }
    return false;
  }
}
