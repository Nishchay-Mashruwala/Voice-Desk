import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/tasks/task_settings.dart';

const _gib = 1024 * 1024 * 1024;

void main() {
  late AppDatabase db;

  ProviderContainer make({int ram = 6 * _gib}) {
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      recordingsRootProvider.overrideWithValue(Directory.systemTemp.createTempSync('tasks')),
      modelsRootProvider.overrideWithValue(Directory.systemTemp.createTempSync('models')),
      phoneClassProvider.overrideWith((ref) async => PhoneClass(totalRamBytes: ram, dotProduct: false)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('Find tasks is on by default and kept', () async {
    final c = make();
    final s = await c.read(taskSettingsProvider.future);
    expect((s.findTasks, s.ai), (true, TaskAi.faster));
    await c.read(taskSettingsProvider.notifier).setFindTasks(false);
    await c.read(taskSettingsProvider.notifier).setAi(TaskAi.accurate);
    final again = await make().read(taskSettingsProvider.future);
    expect((again.findTasks, again.ai), (false, TaskAi.accurate));
  });

  test('More accurate needs a phone with 8 GB', () async {
    // Android reports about 7.3 GiB for an 8 GB phone, 5.5 GiB for a 6 GB one.
    expect(const PhoneClass(totalRamBytes: 11 * _gib ~/ 2, dotProduct: true).canRunLargeTaskAi, isFalse);
    expect(const PhoneClass(totalRamBytes: 73 * _gib ~/ 10, dotProduct: false).canRunLargeTaskAi, isTrue);

    final small = make();
    await small.read(taskSettingsProvider.notifier).setAi(TaskAi.accurate);
    expect(await small.read(taskModelProvider.future), ModelId.taskFaster);

    final big = make(ram: 73 * _gib ~/ 10);
    expect(await big.read(taskModelProvider.future), ModelId.taskAccurate);
    await big.read(taskSettingsProvider.notifier).setAi(TaskAi.faster);
    expect(await big.read(taskModelProvider.future), ModelId.taskFaster);
  });

  test('the task model is needed while Find tasks is on', () async {
    final c = make();
    await c.read(speechSetupProvider.future);
    await c.read(taskModelProvider.future);
    expect(c.read(neededModelIdsProvider), contains(ModelId.taskFaster));
    expect(c.read(neededModelIdsProvider).last, ModelId.taskFaster, reason: 'downloaded after the speech models');
    await c.read(taskSettingsProvider.notifier).setFindTasks(false);
    expect(await c.read(taskModelProvider.future), isNull);
    expect(c.read(neededModelIdsProvider), isNot(contains(ModelId.taskFaster)));
  });

  test('the task models are pinned as the desktop', () {
    final faster = kCatalogue[ModelId.taskFaster]!, accurate = kCatalogue[ModelId.taskAccurate]!;
    expect(faster.download.url.toString(),
        'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/d7f544eead698dbd1f15126ef60b45a1e1933222/Qwen3-1.7B-Q4_K_M.gguf');
    expect((faster.download.size, faster.download.sha256),
        (1107409472, 'b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897'));
    expect(accurate.download.url.toString(),
        'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/22c9fc8a8c7700b76a1789366280a6a5a1ad1120/Qwen3-4B-Q4_K_M.gguf');
    expect((accurate.download.size, accurate.download.sha256),
        (2497281312, 'f6f851777709861056efcdad3af01da38b31223a3ba26e61a4f8bf3a2195813a'));
    expect((faster.folder, accurate.folder), ('tasks', 'tasks'));
  });

  test('the banner knows when only the task model is missing, or it with others', () async {
    final c = make();
    await c.read(speechSetupProvider.future);
    await c.read(taskModelProvider.future);
    c.listen(neededModelsProvider, (_, _) {});
    expect(c.read(neededModelsProvider).missing, Missing.both, reason: 'nothing downloaded in this test');
  });
}
