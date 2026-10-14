import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:mobile_backend/engine/audio/player.dart';
import 'package:mobile_backend/engine/audio/wav.dart';

/// Stands in for just_audio's Android plugin: records what it's asked to do and
/// sends the playback events a test asks for.
class FakePlatform extends JustAudioPlatform {
  FakeNativePlayer? player;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async => player = FakeNativePlayer(request.id);

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async => DisposePlayerResponse();
}

class FakeNativePlayer extends AudioPlayerPlatform {
  FakeNativePlayer(super.id);

  final calls = <String>[];
  final _events = StreamController<PlaybackEventMessage>.broadcast();
  var _state = ProcessingStateMessage.idle;
  var _position = Duration.zero;
  var _index = 0;

  void _send() => _events.add(PlaybackEventMessage(
        processingState: _state,
        updateTime: DateTime.now(),
        updatePosition: _position,
        bufferedPosition: _position,
        duration: const Duration(minutes: 1),
        icyMetadata: null,
        currentIndex: _index,
        androidAudioSessionId: null,
      ));

  /// Plays to the end of the last piece.
  void reachEnd(int lastIndex) {
    _index = lastIndex;
    _position = const Duration(minutes: 1);
    _state = ProcessingStateMessage.completed;
    _send();
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    calls.add('load');
    _state = ProcessingStateMessage.ready;
    _send();
    return LoadResponse(duration: const Duration(minutes: 1));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    calls.add('play');
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    calls.add('pause');
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    calls.add('seek:${request.index}:${request.position?.inSeconds}');
    _position = request.position ?? Duration.zero;
    _index = request.index ?? _index;
    _state = ProcessingStateMessage.ready;
    _send();
    return SeekResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async => DisposeResponse();
  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async => SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async => SetSpeedResponse();
  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async => SetPitchResponse();
  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async => SetSkipSilenceResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async => SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async => SetShuffleModeResponse();
  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) async => SetShuffleOrderResponse();
  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();
  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse> setAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest request) async =>
      SetAutomaticallyWaitsToMinimizeStallingResponse();
}

/// A 1-minute piece of silence.
File piece(Directory dir, int i) {
  final f = File('${dir.path}/piece-00$i.wav');
  f.writeAsBytesSync([...wavHeader(60 * kBytesPerSecond), ...List.filled(60 * kBytesPerSecond, 0)]);
  return f;
}

/// Waits for [ok], letting just_audio's async steps run (they take longer when tests run in parallel).
Future<void> until(bool Function() ok) async {
  for (var i = 0; i < 1000 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ok(), isTrue, reason: 'condition not met in time');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePlatform platform;
  late Directory dir;
  setUp(() {
    platform = FakePlatform();
    JustAudioPlatform.instance = platform;
    dir = Directory.systemTemp.createTempSync('player');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('at the end it stops and goes back to the start, so Play plays it again', () async {
    final player = JustAudioPlayer();
    final playing = <bool>[];
    final at = <Duration>[];
    final sub = player.playing.listen(playing.add);
    final atSub = player.position.listen(at.add);
    expect(await player.load([piece(dir, 0), piece(dir, 1)]), const Duration(minutes: 2));
    unawaited(player.play());
    // The end can only come once the phone is really playing.
    await until(() => platform.player!.calls.contains('play'));
    expect(playing.last, isTrue);

    at.clear();
    platform.player!.reachEnd(1);
    await until(() => platform.player!.calls.contains('seek:0:0'));
    await pumpEventQueue();

    expect(playing.last, isFalse);
    expect(platform.player!.calls, containsAllInOrder(['play', 'pause', 'seek:0:0']));
    // From the end straight to the start: never the start of the last piece in between.
    expect(at.last, Duration.zero);
    expect(at, isNot(contains(const Duration(minutes: 1))));
    await sub.cancel();
    await atSub.cancel();
    await player.dispose();
  });

  test('seeking into the second piece shows the time within the whole recording', () async {
    final player = JustAudioPlayer();
    final at = <Duration>[];
    final sub = player.position.listen(at.add);
    await player.load([piece(dir, 0), piece(dir, 1)]);

    await player.seek(const Duration(seconds: 89));
    await pumpEventQueue();

    expect(platform.player!.calls.last, 'seek:1:29');
    expect(at.last, const Duration(seconds: 89));
    await sub.cancel();
    await player.dispose();
  });

  test('a seek that finishes after the screen closed is ignored', () async {
    final player = JustAudioPlayer();
    await player.load([piece(dir, 0), piece(dir, 1)]);
    await player.dispose();
    await player.seek(const Duration(seconds: 89));
  });
}
