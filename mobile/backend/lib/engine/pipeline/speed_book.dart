import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/settings_repository.dart';
import '../speech/speech_setup.dart';
import '../tasks/task_settings.dart';

/// How fast this phone turns a recording into text with each setup:
/// processing time ÷ audio time, after Stop on 4 threads. Until measured, the
/// Galaxy M31 speed test's figures (an estimate for the bigger English model
/// and the Indian ones).
class SpeedBook {
  SpeedBook(this._settings);
  final SettingsRepository _settings;

  static const _faster = 0.17;
  static const _accurate = 0.9;
  static const _perIndian = 0.2;

  /// Jobs averaged.
  static const _kept = 5;

  static double defaultFor(SpeechSetup s) =>
      (s.hasEnglish ? (s.english == EnglishModel.faster ? _faster : _accurate) : 0) + _perIndian * s.indian.length;

  String _key(SpeechSetup s) => 'speed:${s.key}';

  Future<List<double>> _measured(SpeechSetup s) async {
    final stored = await _settings.getString(_key(s));
    return [for (final x in stored.split(',')) ?double.tryParse(x)];
  }

  Future<double> rtf(SpeechSetup s) async {
    final m = await _measured(s);
    return m.isEmpty ? defaultFor(s) : m.reduce((a, b) => a + b) / m.length;
  }

  Future<void> record(SpeechSetup s, double rtf) async {
    final m = [...await _measured(s), rtf];
    await _settings.setString(_key(s), m.skip(m.length > _kept ? m.length - _kept : 0).join(','));
  }

  /// About how long [audio] takes with [s] on this phone.
  Future<Duration> estimateFor(SpeechSetup s, Duration audio) async =>
      Duration(milliseconds: (audio.inMilliseconds * await rtf(s)).round());

  /// The tasks step's time ÷ audio time with each task model; until measured,
  /// the M31 speed test's (1.7B: a 30-min meeting in about 24 min; the 4B
  /// about twice as slow, not measured).
  static double defaultTasks(TaskAi a) => a == TaskAi.faster ? 0.8 : 1.6;

  Future<double> tasksRtf(TaskAi a) async {
    final stored = await _settings.getString('speed:tasks:${a.name}');
    final m = [for (final x in stored.split(',')) ?double.tryParse(x)];
    return m.isEmpty ? defaultTasks(a) : m.reduce((x, y) => x + y) / m.length;
  }

  Future<void> recordTasks(TaskAi a, double rtf) async {
    final stored = await _settings.getString('speed:tasks:${a.name}');
    final m = [for (final x in stored.split(',')) ?double.tryParse(x), rtf];
    await _settings.setString('speed:tasks:${a.name}', m.skip(m.length > _kept ? m.length - _kept : 0).join(','));
  }

  /// About how long the summary and tasks of [audio] take with [a].
  Future<Duration> estimateTasks(TaskAi a, Duration audio) async =>
      Duration(milliseconds: (audio.inMilliseconds * await tasksRtf(a)).round());
}

final speedBookProvider = Provider<SpeedBook>((ref) => SpeedBook(ref.watch(settingsRepositoryProvider)));
