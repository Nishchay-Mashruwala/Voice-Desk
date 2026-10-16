import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'wav.dart';

/// Plays a recording's pieces back to back. Positions are across the whole recording.
abstract class Player {
  /// Returns the recording's length.
  Future<Duration> load(List<File> pieces);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Stream<Duration> get position;
  Stream<bool> get playing;
  Future<void> dispose();
}

class JustAudioPlayer implements Player {
  JustAudioPlayer() {
    // just_audio stays "playing" at the end: stop and go back to the start, so Play plays it again.
    _player.processingStateStream.listen((s) async {
      if (s != ja.ProcessingState.completed) return;
      await _player.pause();
      await seek(Duration.zero);
    });
    _player.positionStream.listen((_) => _sendPosition());
    _player.currentIndexStream.listen((_) => _sendPosition());
  }

  final _player = ja.AudioPlayer();
  final _position = StreamController<Duration>.broadcast();

  /// Where each piece starts in the whole recording.
  List<Duration> _starts = const [];

  /// The piece a seek is going to. just_audio reports the new position before
  /// the new piece, so until the seek is done the position is in this piece.
  int? _seekingTo;

  void _sendPosition() {
    if (_position.isClosed) return; // disposed while a seek was finishing
    final i = _seekingTo ?? _player.currentIndex;
    _position.add((i == null || i >= _starts.length ? Duration.zero : _starts[i]) + _player.position);
  }

  @override
  Future<Duration> load(List<File> pieces) async {
    var at = Duration.zero;
    final starts = <Duration>[];
    for (final p in pieces) {
      starts.add(at);
      at += audioDuration(p);
    }
    _starts = starts;
    await _player.setAudioSources([for (final p in pieces) ja.AudioSource.file(p.path)]);
    return at;
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration to) async {
    if (_starts.isEmpty) return;
    var i = _starts.lastIndexWhere((s) => s <= to);
    if (i < 0) i = 0;
    _seekingTo = i;
    try {
      await _player.seek(to - _starts[i], index: i);
    } finally {
      _seekingTo = null;
    }
    _sendPosition();
  }

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<bool> get playing => _player.playingStream;

  @override
  Future<void> dispose() async {
    await _player.dispose();
    await _position.close();
  }
}

final playerProvider = Provider.autoDispose<Player>((ref) {
  final p = JustAudioPlayer();
  ref.onDispose(p.dispose);
  return p;
});
