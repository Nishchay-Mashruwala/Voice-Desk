import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/recording.dart';
import '../audio/recorder_controller.dart' show freeSpaceProvider;
import 'catalogue.dart';
import 'downloader.dart';
import 'model_store.dart';
import '../speech/speech_setup.dart';
import '../tasks/task_settings.dart';

enum ModelPhase { missing, downloading, ready, failed }

class ModelState {
  const ModelState(this.phase, {this.done = 0, this.total = 0, this.message});
  final ModelPhase phase;
  final int done;
  final int total;

  /// Why it failed: `storage_low`, `network`, `corrupt`.
  final String? message;
}

/// `<app support>/models`; overridden in `openBackend()`.
final modelsRootProvider = Provider<Directory>((ref) => throw UnimplementedError('modelsRootProvider not overridden'));

final modelStoreProvider = Provider<ModelStore>((ref) => ModelStore(ref.watch(modelsRootProvider), Downloader()));

final modelsProvider = NotifierProvider<Models, Map<ModelId, ModelState>>(Models.new);

/// Each model's state on the phone: download (what it needs first), delete.
class Models extends Notifier<Map<ModelId, ModelState>> {
  ModelStore get _store => ref.read(modelStoreProvider);

  /// Downloads under way, so a model two others need is fetched once.
  final _running = <ModelId, Future<void>>{};

  @override
  Map<ModelId, ModelState> build() {
    final store = ref.read(modelStoreProvider);
    return {
      for (final id in ModelId.values) id: ModelState(store.ready(id) ? ModelPhase.ready : ModelPhase.missing),
    };
  }

  /// Whether the model's files are on the phone now.
  bool isReady(ModelId id) => _store.ready(id);

  /// What the model takes on the phone now.
  int bytesOnDisk(ModelId id) => _store.has(id) ? _store.bytesOnDisk(id) : 0;

  /// What a download of everything the settings need started with, so its
  /// progress counts what is done and never goes back (0: none running).
  int get batchTotal => _batchTotal;
  int _batchTotal = 0;

  /// Downloads every model needed (see [neededModelIdsProvider]), one after another.
  Future<void> downloadNeeded() async {
    await ref.read(speechSetupProvider.future);
    await ref.read(taskModelProvider.future);
    final missing = [for (final id in ref.read(neededModelIdsProvider)) if (!isReady(id)) id];
    _batchTotal = missing.fold(0, (sum, id) => sum + _store.spec(id).download.size);
    try {
      for (final id in missing) {
        if (isReady(id)) continue; // fetched as another one's need
        await download(id);
        if (state[id]?.phase == ModelPhase.failed) return;
      }
    } finally {
      _batchTotal = 0;
      if (ref.mounted) state = {...state}; // the aggregate drops the batch
    }
  }

  List<ModelId> _missing(ModelId id) => [
        for (final need in _store.spec(id).needs)
          if (!isReady(need)) need,
        if (!isReady(id)) id,
      ];

  /// What getting [id] still costs, what it needs included.
  int bytesToDownload(ModelId id) => _missing(id).fold(0, (sum, m) => sum + _store.spec(m).download.size);

  void _put(ModelId id, ModelState s) {
    if (ref.mounted) state = {...state, id: s};
  }

  Future<void> download(ModelId id) async {
    if (state[id]?.phase == ModelPhase.downloading) return _running[id];
    // Done means its files are on the phone, whatever was shown before.
    if (isReady(id)) {
      if (state[id]?.phase != ModelPhase.ready) _put(id, const ModelState(ModelPhase.ready));
      return;
    }
    final missing = _missing(id);
    final total = missing.fold(0, (sum, m) => sum + _store.spec(m).download.size);
    // Set before the first await, so a second tap is ignored.
    _put(id, ModelState(ModelPhase.downloading, total: total));
    final run = _download(id, missing, total);
    _running[id] = run;
    try {
      await run;
    } finally {
      _running.remove(id);
    }
  }

  Future<void> _download(ModelId id, List<ModelId> missing, int total) async {
    final room = missing.fold(0, (sum, m) => sum + minFreeToDownload(_store.spec(m)));
    if (await ref.read(freeSpaceProvider).bytesFree() < room) {
      _put(id, const ModelState(ModelPhase.failed, message: 'storage_low'));
      return;
    }
    var before = 0; // bytes of the models already fetched in this run
    var shownMb = -1;
    void progress(int done) {
      // A screen update per megabyte, not per network chunk. The end always
      // shows: it is when unpacking starts ("Preparing…").
      final at = before + done;
      final mb = at ~/ (1024 * 1024);
      if (mb == shownMb && at < total) return;
      shownMb = mb;
      _put(id, ModelState(ModelPhase.downloading, done: at, total: total));
    }

    try {
      for (final m in missing) {
        if (m == id) {
          await _store.download(m, onProgress: (done, _) => progress(done));
        } else {
          // Another download may be fetching it already: wait for that one.
          await (_running[m] ??= _store.download(m, onProgress: (done, _) => progress(done)).whenComplete(() {
            _running.remove(m); // (a `=>` here would return this very future, and wait for itself)
          }));
          // The run waited on may have been the part's own download, which
          // reports a failure in its state rather than by throwing.
          if (!isReady(m)) throw const DownloadFailed('network');
          _put(m, const ModelState(ModelPhase.ready));
        }
        before += _store.spec(m).download.size;
      }
      _put(id, const ModelState(ModelPhase.ready));
    } on DownloadFailed catch (e) {
      _put(id, ModelState(ModelPhase.failed, message: e.reason == 'corrupt' ? 'corrupt' : 'network'));
    } on FileSystemException {
      // Writing failed: the phone ran out of storage.
      _put(id, const ModelState(ModelPhase.failed, message: 'storage_low'));
    } on Object catch (e) {
      // Never left "downloading": whatever went wrong, it can be tried again.
      debugPrint('Voice Desk: ${id.name} could not be downloaded: $e');
      _put(id, const ModelState(ModelPhase.failed, message: 'network'));
    }
  }

  /// Deletes the model, and what it needed if nothing else on the phone does.
  Future<void> delete(ModelId id) async {
    await _store.delete(id);
    _put(id, const ModelState(ModelPhase.missing));
    for (final need in _store.spec(id).needs) {
      final stillUsed = ModelId.values
          .any((other) => other != id && _store.has(other) && _store.spec(other).needs.contains(need) && isReady(other));
      if (!stillUsed) {
        await _store.delete(need);
        _put(need, const ModelState(ModelPhase.missing));
      }
    }
  }
}

/// All the models the speech settings need, as one: for the Record screen's
/// banner (and the download step of the first start).
class SpeechModelsState {
  const SpeechModelsState(this.phase,
      {this.done = 0, this.total = 0, this.bytesToDownload = 0, this.freeNeeded = 0, this.message, this.missing = Missing.speech});
  final ModelPhase phase;
  final int done;
  final int total;

  /// What is still missing.
  final int bytesToDownload;

  /// Free storage the missing models need to download and unpack.
  final int freeNeeded;
  final String? message;

  /// Which kinds of model are missing (for the banner's words).
  final Missing missing;
}

/// Speech models only, the task model only, or both.
enum Missing { speech, tasks, both }

/// The models needed: those of the speech settings now, and those of every
/// recording still to be turned into text (made with other settings, e.g. a
/// language turned off since), so none waits without a way to get them; and
/// the task model while Find tasks is on (last: speech comes first).
final neededModelIdsProvider = Provider<List<ModelId>>((ref) {
  final setup = ref.watch(speechSetupProvider).value ?? SpeechSetup.englishOnly;
  final task = ref.watch(taskModelProvider).value;
  const waiting = {RecordingStatus.recording, RecordingStatus.queued, RecordingStatus.processing, RecordingStatus.waitingCharge};
  final ids = {
    ...setup.models,
    for (final r in ref.watch(recordingsProvider).value ?? const <Recording>[])
      if (waiting.contains(r.status)) ...r.setup.models,
    ?task,
  };
  return [for (final id in ModelId.values) if (ids.contains(id)) id]; // download order
});

final neededModelsProvider = Provider<SpeechModelsState>((ref) {
  final states = ref.watch(modelsProvider);
  final models = ref.read(modelsProvider.notifier);
  final store = ref.read(modelStoreProvider);
  final ids = [for (final id in ref.watch(neededModelIdsProvider)) if (store.has(id)) id];
  final missing = [for (final id in ids) if (!models.isReady(id)) id];
  final left = missing.fold(0, (sum, id) => sum + store.spec(id).download.size);
  bool isTask(ModelId id) => id == ModelId.taskFaster || id == ModelId.taskAccurate;
  final kinds = missing.every(isTask) ? Missing.tasks : (missing.any(isTask) ? Missing.both : Missing.speech);
  final room = missing.fold(0, (sum, id) => sum + minFreeToDownload(store.spec(id)));
  if (missing.isEmpty) return const SpeechModelsState(ModelPhase.ready);
  final running = [for (final id in missing) if (states[id]?.phase == ModelPhase.downloading) id];
  final failed = [for (final id in missing) if (states[id]?.phase == ModelPhase.failed) id];
  if (running.isNotEmpty) {
    final inFlight = running.fold(0, (sum, id) => sum + (states[id]?.done ?? 0));
    final total = models.batchTotal > left ? models.batchTotal : left;
    final done = (total - left + inFlight).clamp(0, total);
    return SpeechModelsState(ModelPhase.downloading,
        done: done, total: total, bytesToDownload: left, freeNeeded: room, missing: kinds);
  }
  if (failed.isNotEmpty) {
    return SpeechModelsState(ModelPhase.failed,
        bytesToDownload: left, freeNeeded: room, message: states[failed.first]?.message, missing: kinds);
  }
  return SpeechModelsState(ModelPhase.missing, bytesToDownload: left, freeNeeded: room, missing: kinds);
});
