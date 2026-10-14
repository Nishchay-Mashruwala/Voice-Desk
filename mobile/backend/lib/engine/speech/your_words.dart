import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/transcript.dart';
import 'leave_out.dart';
import 'vocabulary.dart';

const kNameKey = 'user_name';
const kVocabularyKey = 'vocabulary';
const kLeaveOutKey = 'leave_out';

/// Settings → "You and your words", as on the desktop.
@immutable
class YourWords {
  const YourWords({this.name = '', this.vocabulary = '', this.leaveOut = ''});

  final String name;

  /// Words to get right; entries separated by commas or new lines.
  final String vocabulary;

  /// Words never written ("umm, uh, the the").
  final String leaveOut;

  bool get isEmpty => name.trim().isEmpty && vocabulary.trim().isEmpty && leaveOut.trim().isEmpty;

  @override
  bool operator ==(Object other) =>
      other is YourWords && other.name == name && other.vocabulary == vocabulary && other.leaveOut == leaveOut;

  @override
  int get hashCode => Object.hash(name, vocabulary, leaveOut);
}

final yourWordsProvider = AsyncNotifierProvider<YourWordsNotifier, YourWords>(YourWordsNotifier.new);

class YourWordsNotifier extends AsyncNotifier<YourWords> {
  @override
  Future<YourWords> build() async {
    final settings = ref.read(settingsRepositoryProvider);
    return YourWords(
      name: await settings.getString(kNameKey),
      vocabulary: await settings.getString(kVocabularyKey),
      leaveOut: await settings.getString(kLeaveOutKey),
    );
  }

  /// Saves what's given; the rest stays.
  Future<void> set({String? name, String? vocabulary, String? leaveOut}) async {
    final settings = ref.read(settingsRepositoryProvider);
    final now = await future;
    if (name != null) await settings.setString(kNameKey, name);
    if (vocabulary != null) await settings.setString(kVocabularyKey, vocabulary);
    if (leaveOut != null) await settings.setString(kLeaveOutKey, leaveOut);
    state = AsyncData(YourWords(
      name: name ?? now.name,
      vocabulary: vocabulary ?? now.vocabulary,
      leaveOut: leaveOut ?? now.leaveOut,
    ));
  }
}

/// The bundled list of ordinary English words (from the desktop).
final commonWordsProvider = FutureProvider<CommonWords>(
  (ref) async => CommonWords.parse(await rootBundle.loadString('packages/mobile_backend/assets/english-words.txt')),
);

/// The name, vocabulary and Leave out, applied to each new transcript line.
class TranscriptPolish {
  const TranscriptPolish(this._vocabulary, this._leaveOut);

  static final none = TranscriptPolish(Vocabulary(const [], CommonWords({})), LeaveOut(''));

  final Vocabulary _vocabulary;
  final LeaveOut _leaveOut;

  /// Vocabulary first (so a fixed name can't be left out by accident of
  /// spelling), then Leave out; a line left empty is dropped.
  List<Phrase> apply(List<Phrase> lines) => [
        for (final line in lines) ?_leaveOut.phrase(_vocabulary.apply(line)),
      ];
}

/// What new lines get: read when a job (or a live step) starts. Nothing set:
/// nothing to do, and the word list isn't even loaded.
final transcriptPolishProvider = FutureProvider<TranscriptPolish>((ref) async {
  final words = await ref.watch(yourWordsProvider.future);
  if (words.isEmpty) return TranscriptPolish.none;
  final common = await ref.watch(commonWordsProvider.future);
  return TranscriptPolish(
    Vocabulary.fromSettings(name: words.name, vocabulary: words.vocabulary, common: common),
    LeaveOut(words.leaveOut),
  );
});
