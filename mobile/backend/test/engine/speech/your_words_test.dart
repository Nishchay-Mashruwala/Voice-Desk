import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/speech/leave_out.dart';
import 'package:mobile_backend/engine/speech/vocabulary.dart';
import 'package:mobile_backend/engine/speech/your_words.dart';

void main() {
  test('your name, vocabulary and Leave out are saved and read back', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    expect(await container.read(yourWordsProvider.future), const YourWords());
    await container.read(yourWordsProvider.notifier).set(name: 'Nishchay', vocabulary: 'Priya, Voice Desk');
    await container.read(yourWordsProvider.notifier).set(leaveOut: 'umm, uh');
    const saved = YourWords(name: 'Nishchay', vocabulary: 'Priya, Voice Desk', leaveOut: 'umm, uh');
    expect(container.read(yourWordsProvider).value, saved);
    // A fresh start reads them from the database.
    final again = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(again.dispose);
    expect(await again.read(yourWordsProvider.future), saved);
  });

  test('polishing: vocabulary first, then Leave out; a line left empty is dropped', () {
    final polish = TranscriptPolish(
      Vocabulary.fromSettings(name: 'Nishchay', vocabulary: '', common: CommonWords({})),
      LeaveOut('umm'),
    );
    Phrase p(String text) => Phrase(
          startMs: 0,
          endMs: 1000,
          text: text,
          words: [for (final w in text.split(' ')) Word(w, 0, 1000)],
        );
    final out = polish.apply([p('umm Nishher said yes'), p('umm')]);
    expect(out.map((l) => l.text), ['Nishher said yes'.replaceFirst('Nishher', 'Nishchay')]);
  });

  test('nothing set: polishing changes nothing', () {
    final line = Phrase(startMs: 0, endMs: 1000, text: 'umm', words: const [Word('umm', 0, 1000)]);
    expect(TranscriptPolish.none.apply([line]), [line]);
  });
}
