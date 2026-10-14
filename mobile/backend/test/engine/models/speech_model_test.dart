import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/audio/free_space.dart';
import 'package:mobile_backend/engine/audio/recorder_controller.dart' show freeSpaceProvider;
import 'package:mobile_backend/engine/models/downloader.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:path/path.dart' as p;

/// Serves fixed bytes per URL, as a finished download would leave them.
class FakeDownloader extends Downloader {
  FakeDownloader(this.files);
  final Map<Uri, List<int>> files;
  final fetched = <Uri>[];

  @override
  Future<void> fetch(Uri url, File dest, {required int size, required String sha256, void Function(int)? onBytes}) async {
    fetched.add(url);
    await dest.parent.create(recursive: true);
    dest.writeAsBytesSync(files[url]!);
    onBytes?.call(size);
  }
}

/// A downloader that breaks with an Error (e.g. a redirect with no Location).
class BrokenDownloader extends Downloader {
  @override
  Future<void> fetch(Uri url, File dest, {required int size, required String sha256, void Function(int)? onBytes}) =>
      throw TypeError();
}

/// A store whose disk fills up while unpacking.
class FullDiskStore extends SpeechModelStore {
  FullDiskStore(Directory root) : super(root, Downloader());
  @override
  Future<void> download({void Function(int done, int total)? onProgress}) async =>
      throw const FileSystemException('No space left on device');
}

class FakeFreeSpace implements FreeSpace {
  int value = 2 * 1024 * 1024 * 1024;
  @override
  Future<int> bytesFree() async => value;
}

String sha(List<int> b) => sha256.convert(b).toString();

void main() {
  final vadBytes = List<int>.generate(1000, (i) => i % 256);
  final modelBytes = List<int>.generate(5000, (i) => (i * 3) % 256);
  final tokensBytes = 'a 0\nb 1\n'.codeUnits;
  final archiveBytes = BZip2Encoder().encodeBytes(TarEncoder().encodeBytes(Archive()
    ..add(ArchiveFile.bytes('pk/model.int8.onnx', modelBytes))
    ..add(ArchiveFile.bytes('pk/tokens.txt', tokensBytes))
    ..add(ArchiveFile.bytes('pk/test_wavs/0.wav', [1, 2, 3]))));

  final vad = ModelDownload(Uri.parse('https://x.test/vad.onnx'), vadBytes.length, sha(vadBytes));
  final pack = ModelDownload(Uri.parse('https://x.test/pk.tar.bz2'), archiveBytes.length, sha(archiveBytes));
  List<ModelMember> members({String? modelHash}) => [
        ModelMember('pk/model.int8.onnx', 'model.int8.onnx', modelBytes.length, modelHash ?? sha(modelBytes)),
        ModelMember('pk/tokens.txt', 'tokens.txt', tokensBytes.length, sha(tokensBytes)),
      ];

  late Directory root;
  late FakeDownloader downloader;
  setUp(() {
    root = Directory.systemTemp.createTempSync('models');
    downloader = FakeDownloader({vad.url: vadBytes, pack.url: archiveBytes});
  });
  tearDown(() => root.deleteSync(recursive: true));

  SpeechModelStore store({String? modelHash}) =>
      SpeechModelStore(root, downloader, vad: vad, archive: pack, members: members(modelHash: modelHash));

  test('not ready until all three files are there', () async {
    final s = store();
    expect(s.ready, isFalse);
    await s.download();
    expect(s.ready, isTrue);
    s.files.tokens.deleteSync();
    expect(s.ready, isFalse);
  });

  test('download extracts the two files, checks them and removes the archive', () async {
    final s = store();
    final seen = <int>[];
    await s.download(onProgress: (done, total) => seen.add(done));
    expect(s.files.vad.readAsBytesSync(), vadBytes);
    expect(s.files.model.readAsBytesSync(), modelBytes);
    expect(s.files.tokens.readAsBytesSync(), tokensBytes);
    final left = root.listSync(recursive: true).whereType<File>().map((f) => p.basename(f.path)).toSet();
    expect(left, {'silero_vad.onnx', 'model.int8.onnx', 'tokens.txt'});
    expect(seen.last, vadBytes.length + archiveBytes.length);
  });

  test('a member with the wrong hash fails and is not ready', () async {
    final s = store(modelHash: '0' * 64);
    await expectLater(s.download(), throwsA(isA<DownloadFailed>().having((e) => e.reason, 'reason', 'corrupt')));
    expect(s.ready, isFalse);
  });

  test('too little storage refuses to start with storage_low', () async {
    final free = FakeFreeSpace()..value = 299 * 1024 * 1024;
    final container = ProviderContainer(overrides: [
      speechModelStoreProvider.overrideWithValue(store()),
      freeSpaceProvider.overrideWithValue(free),
    ]);
    addTearDown(container.dispose);
    await container.read(speechModelProvider.notifier).download();
    final st = container.read(speechModelProvider);
    expect(st.phase, SpeechModelPhase.failed);
    expect(st.message, 'storage_low');
    expect(downloader.fetched, isEmpty);
  });

  test('the model notifier downloads to ready, and delete makes it missing again', () async {
    final container = ProviderContainer(overrides: [
      speechModelStoreProvider.overrideWithValue(store()),
      freeSpaceProvider.overrideWithValue(FakeFreeSpace()),
    ]);
    addTearDown(container.dispose);
    expect(container.read(speechModelProvider).phase, SpeechModelPhase.missing);
    await container.read(speechModelProvider.notifier).download();
    expect(container.read(speechModelProvider).phase, SpeechModelPhase.ready);
    await container.read(speechModelProvider.notifier).delete();
    expect(container.read(speechModelProvider).phase, SpeechModelPhase.missing);
    expect(store().ready, isFalse);
  });

  test('when the download is done it shows the full size while unpacking', () async {
    final container = ProviderContainer(overrides: [
      speechModelStoreProvider.overrideWithValue(store()),
      freeSpaceProvider.overrideWithValue(FakeFreeSpace()),
    ]);
    addTearDown(container.dispose);
    final seen = <SpeechModelState>[];
    container.listen(speechModelProvider, (_, s) => seen.add(s));
    await container.read(speechModelProvider.notifier).download();
    final total = vadBytes.length + archiveBytes.length;
    expect(seen.where((s) => s.phase == SpeechModelPhase.downloading && s.done == total && s.total == total), isNotEmpty);
  });

  test('any error during the download ends in failed, not stuck downloading', () async {
    final container = ProviderContainer(overrides: [
      speechModelStoreProvider.overrideWithValue(SpeechModelStore(root, BrokenDownloader())),
      freeSpaceProvider.overrideWithValue(FakeFreeSpace()),
    ]);
    addTearDown(container.dispose);
    await container.read(speechModelProvider.notifier).download();
    expect(container.read(speechModelProvider).phase, SpeechModelPhase.failed);
    expect(container.read(speechModelProvider).message, 'network');
  });

  test('an archive already downloaded is not downloaded again', () async {
    // e.g. the app was closed while unpacking
    File('${root.path}/speech/parakeet.tar.bz2')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(archiveBytes);
    final s = store();
    await s.download();
    expect(downloader.fetched, [vad.url]);
    expect(s.ready, isTrue);
  });

  test('a full disk while unpacking says storage_low', () async {
    final container = ProviderContainer(overrides: [
      speechModelStoreProvider.overrideWithValue(FullDiskStore(root)),
      freeSpaceProvider.overrideWithValue(FakeFreeSpace()),
    ]);
    addTearDown(container.dispose);
    await container.read(speechModelProvider.notifier).download();
    expect(container.read(speechModelProvider).message, 'storage_low');
  });

  test('a damaged archive fails as corrupt and leaves no temporary files', () async {
    downloader.files[pack.url] = List<int>.generate(archiveBytes.length, (i) => i % 7);
    final s = store();
    await expectLater(s.download(), throwsA(isA<DownloadFailed>().having((e) => e.reason, 'reason', 'corrupt')));
    final left = root.listSync(recursive: true).whereType<File>().map((f) => p.basename(f.path)).toSet();
    expect(left, {'silero_vad.onnx'});
  });

  test('a double tap on Download downloads once', () async {
    final container = ProviderContainer(overrides: [
      speechModelStoreProvider.overrideWithValue(store()),
      freeSpaceProvider.overrideWithValue(FakeFreeSpace()),
    ]);
    addTearDown(container.dispose);
    final model = container.read(speechModelProvider.notifier);
    await Future.wait([model.download(), model.download()]);
    expect(downloader.fetched, [vad.url, pack.url]);
    expect(container.read(speechModelProvider).phase, SpeechModelPhase.ready);
  });
}
