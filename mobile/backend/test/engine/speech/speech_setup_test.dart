import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/engine/audio/free_space.dart';
import 'package:mobile_backend/engine/audio/recorder_controller.dart' show freeSpaceProvider;
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/downloader.dart';
import 'package:mobile_backend/engine/models/model_store.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/tasks/task_settings.dart';

const _gib = 1024 * 1024 * 1024;

/// Models are ready when the test says so; a download moves step by step.
class StepStore extends ModelStore {
  StepStore() : super(Directory.systemTemp, Downloader());
  final readyNow = <ModelId>{};
  final steps = <ModelId, StreamController<int>>{};
  final fetched = <ModelId>[];

  @override
  bool ready(ModelId id) => readyNow.contains(id);

  @override
  Future<void> download(ModelId id, {void Function(int done, int total)? onProgress}) async {
    fetched.add(id);
    final c = steps[id];
    if (c != null) {
      await for (final done in c.stream) {
        onProgress?.call(done, spec(id).download.size);
      }
    }
    readyNow.add(id);
  }
}

class FakeFreeSpace implements FreeSpace {
  @override
  Future<int> bytesFree() async => 100 * _gib;
}

void main() {
  late AppDatabase db;
  late StepStore store;
  late ProviderContainer c;

  ProviderContainer make({PhoneClass phone = const PhoneClass(totalRamBytes: 6 * _gib, dotProduct: false)}) {
    final x = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      recordingsRootProvider.overrideWithValue(Directory.systemTemp.createTempSync('setup')),
      modelStoreProvider.overrideWithValue(store),
      freeSpaceProvider.overrideWithValue(FakeFreeSpace()),
      phoneClassProvider.overrideWith((ref) async => phone),
    ]);
    addTearDown(x.dispose);
    return x;
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = StepStore();
    c = make();
  });
  tearDown(() => db.close());

  test('the default is English only, Gujarati preferred, Auto', () async {
    final s = await c.read(speechSettingsProvider.future);
    expect(s.languages, {Lang.en});
    expect(s.prefer, Lang.gu);
    expect(s.accuracy, Accuracy.auto);
  });

  test("languages can't all be turned off", () async {
    final n = c.read(speechSettingsProvider.notifier);
    await n.setLanguages({Lang.gu});
    await expectLater(n.setLanguages({}), throwsArgumentError);
    expect((await c.read(speechSettingsProvider.future)).languages, {Lang.gu});
  });

  test('the settings are kept', () async {
    final n = c.read(speechSettingsProvider.notifier);
    await n.setLanguages({Lang.gu, Lang.en});
    await n.setPrefer(Lang.hi);
    await n.setAccuracy(Accuracy.accurate);
    final again = make();
    final s = await again.read(speechSettingsProvider.future);
    expect(s.languages, {Lang.en, Lang.gu});
    expect(s.prefer, Lang.hi);
    expect(s.accuracy, Accuracy.accurate);
  });

  test('Auto is Faster without dot-product or under 5.5 GiB, More accurate with both', () {
    expect(const PhoneClass(totalRamBytes: 8 * _gib, dotProduct: false).auto, EnglishModel.faster);
    expect(const PhoneClass(totalRamBytes: 5 * _gib, dotProduct: true).auto, EnglishModel.faster);
    expect(const PhoneClass(totalRamBytes: 11 * _gib ~/ 2, dotProduct: true).auto, EnglishModel.accurate);
    expect(const PhoneClass(totalRamBytes: 8 * _gib, dotProduct: true).auto, EnglishModel.accurate);
  });

  test('dot-product is read from the CPU features', () {
    const m31 = 'processor\t: 0\nFeatures\t: fp asimd evtstrm aes pmull sha1 sha2 crc32 cpuid\nCPU part\t: 0xd03\n';
    const newer = 'processor\t: 0\nFeatures\t: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp\n';
    expect(hasDotProduct(m31), isFalse);
    expect(hasDotProduct(newer), isTrue);
    expect(hasDotProduct(''), isFalse);
  });

  test('the setup now resolves Auto for this phone', () async {
    final fast = make(phone: const PhoneClass(totalRamBytes: 8 * _gib, dotProduct: true));
    expect((await fast.read(speechSetupProvider.future)).english, EnglishModel.accurate);
    expect((await c.read(speechSetupProvider.future)).english, EnglishModel.faster);
    await c.read(speechSettingsProvider.notifier).setAccuracy(Accuracy.accurate);
    expect((await c.read(speechSetupProvider.future)).english, EnglishModel.accurate);
  });

  test('a setup needs only the models of its languages', () {
    expect(const SpeechSetup(languages: {Lang.en}).models, [ModelId.vad, ModelId.englishFaster]);
    expect(const SpeechSetup(languages: {Lang.en, Lang.gu}, english: EnglishModel.accurate).models,
        [ModelId.vad, ModelId.englishAccurate, ModelId.indicTokens, ModelId.gujarati]);
    expect(const SpeechSetup(languages: {Lang.gu}).models, [ModelId.vad, ModelId.indicTokens, ModelId.gujarati]);
    expect(const SpeechSetup(languages: {Lang.en, Lang.hi, Lang.gu}).models,
        [ModelId.vad, ModelId.englishFaster, ModelId.indicTokens, ModelId.hindi, ModelId.gujarati]);
  });

  test('a setup is stored as text and read back the same', () {
    const s = SpeechSetup(languages: {Lang.gu, Lang.en}, prefer: Lang.hi, english: EnglishModel.accurate);
    expect(s.languagesCode, 'en,gu');
    expect(SpeechSetup.parse('en,gu', 'hi', 'accurate'), s);
    expect(SpeechSetup.parse('', 'xx', 'yy'), SpeechSetup.englishOnly);
    expect(s.key, 'accurate+gu');
    expect(const SpeechSetup(languages: {Lang.gu, Lang.hi}).key, 'hi+gu');
  });

  test('needed models are ready only when all are', () async {
    await c.read(speechSettingsProvider.notifier).setSpeakers(false); // languages only here
    await c.read(taskSettingsProvider.notifier).setFindTasks(false);
    await c.read(speechSettingsProvider.notifier).setLanguages({Lang.en, Lang.gu});
    await c.read(speechSetupProvider.future);
    store.readyNow.addAll([ModelId.vad, ModelId.englishFaster]);
    c.invalidate(modelsProvider);
    var needed = c.read(neededModelsProvider);
    expect(needed.phase, ModelPhase.missing);
    expect(needed.bytesToDownload, 67605 + 197595461);
    store.readyNow.addAll([ModelId.indicTokens, ModelId.gujarati]);
    c.invalidate(modelsProvider);
    needed = c.read(neededModelsProvider);
    expect(needed.phase, ModelPhase.ready);
    expect(needed.bytesToDownload, 0);
  });

  test('downloading what the settings need fetches each missing model, and its progress never goes back', () async {
    await c.read(speechSettingsProvider.notifier).setSpeakers(false); // languages only here
    await c.read(taskSettingsProvider.notifier).setFindTasks(false);
    await c.read(speechSettingsProvider.notifier).setLanguages({Lang.en, Lang.gu});
    await c.read(speechSetupProvider.future);
    store.readyNow.add(ModelId.vad);
    c.invalidate(modelsProvider);
    final en = store.steps[ModelId.englishFaster] = StreamController<int>();
    final gu = store.steps[ModelId.gujarati] = StreamController<int>();
    final seen = <double>[];
    c.listen(neededModelsProvider, (_, s) {
      if (s.phase == ModelPhase.downloading && s.total > 0) seen.add(s.done / s.total);
    });
    final run = c.read(modelsProvider.notifier).downloadNeeded();
    await pumpEventQueue();
    en.add(54000000);
    await pumpEventQueue();
    await en.close();
    await pumpEventQueue();
    gu.add(100000000);
    await pumpEventQueue();
    await gu.close();
    await run;
    expect(store.fetched, [ModelId.englishFaster, ModelId.indicTokens, ModelId.gujarati]);
    expect(c.read(neededModelsProvider).phase, ModelPhase.ready);
    expect(seen, isNotEmpty);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
  });

  test("a waiting recording's models count even when the settings no longer need them", () async {
    await c.read(speechSettingsProvider.notifier).setSpeakers(false); // languages only here
    await c.read(taskSettingsProvider.notifier).setFindTasks(false);
    // Made with Gujarati; its download failed; Gujarati was then turned off.
    final repo = c.read(recordingsRepositoryProvider);
    final r = await repo.create(startedAt: DateTime(2026, 10, 14, 9), setup: const SpeechSetup(languages: {Lang.en, Lang.gu}));
    await repo.finish(r.id, const Duration(seconds: 30));
    store.readyNow.addAll([ModelId.vad, ModelId.englishFaster]);
    await c.read(speechSetupProvider.future);
    c.listen(neededModelsProvider, (_, _) {}); // as the banner does
    c.listen(recordingsProvider, (_, _) {});
    await c.read(recordingsProvider.future);
    c.invalidate(modelsProvider);
    final needed = c.read(neededModelsProvider);
    expect(needed.phase, ModelPhase.missing);
    expect(needed.bytesToDownload, 67605 + 197595461);
    await c.read(modelsProvider.notifier).downloadNeeded();
    expect(store.fetched, [ModelId.indicTokens, ModelId.gujarati]);
    expect(c.read(neededModelsProvider).phase, ModelPhase.ready);
  });

  test('speaker detection is on by default and kept', () async {
    expect((await c.read(speechSettingsProvider.future)).speakers, isTrue);
    await c.read(speechSettingsProvider.notifier).setSpeakers(false);
    final again = make();
    expect((await again.read(speechSettingsProvider.future)).speakers, isFalse);
    expect((await again.read(speechSetupProvider.future)).speakers, isFalse);
  });

  test('a setup with speakers needs the speaker model', () {
    expect(const SpeechSetup(languages: {Lang.en}, speakers: true).models,
        [ModelId.vad, ModelId.englishFaster, ModelId.speakers]);
    expect(const SpeechSetup(languages: {Lang.en}).models, [ModelId.vad, ModelId.englishFaster]);
    expect(const SpeechSetup(languages: {Lang.en}, speakers: true), isNot(const SpeechSetup(languages: {Lang.en})));
  });
}
