import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mobile_backend/data/providers.dart' show tasksRepositoryProvider;
import 'package:mobile_backend/data/settings_repository.dart';
import 'package:mobile_backend/data/tasks_repository.dart';
import 'package:mobile_backend/engine/tasks/task_answer.dart';
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/pipeline/speed_book.dart';
import 'package:mobile_backend/engine/setup_flag.dart';
import 'package:mobile_backend/engine/speakers/voice_training.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/speech/your_words.dart';
import 'package:mobile_backend/engine/tasks/task_settings.dart';

/// The models, all ready or as given; counts what the screens ask of them.
class FakeModels extends Models {
  FakeModels([this.initial = const {}]);
  final Map<ModelId, ModelState> initial;
  int neededDownloads = 0;
  final downloads = <ModelId>[];
  final deletes = <ModelId>[];

  @override
  Map<ModelId, ModelState> build() => {
        for (final id in ModelId.values) id: initial[id] ?? const ModelState(ModelPhase.ready),
      };

  @override
  bool isReady(ModelId id) => state[id]?.phase == ModelPhase.ready;

  @override
  int bytesOnDisk(ModelId id) => isReady(id) ? kCatalogue[id]!.download.size : 0;

  @override
  int bytesToDownload(ModelId id) => [...kCatalogue[id]!.needs, id]
      .where((m) => !isReady(m))
      .fold(0, (sum, m) => sum + kCatalogue[m]!.download.size);

  @override
  Future<void> downloadNeeded() async => neededDownloads++;

  @override
  Future<void> download(ModelId id) async => downloads.add(id);

  @override
  Future<void> delete(ModelId id) async => deletes.add(id);
}

/// Settings → Speech as given; records what the screen sets.
/// Tasks in memory, in the order given; what was done to them in [calls].
class FakeTasks implements TasksRepository {
  FakeTasks([List<TaskItem> items = const []]) : items = [...items];
  List<TaskItem> items;
  final calls = <String>[];
  final _changes = StreamController<void>.broadcast();

  List<TaskItem> _sorted(bool Function(TaskItem) where) =>
      [...items.where((t) => where(t) && !t.done), ...items.where((t) => where(t) && t.done)];

  Stream<List<TaskItem>> _watch(bool Function(TaskItem) where) async* {
    yield _sorted(where);
    await for (final _ in _changes.stream) {
      yield _sorted(where);
    }
  }

  void _changed() => _changes.add(null);

  void _put(int id, TaskItem Function(TaskItem t) change) {
    items = [for (final t in items) t.id == id ? change(t) : t];
    _changed();
  }

  @override
  Stream<List<TaskItem>> watchAll() => _watch((_) => true);

  @override
  Stream<List<TaskItem>> watchFor(int meetingId) => _watch((t) => t.meetingId == meetingId);

  @override
  Future<int> add(String description, {int? meetingId}) async {
    calls.add('add:$description');
    final id = items.fold(0, (m, t) => t.id > m ? t.id : m) + 1;
    items = [...items, TaskItem(id: id, description: description, meetingId: meetingId)];
    _changed();
    return id;
  }

  @override
  Future<void> edit(int id, {String? description, String? due}) async {
    calls.add('edit:$id:$description:$due');
    _put(id, (t) => t.copyWith(description: description, due: due));
  }

  @override
  Future<void> setDone(int id, bool done) async {
    calls.add('done:$id:$done');
    _put(id, (t) => t.copyWith(done: done));
  }

  @override
  Future<void> delete(int id) async {
    calls.add('delete:$id');
    items = [for (final t in items) if (t.id != id) t];
    _changed();
  }

  @override
  Future<void> restore(int id) async => calls.add('restore:$id');

  @override
  Future<void> reorder(List<int> ids) async {
    calls.add('reorder:${ids.join(',')}');
    items = [for (final id in ids) items.firstWhere((t) => t.id == id), ...items.where((t) => !ids.contains(t.id))];
    _changed();
  }

  @override
  Future<void> saveFound(int meetingId, String summary, List<(FoundTask, int?)> found) async => calls.add('found:$meetingId');
}

class FakeTaskSettings extends TaskSettingsNotifier {
  FakeTaskSettings([this.initial = const TaskSettings()]);
  final TaskSettings initial;
  final sets = <String>[];

  @override
  Future<TaskSettings> build() async => initial;

  @override
  Future<void> setFindTasks(bool on) async {
    sets.add('find_tasks:$on');
    state = AsyncData((await future).copyWith(findTasks: on));
  }

  @override
  Future<void> setAi(TaskAi ai) async {
    sets.add('task_ai:${ai.name}');
    state = AsyncData((await future).copyWith(ai: ai));
  }
}

class FakeSpeechSettings extends SpeechSettingsNotifier {
  FakeSpeechSettings([this.initial = const SpeechSettings()]);
  final SpeechSettings initial;
  final sets = <String>[];

  @override
  Future<SpeechSettings> build() async => initial;

  @override
  Future<void> setLanguages(Set<Lang> languages) async {
    sets.add('languages:${SpeechSetup(languages: languages).languagesCode}');
    state = AsyncData((await future).copyWith(languages: languages));
  }

  @override
  Future<void> setPrefer(Lang prefer) async {
    sets.add('prefer:${prefer.name}');
    state = AsyncData((await future).copyWith(prefer: prefer));
  }

  @override
  Future<void> setAccuracy(Accuracy accuracy) async {
    sets.add('accuracy:${accuracy.name}');
    state = AsyncData((await future).copyWith(accuracy: accuracy));
  }

  @override
  Future<void> setSpeakers(bool on) async {
    sets.add('speakers:$on');
    state = AsyncData((await future).copyWith(speakers: on));
  }
}

/// Settings kept in memory (for the speed estimates).
class MemorySettings implements SettingsRepository {
  final values = <String, String>{};
  @override
  Future<bool> getBool(String key, {bool orElse = false}) async => values[key] == null ? orElse : values[key] == 'true';
  @override
  Future<void> setBool(String key, bool value) async => values[key] = '$value';
  @override
  Future<String> getString(String key, {String orElse = ''}) async => values[key] ?? orElse;
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
}

/// A phone like the M31 (no dot-product): Auto picks Faster.
const m31 = PhoneClass(totalRamBytes: 6 * 1024 * 1024 * 1024, dotProduct: false);

class FakeOnlyWhileCharging extends OnlyWhileCharging {
  FakeOnlyWhileCharging([this.initial = false]);
  final bool initial;
  final sets = <bool>[];

  @override
  Future<bool> build() async => initial;

  @override
  Future<void> set(bool on) async {
    sets.add(on);
    state = AsyncData(on);
  }
}

class FakeYourWords extends YourWordsNotifier {
  FakeYourWords([this.initial = const YourWords()]);
  final YourWords initial;
  final saved = <String>[];

  @override
  Future<YourWords> build() async => initial;

  @override
  Future<void> set({String? name, String? aliases, String? vocabulary, String? leaveOut}) async {
    if (name != null) saved.add('name:$name');
    if (aliases != null) saved.add('aliases:$aliases');
    if (vocabulary != null) saved.add('vocabulary:$vocabulary');
    if (leaveOut != null) saved.add('leaveOut:$leaveOut');
  }
}

/// The first-start setup's flag as given; counts finishes.
class FakeSetupDone extends SetupDone {
  FakeSetupDone(this.initial);
  final bool initial;
  int finished = 0;
  @override
  Future<bool> build() async => initial;
  @override
  Future<void> finish() async {
    finished++;
    state = const AsyncData(true);
  }
}

/// Processing doing nothing (the screens' tests don't run the real one).
class IdleProcessor extends Processor {
  IdleProcessor([this.initial = const ProcessingState()]);
  final ProcessingState initial;
  final retried = <int>[];

  @override
  ProcessingState build() => initial;

  @override
  void kick() {}

  /// Processing starts on [id] (as when the phone is plugged in).
  void startWorkingOn(int id) => state = ProcessingState(recordingId: id, title: 'Weekly review');

  @override
  Future<void> retry(int id) async => retried.add(id);

  final findingTasks = <int>[];
  @override
  Future<void> findTasks(int id) async => findingTasks.add(id);

  final again = <(int, SpeechSetup)>[];
  @override
  Future<void> processAgain(int id, SpeechSetup setup) async {
    if (processAgainError != null) throw processAgainError!;
    again.add((id, setup));
  }

  /// What Process again throws (e.g. its audio went meanwhile).
  Object? processAgainError;
}

const readyModels = SpeechModelsState(ModelPhase.ready);

/// Overrides the backend parts the screens read but these tests don't exercise.
List<Override> quietBackend({
  SpeechModelsState needed = readyModels,
  FakeModels? models,
  FakeSpeechSettings? speech,
  FakeOnlyWhileCharging? charging,
  ProcessingState processing = const ProcessingState(),
  IdleProcessor? processor,
  FakeYourWords? yourWords,
  (Float32List?, DateTime?) myVoice = (null, null),
  FakeSetupDone? setup,
  FakeTaskSettings? tasks,
  PhoneClass phone = m31,
  FakeTasks? taskList,
}) => [
  modelsProvider.overrideWith(() => models ?? FakeModels()),
  neededModelsProvider.overrideWithValue(needed),
  speechSettingsProvider.overrideWith(() => speech ?? FakeSpeechSettings()),
  phoneClassProvider.overrideWith((ref) async => phone),
  taskSettingsProvider.overrideWith(() => tasks ?? FakeTaskSettings()),
  tasksRepositoryProvider.overrideWithValue(taskList ?? FakeTasks()),
  speedBookProvider.overrideWithValue(SpeedBook(MemorySettings())),
  onlyWhileChargingProvider.overrideWith(() => charging ?? FakeOnlyWhileCharging()),
  processorProvider.overrideWith(() => processor ?? IdleProcessor(processing)),
  yourWordsProvider.overrideWith(() => yourWords ?? FakeYourWords()),
  myVoiceProvider.overrideWith((ref) async => myVoice),
  setupDoneProvider.overrideWith(() => setup ?? FakeSetupDone(true)),
];
