import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/recordings_repository.dart';
import 'audio_source.dart';
import '../pipeline/processor.dart';
import '../speech/speech_setup.dart';
import 'free_space.dart';
import 'piece_writer.dart';
import 'recording_notification.dart';
import 'wav.dart';

/// [starting] lasts from the tap until the microphone and notification run.
enum RecorderPhase { idle, starting, recording, paused }

/// What the recorder is doing. [message] is an id the UI words:
/// `microphone_denied`, `storage_low`, `storage_full_stopped`, `too_short`,
/// `start_failed`, `recording_failed`.
class RecorderState {
  const RecorderState({
    this.phase = RecorderPhase.idle,
    this.recordingId,
    this.elapsed = Duration.zero,
    this.level = 0,
    this.message,
  });

  final RecorderPhase phase;
  final int? recordingId;
  final Duration elapsed;
  final double level;
  final String? message;

  RecorderState copyWith({RecorderPhase? phase, Duration? elapsed, double? level}) => RecorderState(
        phase: phase ?? this.phase,
        recordingId: recordingId,
        elapsed: elapsed ?? this.elapsed,
        level: level ?? this.level,
        message: message,
      );
}

final audioSourceProvider = Provider<AudioSource>((ref) => MicAudioSource());
final recordingNotificationProvider = Provider<RecordingNotification>((ref) => ref.watch(foregroundServiceProvider).recording);
final freeSpaceProvider = Provider<FreeSpace>((ref) => AndroidFreeSpace(ref.watch(recordingsRootProvider).path));

/// Makes the writer for a recording's folder (tests give one that fails).
final pieceWriterProvider = Provider<PieceWriter Function(Directory)>((ref) => PieceWriter.new);

final recorderProvider = NotifierProvider<RecorderController, RecorderState>(RecorderController.new);

/// Free storage is checked after every this much audio.
const _checkEvery = kBytesPerSecond * 10;

class RecorderController extends Notifier<RecorderState> {
  PieceWriter? _writer;
  StreamSubscription<Uint8List>? _audio;
  StreamSubscription<double>? _levels;
  StreamSubscription<String>? _buttons;
  Completer<void>? _audioDone;
  Future<void> _writes = Future.value();
  int _nextCheckAt = _checkEvery;
  int _shownSeconds = -1;
  bool _stopping = false;
  bool _writeFailed = false;
  String _title = '';

  /// Done when a running start has finished: a Stop pressed meanwhile waits for it.
  Future<void>? _starting;

  RecordingsRepository get _repo => ref.read(recordingsRepositoryProvider);
  AudioSource get _source => ref.read(audioSourceProvider);
  RecordingNotification get _notification => ref.read(recordingNotificationProvider);

  @override
  RecorderState build() {
    _buttons = ref.read(recordingNotificationProvider).buttons.listen(_onButton);
    ref.onDispose(() {
      _buttons?.cancel();
      _audio?.cancel();
      _levels?.cancel();
    });
    return const RecorderState();
  }

  void _onButton(String id) {
    switch (id) {
      case 'pause':
        pause();
      case 'resume':
        resume();
      case 'stop':
        stop();
    }
  }

  Future<void> start({String? title}) async {
    if (state.phase != RecorderPhase.idle || _stopping) return;
    // Set before the first await, so a second tap is ignored and a Stop waits.
    state = const RecorderState(phase: RecorderPhase.starting);
    final done = Completer<void>();
    _starting = done.future;
    try {
      await _start(title);
    } finally {
      _starting = null;
      done.complete();
    }
  }

  /// The speech settings of now; English only if they can't be read.
  Future<SpeechSetup> _setupNow() async {
    try {
      return await ref.read(speechSetupProvider.future);
    } on Object {
      return SpeechSetup.englishOnly;
    }
  }

  Future<void> _start(String? title) async {
    if (!await _source.hasPermission()) {
      state = const RecorderState(message: 'microphone_denied');
      return;
    }
    if (!canStartRecording(await ref.read(freeSpaceProvider).bytesFree())) {
      state = const RecorderState(message: 'storage_low');
      return;
    }
    final recording = await _repo.create(title: title, startedAt: DateTime.now(), setup: await _setupNow());
    try {
      _title = recording.title;
      final trigger = ref.read(processingTriggerProvider);
      _writer = ref.read(pieceWriterProvider)(await _repo.audioDir(recording.id))
        ..onPieceFinished = (n) => trigger.pieceFinished(recording.id, n);
      _writes = Future.value();
      _writeFailed = false;
      _nextCheckAt = _checkEvery;
      _shownSeconds = -1;
      await _notification.show(recording.title);
      _audioDone = Completer<void>();
      final stream = await _source.start();
      _audio = stream.listen(
        (pcm) => _writes = _writes.then((_) => _write(pcm)),
        onError: (Object _) => unawaited(stop(message: 'recording_failed')),
        onDone: () {
          if (!_audioDone!.isCompleted) _audioDone!.complete();
        },
      );
      _levels = _source.level.listen((l) => state = state.copyWith(level: l));
      state = RecorderState(phase: RecorderPhase.recording, recordingId: recording.id);
    } catch (_) {
      // Nothing may be left half-started: no notification, microphone or row.
      _writer = null;
      await _quietly(_notification.hide);
      await _quietly(_source.stop);
      await _quietly(() => _repo.delete(recording.id));
      state = const RecorderState(message: 'start_failed');
    }
  }

  Future<void> _write(Uint8List pcm) async {
    final writer = _writer;
    if (writer == null || _writeFailed) return;
    try {
      await writer.add(pcm);
      final elapsed = Duration(microseconds: writer.dataBytes * Duration.microsecondsPerSecond ~/ kBytesPerSecond);
      state = state.copyWith(elapsed: elapsed);
      if (elapsed.inSeconds != _shownSeconds) {
        _shownSeconds = elapsed.inSeconds;
        unawaited(_notification.update(elapsed, paused: state.phase == RecorderPhase.paused));
      }
      if (writer.dataBytes >= _nextCheckAt) {
        _nextCheckAt += _checkEvery;
        if (mustStopRecording(await ref.read(freeSpaceProvider).bytesFree())) {
          unawaited(stop(message: 'storage_full_stopped'));
        }
      }
    } catch (_) {
      // Storage full or gone: keep what was written and stop.
      _writeFailed = true;
      unawaited(stop(message: 'recording_failed'));
    }
  }

  Future<void> pause() async {
    if (state.phase != RecorderPhase.recording) return;
    await _source.pause();
    state = state.copyWith(phase: RecorderPhase.paused, level: 0);
    await _notification.update(state.elapsed, paused: true);
  }

  Future<void> resume() async {
    if (state.phase != RecorderPhase.paused) return;
    await _source.resume();
    state = state.copyWith(phase: RecorderPhase.recording);
    await _notification.update(state.elapsed, paused: false);
  }

  /// Stops and saves (or drops a recording under [kMinRecording]). [message]
  /// says why when the recorder stopped by itself.
  ///
  /// Always ends idle with the notification gone, even when something fails on
  /// the way (a recording that can't be finished is recovered at next start).
  Future<void> stop({String? message}) async {
    if (state.phase == RecorderPhase.idle || _stopping) return;
    _stopping = true;
    try {
      await _starting;
      if (state.phase == RecorderPhase.idle) return; // the start didn't get going
      final id = state.recordingId!;
      await _levels?.cancel();
      await _quietly(_source.stop);
      // The microphone's stream ends on stop; don't hang if a device never says so.
      await _audioDone?.future.timeout(const Duration(seconds: 2), onTimeout: () {});
      await _audio?.cancel();
      await _writes;
      final writer = _writer;
      _writer = null;
      final closed = writer != null && await _quietly(writer.close);
      final elapsed = Duration(microseconds: (writer?.dataBytes ?? 0) * Duration.microsecondsPerSecond ~/ kBytesPerSecond);
      if (_writeFailed || !closed) message = 'recording_failed';
      try {
        if (elapsed < kMinRecording) {
          await _repo.delete(id);
          state = RecorderState(message: message ?? 'too_short');
        } else {
          await _repo.finish(id, elapsed);
          state = RecorderState(message: message);
          // Processing takes the notification over before the recording's goes.
          ref.read(processingTriggerProvider).recordingStopped(_title);
        }
      } catch (_) {
        state = const RecorderState(message: 'recording_failed');
      }
      await _quietly(_notification.hide);
    } finally {
      _stopping = false;
    }
  }
}

/// Runs [f], ignoring a failure (stopping must always get to the end). Says whether it worked.
Future<bool> _quietly(Future<void> Function() f) async {
  try {
    await f();
    return true;
  } catch (_) {
    return false;
  }
}
