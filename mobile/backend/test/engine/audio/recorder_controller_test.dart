import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/engine/audio/audio_source.dart';
import 'package:mobile_backend/engine/audio/free_space.dart';
import 'package:mobile_backend/engine/audio/piece_writer.dart';
import 'package:mobile_backend/engine/audio/recorder_controller.dart';
import 'package:mobile_backend/engine/audio/recording_notification.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';

class FakeSource implements AudioSource {
  bool permission = true;
  bool failStart = false;
  final calls = <String>[];
  StreamController<Uint8List>? _audio;
  final _level = StreamController<double>.broadcast();

  void emit(Uint8List pcm) => _audio!.add(pcm);
  void fail() => _audio!.addError(Exception('microphone gone'));

  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<Stream<Uint8List>> start() async {
    calls.add('start');
    if (failStart) throw Exception('microphone busy');
    _audio = StreamController<Uint8List>();
    return _audio!.stream;
  }

  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<void> stop() async {
    calls.add('stop');
    await _audio?.close();
  }

  @override
  Stream<double> get level => _level.stream;
}

class FakeNotification implements RecordingNotification {
  final calls = <String>[];
  final _buttons = StreamController<String>.broadcast();
  void press(String id) => _buttons.add(id);

  /// When set, show() waits for it (the real service takes a moment to start).
  Completer<void>? slowShow;
  bool failShow = false;

  @override
  Future<void> show(String title) async {
    calls.add('show:$title');
    await slowShow?.future;
    if (failShow) throw Exception('service not started');
  }
  @override
  Future<void> update(Duration elapsed, {required bool paused}) async => calls.add('update');
  @override
  Future<void> hide() async => calls.add('hide');
  @override
  Stream<String> get buttons => _buttons.stream;
}

/// A writer that fails once [failAfter] chunks were written (storage full or gone).
class FailingWriter extends PieceWriter {
  FailingWriter(super.dir);
  int failAfter = 1 << 30;
  int _adds = 0;
  @override
  Future<void> add(Uint8List pcm) async {
    if (_adds++ >= failAfter) throw const FileSystemException('No space left on device');
    await super.add(pcm);
  }
}

/// Records what the recorder tells processing.
class FakeTrigger implements ProcessingTrigger {
  final calls = <String>[];

  /// Also logs into another fake's list, to check the order between them.
  List<String>? shared;
  @override
  void pieceFinished(int recordingId, int finishedPieces) => calls.add('piece:$finishedPieces');
  @override
  void recordingStopped(String title) {
    calls.add('stopped');
    shared?.add('stopped:$title');
  }
  @override
  void conditionsChanged() => calls.add('conditions');
}

class FakeFreeSpace implements FreeSpace {
  int value = 10 * 1024 * 1024 * 1024;
  @override
  Future<int> bytesFree() async => value;
}

Future<void> waitFor(bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late FakeSource source;
  late FakeNotification notification;
  late FakeFreeSpace free;
  late RecordingsRepository repo;
  late RecorderController ctl;
  FailingWriter? writer;
  late FakeTrigger trigger;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    source = FakeSource();
    notification = FakeNotification();
    free = FakeFreeSpace();
    trigger = FakeTrigger();
    container = ProviderContainer(overrides: [
      processingTriggerProvider.overrideWithValue(trigger),
      databaseProvider.overrideWithValue(db),
      recordingsRootProvider.overrideWithValue(Directory.systemTemp.createTempSync('rec')),
      audioSourceProvider.overrideWithValue(source),
      recordingNotificationProvider.overrideWithValue(notification),
      freeSpaceProvider.overrideWithValue(free),
      pieceWriterProvider.overrideWithValue((dir) => writer = FailingWriter(dir)),
    ]);
    repo = container.read(recordingsRepositoryProvider);
    ctl = container.read(recorderProvider.notifier);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  RecorderState state() => container.read(recorderProvider);

  test('records into pieces and finishes as queued', () async {
    await ctl.start(title: 'Weekly');
    expect(state().phase, RecorderPhase.recording);
    source.emit(Uint8List(32000 * 3)); // 3 s
    await ctl.stop();
    final r = (await repo.watchAll().first).single;
    expect(r.title, 'Weekly');
    expect(r.status, RecordingStatus.queued);
    expect(r.duration, const Duration(seconds: 3));
    expect(await repo.pieces(r.id), hasLength(1));
    expect(notification.calls.first, 'show:Weekly');
    expect(notification.calls.last, 'hide');
    expect(state().phase, RecorderPhase.idle);
  });

  test('microphone refused → no recording, message', () async {
    source.permission = false;
    await ctl.start();
    expect(state().message, 'microphone_denied');
    expect(state().phase, RecorderPhase.idle);
    expect(await repo.watchAll().first, isEmpty);
  });

  test('storage low → does not start', () async {
    free.value = kMinFreeToStart - 1;
    await ctl.start();
    expect(state().message, 'storage_low');
    expect(source.calls, isNot(contains('start')));
    expect(await repo.watchAll().first, isEmpty);
  });

  test('stops and saves when storage runs low', () async {
    await ctl.start();
    source.emit(Uint8List(32000 * 5));
    free.value = kMinFreeWhileRecording - 1;
    source.emit(Uint8List(32000 * 6)); // passes the 10 s check
    await waitFor(() => state().phase == RecorderPhase.idle);
    expect(state().phase, RecorderPhase.idle);
    expect(state().message, 'storage_full_stopped');
    final r = (await repo.watchAll().first).single;
    expect(r.status, RecordingStatus.queued);
    expect(r.duration, const Duration(seconds: 11));
  });

  test('discards recordings under 1 s', () async {
    await ctl.start();
    source.emit(Uint8List(16000)); // 0.5 s
    await ctl.stop();
    expect(await repo.watchAll().first, isEmpty);
    expect(state().message, 'too_short');
  });

  test('elapsed follows the audio written', () async {
    await ctl.start();
    source.emit(Uint8List(32000 * 2));
    await waitFor(() => state().elapsed == const Duration(seconds: 2));
    expect(state().elapsed, const Duration(seconds: 2));
    await ctl.stop();
  });

  test('pause and resume from the notification', () async {
    await ctl.start();
    notification.press('pause');
    await waitFor(() => state().phase == RecorderPhase.paused);
    expect(state().phase, RecorderPhase.paused);
    expect(source.calls, contains('pause'));
    notification.press('resume');
    await waitFor(() => state().phase == RecorderPhase.recording);
    expect(state().phase, RecorderPhase.recording);
    expect(source.calls, contains('resume'));
    notification.press('stop');
    await waitFor(() => state().phase == RecorderPhase.idle);
    expect(state().phase, RecorderPhase.idle);
  });

  test('a second start while recording is ignored', () async {
    await ctl.start();
    await ctl.start();
    source.emit(Uint8List(32000 * 2));
    await ctl.stop();
    expect(await repo.watchAll().first, hasLength(1));
  });

  test('Stop pressed while starting stops it once started: microphone off, nothing left', () async {
    notification.slowShow = Completer();
    final starting = ctl.start();
    await pumpEventQueue();
    final stopping = ctl.stop();
    notification.slowShow!.complete();
    await starting;
    await stopping;
    expect(source.calls.last, 'stop');
    expect(state().phase, RecorderPhase.idle);
    expect(await repo.watchAll().first, isEmpty);
  });

  test('two quick taps on Record make one recording', () async {
    notification.slowShow = Completer();
    final first = ctl.start();
    final second = ctl.start();
    notification.slowShow!.complete();
    await first;
    await second;
    source.emit(Uint8List(32000 * 2));
    await ctl.stop();
    expect(await repo.watchAll().first, hasLength(1));
    expect(source.calls.where((c) => c == 'start'), hasLength(1));
  });

  test('the microphone failing to start leaves nothing recording', () async {
    source.failStart = true;
    await ctl.start();
    expect(state().phase, RecorderPhase.idle);
    expect(state().message, 'start_failed');
    expect(notification.calls.last, 'hide');
    expect(await repo.watchAll().first, isEmpty);
  });

  test('the notification failing to start leaves nothing recording', () async {
    notification.failShow = true;
    await ctl.start();
    expect(state().phase, RecorderPhase.idle);
    expect(state().message, 'start_failed');
    expect(source.calls, isNot(contains('start')));
    expect(await repo.watchAll().first, isEmpty);
  });

  test('a failed write stops the recording and keeps what was saved', () async {
    await ctl.start();
    writer!.failAfter = 1;
    source.emit(Uint8List(32000 * 2));
    source.emit(Uint8List(32000 * 2)); // storage full now
    await waitFor(() => state().phase == RecorderPhase.idle);
    expect(state().phase, RecorderPhase.idle);
    expect(state().message, 'recording_failed');
    expect(notification.calls.last, 'hide');
    await ctl.stop(); // nothing left to stop, and no error
  });

  test('a microphone error stops the recording and keeps it', () async {
    await ctl.start();
    source.emit(Uint8List(32000 * 2));
    source.fail();
    await waitFor(() => state().phase == RecorderPhase.idle);
    expect(state().phase, RecorderPhase.idle);
    expect(state().message, 'recording_failed');
    final r = (await repo.watchAll().first).single;
    expect(r.status, RecordingStatus.queued);
    expect(r.duration, const Duration(seconds: 2));
  });

  test('tells processing about each finished piece, and when it stops', () async {
    await ctl.start();
    source.emit(Uint8List(32000 * 125)); // 2 min 5 s: two pieces finished
    await waitFor(() => trigger.calls.length >= 2);
    await ctl.stop();
    expect(trigger.calls, ['piece:1', 'piece:2', 'stopped']);
  });

  test('processing takes over the notification before the recording one goes', () async {
    trigger.shared = notification.calls;
    await ctl.start(title: 'Weekly');
    source.emit(Uint8List(32000 * 2));
    await ctl.stop();
    expect(notification.calls.sublist(notification.calls.length - 2), ['stopped:Weekly', 'hide']);
  });

  test('a recording is made with the speech setup of now', () async {
    await container.read(speechSettingsProvider.notifier).setLanguages({Lang.en, Lang.gu});
    await container.read(speechSettingsProvider.notifier).setAccuracy(Accuracy.accurate);
    await ctl.start();
    source.emit(Uint8List(32000));
    await ctl.stop();
    expect((await repo.watchAll().first).single.setup,
        const SpeechSetup(languages: {Lang.en, Lang.gu}, english: EnglishModel.accurate, speakers: true)); // speakers on by default
  });
}
