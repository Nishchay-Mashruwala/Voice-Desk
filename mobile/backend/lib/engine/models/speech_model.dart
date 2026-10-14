import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/recorder_controller.dart' show freeSpaceProvider;
import 'downloader.dart';

/// A file to download, with its exact size and SHA-256.
class ModelDownload {
  const ModelDownload(this.url, this.size, this.sha256);
  final Uri url;
  final int size;
  final String sha256;
}

/// A file kept from a downloaded archive.
class ModelMember {
  const ModelMember(this.inArchive, this.fileName, this.size, this.sha256);
  final String inArchive;
  final String fileName;
  final int size;
  final String sha256;
}

final kVadDownload = ModelDownload(
  Uri.parse('https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx'),
  643854,
  '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
);

final kParakeetDownload = ModelDownload(
  Uri.parse(
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8.tar.bz2'),
  104337827,
  '17f945007b52ccd8b7200ffc7c5652e9e8e961dfdf479cefcabd06cf5703630b',
);

const kParakeetMembers = [
  ModelMember('sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8/model.int8.onnx', 'model.int8.onnx', 131652171,
      '9177a9146cf32ee0cc8152276ef95116f312018d316be37ccf57f7efea81fc1a'),
  ModelMember('sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8/tokens.txt', 'tokens.txt', 9953,
      '450e56bd2f036fe5b6aa821865838cc5aa9d8b0106134ce9a9ba0664abe6cd10'),
];

/// Free storage needed to start the download (archive + unpacked + margin).
const kMinFreeForSpeechModel = 300 * 1024 * 1024;

/// The speech model's files on the phone.
class SpeechModelFiles {
  const SpeechModelFiles({required this.vad, required this.model, required this.tokens});
  final File vad;
  final File model;
  final File tokens;
}

/// Silero VAD + Parakeet under `<root>/speech/`.
class SpeechModelStore {
  SpeechModelStore(
    Directory root,
    this._downloader, {
    ModelDownload? vad,
    ModelDownload? archive,
    List<ModelMember> members = kParakeetMembers,
  })  : _dir = Directory('${root.path}/speech'),
        _vad = vad ?? kVadDownload,
        _archive = archive ?? kParakeetDownload,
        _members = List.unmodifiable(members);

  final Directory _dir;
  final Downloader _downloader;
  final ModelDownload _vad;
  final ModelDownload _archive;
  final List<ModelMember> _members;

  File _member(ModelMember m) => File('${_dir.path}/parakeet/${m.fileName}');

  SpeechModelFiles get files => SpeechModelFiles(
        vad: File('${_dir.path}/silero_vad.onnx'),
        model: _member(_members[0]),
        tokens: _member(_members[1]),
      );

  /// What the download costs, in bytes.
  int get downloadBytes => _vad.size + _archive.size;

  bool get ready => _sized(files.vad, _vad.size) && _members.every((m) => _sized(_member(m), m.size));

  static bool _sized(File f, int size) => f.existsSync() && f.lengthSync() == size;

  /// Downloads what's missing (resuming), unpacks and checks it.
  Future<void> download({void Function(int done, int total)? onProgress}) async {
    final total = downloadBytes;
    if (!_sized(files.vad, _vad.size)) {
      await _downloader.fetch(_vad.url, files.vad, size: _vad.size, sha256: _vad.sha256, onBytes: (n) => onProgress?.call(n, total));
    }
    onProgress?.call(_vad.size, total);
    if (!_members.every((m) => _sized(_member(m), m.size))) {
      final archive = File('${_dir.path}/parakeet.tar.bz2');
      // Already here (e.g. the app was closed while unpacking): it was checked
      // when its download finished, so it isn't fetched again.
      if (!_sized(archive, _archive.size)) {
        await _downloader.fetch(_archive.url, archive,
            size: _archive.size, sha256: _archive.sha256, onBytes: (n) => onProgress?.call(_vad.size + n, total));
      }
      onProgress?.call(total, total);
      final wanted = {for (final m in _members) m.inArchive: _member(m).path};
      try {
        await _unpackInIsolate(archive.path, wanted);
      } on DownloadFailed {
        if (archive.existsSync()) archive.deleteSync(); // damaged: fetched anew next time
        rethrow;
      }
      if (archive.existsSync()) await archive.delete();
      for (final m in _members) {
        final f = _member(m);
        if (!_sized(f, m.size) || (await sha256.bind(f.openRead()).first).toString() != m.sha256) {
          for (final x in _members) {
            if (_member(x).existsSync()) _member(x).deleteSync();
          }
          throw const DownloadFailed('corrupt');
        }
      }
    }
    onProgress?.call(total, total);
  }

  Future<void> delete() async {
    if (_dir.existsSync()) await _dir.delete(recursive: true);
  }
}

/// Unpacking a 100 MB bzip2 in Dart takes a while: off the UI's isolate. (A
/// top-level function, so the closure sent to the isolate holds only these two.)
Future<void> _unpackInIsolate(String archivePath, Map<String, String> wanted) =>
    Isolate.run(() => _unpack(archivePath, wanted));

/// bzip2 → a temporary tar → only the [wanted] entries (archive path → file
/// path). The archive is deleted once the tar holds it all (less storage at
/// the peak); the tar is always deleted.
Future<void> _unpack(String archivePath, Map<String, String> wanted) async {
  final tarFile = File('$archivePath.tar');
  try {
    final input = InputFileStream(archivePath);
    final tar = OutputFileStream(tarFile.path);
    var ok = false;
    try {
      ok = BZip2Decoder().decodeStream(input, tar);
    } on FileSystemException {
      rethrow; // a full disk is not a damaged archive
    } on Object {
      ok = false;
    } finally {
      await input.close();
      await tar.close();
    }
    if (!ok) throw const DownloadFailed('corrupt');
    File(archivePath).deleteSync();
    final tarInput = InputFileStream(tarFile.path);
    try {
      final entries = TarDecoder().decodeStream(tarInput);
      for (final entry in entries.files) {
        final name = entry.name.startsWith('./') ? entry.name.substring(2) : entry.name;
        final dest = wanted[name];
        if (dest == null || !entry.isFile) continue;
        await File(dest).parent.create(recursive: true);
        final out = OutputFileStream(dest);
        entry.writeContent(out);
        await out.close();
      }
    } finally {
      await tarInput.close();
    }
  } finally {
    if (tarFile.existsSync()) tarFile.deleteSync();
  }
}

enum SpeechModelPhase { missing, downloading, ready, failed }

class SpeechModelState {
  const SpeechModelState(this.phase, {this.done = 0, this.total = 0, this.message});
  final SpeechModelPhase phase;
  final int done;
  final int total;

  /// Why it failed: `storage_low`, `network`, `corrupt`.
  final String? message;
}

/// `<app support>/models`; overridden in `openBackend()`.
final modelsRootProvider = Provider<Directory>((ref) => throw UnimplementedError('modelsRootProvider not overridden'));

final speechModelStoreProvider =
    Provider<SpeechModelStore>((ref) => SpeechModelStore(ref.watch(modelsRootProvider), Downloader()));

final speechModelProvider = NotifierProvider<SpeechModel, SpeechModelState>(SpeechModel.new);

class SpeechModel extends Notifier<SpeechModelState> {
  SpeechModelStore get _store => ref.read(speechModelStoreProvider);

  /// Whether the files are on the phone now.
  bool get isReady => _store.ready;

  @override
  SpeechModelState build() => SpeechModelState(ref.read(speechModelStoreProvider).ready ? SpeechModelPhase.ready : SpeechModelPhase.missing);

  Future<void> download() async {
    if (state.phase == SpeechModelPhase.downloading || state.phase == SpeechModelPhase.ready) return;
    final total = _store.downloadBytes;
    // Set before the first await, so a second tap is ignored.
    state = SpeechModelState(SpeechModelPhase.downloading, total: total);
    if (await ref.read(freeSpaceProvider).bytesFree() < kMinFreeForSpeechModel) {
      state = const SpeechModelState(SpeechModelPhase.failed, message: 'storage_low');
      return;
    }
    var shownMb = -1;
    try {
      await _store.download(onProgress: (done, total) {
        // A screen update per megabyte, not per network chunk.
        // The end always shows: it is when unpacking starts ("Preparing…").
        final mb = done ~/ (1024 * 1024);
        if (mb == shownMb && done < total) return;
        shownMb = mb;
        state = SpeechModelState(SpeechModelPhase.downloading, done: done, total: total);
      });
      state = const SpeechModelState(SpeechModelPhase.ready);
    } on DownloadFailed catch (e) {
      state = SpeechModelState(SpeechModelPhase.failed, message: e.reason == 'corrupt' ? 'corrupt' : 'network');
    } on FileSystemException {
      // Writing failed: the phone ran out of storage.
      state = const SpeechModelState(SpeechModelPhase.failed, message: 'storage_low');
    } on Object {
      // Never left "downloading": whatever went wrong, it can be tried again.
      state = const SpeechModelState(SpeechModelPhase.failed, message: 'network');
    }
  }

  Future<void> delete() async {
    await _store.delete();
    state = const SpeechModelState(SpeechModelPhase.missing);
  }
}
