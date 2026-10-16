import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/settings_repository.dart';
import 'package:mobile_backend/engine/pipeline/speed_book.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/tasks/task_settings.dart';

void main() {
  late AppDatabase db;
  late SpeedBook book;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    book = SpeedBook(SettingsRepository(db));
  });
  tearDown(() => db.close());

  const english = SpeechSetup(languages: {Lang.en});
  const withGujarati = SpeechSetup(languages: {Lang.en, Lang.gu});
  const accurateWithBoth = SpeechSetup(languages: {Lang.en, Lang.hi, Lang.gu}, english: EnglishModel.accurate);

  test('speeds are remembered per setup, defaults until then', () async {
    expect(await book.rtf(english), 0.17);
    expect(await book.rtf(withGujarati), closeTo(0.37, 1e-9));
    expect(await book.rtf(accurateWithBoth), closeTo(1.3, 1e-9));
    await book.record(withGujarati, 0.3);
    expect(await book.rtf(withGujarati), closeTo(0.3, 1e-9));
    expect(await book.rtf(english), 0.17); // another setup's speed is its own
  });

  test('the speed is the mean of the last five jobs', () async {
    for (final r in [1.0, 0.2, 0.2, 0.2, 0.2, 0.2]) {
      await book.record(english, r);
    }
    expect(await book.rtf(english), closeTo(0.2, 1e-9));
  });

  test('a 30-min recording takes rtf × 30 min', () async {
    expect(await book.estimateFor(english, const Duration(minutes: 30)), const Duration(seconds: 306));
  });

  test('the tasks step has its speed per task model; the M31 speed test until measured', () async {
    // 1.7B: a 30-min meeting's tasks in about 24 min; 4B about twice that.
    expect(await book.estimateTasks(TaskAi.faster, const Duration(minutes: 30)), const Duration(minutes: 24));
    expect(await book.estimateTasks(TaskAi.accurate, const Duration(minutes: 30)), const Duration(minutes: 48));
    await book.recordTasks(TaskAi.faster, 0.5);
    expect(await book.estimateTasks(TaskAi.faster, const Duration(minutes: 30)), const Duration(minutes: 15));
    expect(await book.estimateTasks(TaskAi.accurate, const Duration(minutes: 30)), const Duration(minutes: 48));
    expect(await book.rtf(english), 0.17, reason: "speech's own speeds are apart");
  });
}
