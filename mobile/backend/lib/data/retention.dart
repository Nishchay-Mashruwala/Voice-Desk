import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'recordings_repository.dart';

/// Settings → Storage → "Keep recordings for": days, 0 = forever.
const kKeepAudioKey = 'keep_audio_days';
const kKeepAudioChoices = [0, 7, 30, 90, 365];
const kKeepAudioDefault = 30;

final keepAudioProvider = AsyncNotifierProvider<KeepAudio, int>(KeepAudio.new);

class KeepAudio extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final days = int.tryParse(await ref.read(settingsRepositoryProvider).getString(kKeepAudioKey));
    return kKeepAudioChoices.contains(days) ? days! : kKeepAudioDefault;
  }

  Future<void> set(int days) async {
    if (!kKeepAudioChoices.contains(days)) throw ArgumentError.value(days, 'days', 'one of $kKeepAudioChoices');
    await ref.read(settingsRepositoryProvider).setString(kKeepAudioKey, '$days');
    state = AsyncData(days);
  }
}

/// Deletes the audio of finished recordings older than [days] (their text
/// stays); 0 keeps everything. Returns how many lost their audio.
Future<int> applyRetention(RecordingsRepository repo, int days, DateTime now) async {
  if (days <= 0) return 0;
  final old = await repo.audioOlderThan(now.subtract(Duration(days: days)));
  for (final r in old) {
    await repo.deleteAudio(r.id);
  }
  return old.length;
}
