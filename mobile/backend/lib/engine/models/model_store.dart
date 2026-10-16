import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'catalogue.dart';
import 'downloader.dart';

/// The models' files under `<root>/speech/`: downloads, checks, sizes and
/// deletes one model at a time.
class ModelStore {
  ModelStore(Directory root, this._downloader, {Map<ModelId, ModelSpec>? catalogue})
      : _dir = Directory('${root.path}/speech'),
        _catalogue = catalogue ?? kCatalogue;

  final Directory _dir;
  final Downloader _downloader;
  final Map<ModelId, ModelSpec> _catalogue;

  ModelSpec spec(ModelId id) => _catalogue[id]!;

  /// Whether this store knows the model (tests use small catalogues).
  bool has(ModelId id) => _catalogue.containsKey(id);

  String _folder(ModelSpec s) => s.folder.isEmpty ? _dir.path : '${_dir.path}/${s.folder}';

  File file(ModelId id, String name) => File('${_folder(spec(id))}/$name');

  /// Where an archive waits to be unpacked.
  File _archive(ModelSpec s) => File('${_dir.path}/${s.folder}.tar.bz2');

  bool ready(ModelId id) {
    final s = _catalogue[id];
    if (s == null) return false;
    if (s.isArchive) return s.members.every((m) => _sized(file(id, m.fileName), m.size));
    return _sized(file(id, s.fileName!), s.download.size);
  }

  static bool _sized(File f, int size) => f.existsSync() && f.lengthSync() == size;

  /// What the model takes on the phone now, half-downloaded parts included.
  int bytesOnDisk(ModelId id) {
    final s = spec(id);
    final files = [
      for (final name in s.fileNames) file(id, name),
      if (!s.isArchive) File('${file(id, s.fileName!).path}.part'),
      if (s.isArchive) ...[_archive(s), File('${_archive(s).path}.part')],
    ];
    return files.where((f) => f.existsSync()).fold(0, (sum, f) => sum + f.lengthSync());
  }

  /// Downloads what's missing (resuming), unpacks and checks it.
  Future<void> download(ModelId id, {void Function(int done, int total)? onProgress}) async {
    final s = spec(id);
    final total = s.download.size;
    if (ready(id)) {
      onProgress?.call(total, total);
      return;
    }
    if (!s.isArchive) {
      await _downloader.fetch(s.download.url, file(id, s.fileName!),
          size: total, sha256: s.download.sha256, onBytes: (n) => onProgress?.call(n, total));
      onProgress?.call(total, total);
      return;
    }
    final archive = _archive(s);
    // Already here (e.g. the app was closed while unpacking): it was checked
    // when its download finished, so it isn't fetched again.
    if (!_sized(archive, total)) {
      await _downloader.fetch(s.download.url, archive,
          size: total, sha256: s.download.sha256, onBytes: (n) => onProgress?.call(n, total));
    }
    onProgress?.call(total, total);
    final wanted = {for (final m in s.members) m.inArchive: file(id, m.fileName).path};
    try {
      await _unpackInIsolate(archive.path, wanted);
    } on DownloadFailed {
      if (archive.existsSync()) archive.deleteSync(); // damaged: fetched anew next time
      rethrow;
    }
    if (archive.existsSync()) await archive.delete();
    for (final m in s.members) {
      final f = file(id, m.fileName);
      if (!_sized(f, m.size) || (await sha256.bind(f.openRead()).first).toString() != m.sha256) {
        await _deleteFiles(s);
        throw const DownloadFailed('corrupt');
      }
    }
  }

  Future<void> delete(ModelId id) => _deleteFiles(spec(id));

  Future<void> _deleteFiles(ModelSpec s) async {
    final files = [
      for (final name in s.fileNames) file(s.id, name),
      if (!s.isArchive) File('${file(s.id, s.fileName!).path}.part'),
      if (s.isArchive) ...[_archive(s), File('${_archive(s).path}.part')],
    ];
    for (final f in files) {
      if (f.existsSync()) await f.delete();
    }
    final folder = Directory(_folder(s));
    if (s.folder.isNotEmpty && folder.existsSync() && folder.listSync().isEmpty) await folder.delete();
  }

  /// Plan 2a's English model (the CTC variant), replaced by the transducer.
  Future<void> removeOldCtc() async {
    final old = Directory('${_dir.path}/parakeet');
    if (old.existsSync()) await old.delete(recursive: true);
    for (final name in ['parakeet.tar.bz2', 'parakeet.tar.bz2.part', 'parakeet.tar.bz2.tar']) {
      final f = File('${_dir.path}/$name');
      if (f.existsSync()) await f.delete();
    }
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
