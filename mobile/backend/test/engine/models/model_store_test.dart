import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/audio/free_space.dart';
import 'package:mobile_backend/engine/audio/recorder_controller.dart' show freeSpaceProvider;
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/downloader.dart';
import 'package:mobile_backend/engine/models/model_store.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:path/path.dart' as p;

/// Serves fixed bytes per URL, as a finished download would leave them.
class FakeDownloader extends Downloader {
  FakeDownloader(this.files);
  final Map<Uri, List<int>> files;
  final fetched = <Uri>[];
  final asked = <Uri, (int, String)>{};

  @override
  Future<void> fetch(Uri url, File dest, {required int size, required String sha256, void Function(int)? onBytes}) async {
    fetched.add(url);
    asked[url] = (size, sha256);
    // A real download takes a while: a second caller must not start another.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await dest.parent.create(recursive: true);
    dest.writeAsBytesSync(files[url]!);
    onBytes?.call(size);
  }
}

/// Serves files, but the first fetch of [failing] breaks off.
class FlakyDownloader extends FakeDownloader {
  FlakyDownloader(super.files, this.failing);
  final Uri failing;
  var failed = false;

  @override
  Future<void> fetch(Uri url, File dest, {required int size, required String sha256, void Function(int)? onBytes}) async {
    if (url == failing && !failed) {
      failed = true;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      throw const DownloadFailed('network');
    }
    return super.fetch(url, dest, size: size, sha256: sha256, onBytes: onBytes);
  }
}

/// A downloader that breaks with an Error (e.g. a redirect with no Location).
class BrokenDownloader extends Downloader {
  @override
  Future<void> fetch(Uri url, File dest, {required int size, required String sha256, void Function(int)? onBytes}) =>
      throw TypeError();
}

/// A store whose disk fills up while unpacking.
class FullDiskStore extends ModelStore {
  FullDiskStore(Directory root, Map<ModelId, ModelSpec> catalogue) : super(root, Downloader(), catalogue: catalogue);
  @override
  Future<void> download(ModelId id, {void Function(int done, int total)? onProgress}) async =>
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
  final encoderBytes = List<int>.generate(5000, (i) => (i * 3) % 256);
  final tokensBytes = 'a 0\nb 1\n'.codeUnits;
  final archiveBytes = BZip2Encoder().encodeBytes(TarEncoder().encodeBytes(Archive()
    ..add(ArchiveFile.bytes('pk/encoder.int8.onnx', encoderBytes))
    ..add(ArchiveFile.bytes('pk/tokens.txt', tokensBytes))
    ..add(ArchiveFile.bytes('pk/test_wavs/0.wav', [1, 2, 3]))));
  final indicTokensBytes = 'x 0\ny 1\nz 2\n'.codeUnits;
  final guBytes = List<int>.generate(3000, (i) => (i * 5) % 256);
  final hiBytes = List<int>.generate(3100, (i) => (i * 11) % 256);

  ModelDownload dl(String name, List<int> bytes) => ModelDownload(Uri.parse('https://x.test/$name'), bytes.length, sha(bytes));
  final vadDl = dl('vad.onnx', vadBytes);
  final packDl = dl('pk.tar.bz2', archiveBytes);
  final tokDl = dl('tokens.txt', indicTokensBytes);
  final guDl = dl('gu.onnx', guBytes);
  final hiDl = dl('hi.onnx', hiBytes);

  Map<ModelId, ModelSpec> catalogue({String? encoderHash}) => {
        ModelId.vad: ModelSpec(id: ModelId.vad, folder: '', download: vadDl, fileName: 'silero_vad.onnx'),
        ModelId.englishFaster: ModelSpec(id: ModelId.englishFaster, folder: 'en', download: packDl, members: [
          ModelMember('pk/encoder.int8.onnx', 'encoder.int8.onnx', encoderBytes.length, encoderHash ?? sha(encoderBytes)),
          ModelMember('pk/tokens.txt', 'tokens.txt', tokensBytes.length, sha(tokensBytes)),
        ]),
        ModelId.indicTokens: ModelSpec(id: ModelId.indicTokens, folder: 'indic', download: tokDl, fileName: 'tokens.txt'),
        ModelId.gujarati: ModelSpec(
            id: ModelId.gujarati, folder: 'indic', download: guDl, fileName: 'gu.int8.onnx', needs: [ModelId.indicTokens]),
        ModelId.hindi: ModelSpec(
            id: ModelId.hindi, folder: 'indic', download: hiDl, fileName: 'hi.int8.onnx', needs: [ModelId.indicTokens]),
      };

  late Directory root;
  late FakeDownloader downloader;
  setUp(() {
    root = Directory.systemTemp.createTempSync('models');
    downloader = FakeDownloader({
      vadDl.url: vadBytes,
      packDl.url: archiveBytes,
      tokDl.url: indicTokensBytes,
      guDl.url: guBytes,
      hiDl.url: hiBytes,
    });
  });
  tearDown(() => root.deleteSync(recursive: true));

  ModelStore store({String? encoderHash}) => ModelStore(root, downloader, catalogue: catalogue(encoderHash: encoderHash));

  ProviderContainer models({ModelStore? using, FakeFreeSpace? free}) {
    final c = ProviderContainer(overrides: [
      modelStoreProvider.overrideWithValue(using ?? store()),
      freeSpaceProvider.overrideWithValue(free ?? FakeFreeSpace()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Set<String> filesLeft() => root.listSync(recursive: true).whereType<File>().map((f) => p.basename(f.path)).toSet();

  group('store', () {
    test('an archive model is not ready until all its files are there', () async {
      final s = store();
      expect(s.ready(ModelId.englishFaster), isFalse);
      await s.download(ModelId.englishFaster);
      expect(s.ready(ModelId.englishFaster), isTrue);
      s.file(ModelId.englishFaster, 'tokens.txt').deleteSync();
      expect(s.ready(ModelId.englishFaster), isFalse);
    });

    test('an archive model is unpacked to its folder and checked', () async {
      final s = store();
      final seen = <int>[];
      await s.download(ModelId.englishFaster, onProgress: (done, total) => seen.add(done));
      expect(File('${root.path}/speech/en/encoder.int8.onnx').readAsBytesSync(), encoderBytes);
      expect(File('${root.path}/speech/en/tokens.txt').readAsBytesSync(), tokensBytes);
      expect(filesLeft(), {'encoder.int8.onnx', 'tokens.txt'});
      expect(seen.last, archiveBytes.length);
    });

    test('a member with the wrong hash fails and is not ready', () async {
      final s = store(encoderHash: '0' * 64);
      await expectLater(
          s.download(ModelId.englishFaster), throwsA(isA<DownloadFailed>().having((e) => e.reason, 'reason', 'corrupt')));
      expect(s.ready(ModelId.englishFaster), isFalse);
    });

    test('a damaged archive fails as corrupt and leaves no temporary files', () async {
      downloader.files[packDl.url] = List<int>.generate(archiveBytes.length, (i) => i % 7);
      await expectLater(
          store().download(ModelId.englishFaster), throwsA(isA<DownloadFailed>().having((e) => e.reason, 'reason', 'corrupt')));
      expect(filesLeft(), isEmpty);
    });

    test('an archive already downloaded is not downloaded again', () async {
      // e.g. the app was closed while unpacking
      File('${root.path}/speech/en.tar.bz2')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(archiveBytes);
      final s = store();
      await s.download(ModelId.englishFaster);
      expect(downloader.fetched, isEmpty);
      expect(s.ready(ModelId.englishFaster), isTrue);
    });

    test('a single-file model is fetched to its place with its size and SHA-256', () async {
      final s = store();
      await s.download(ModelId.gujarati);
      expect(File('${root.path}/speech/indic/gu.int8.onnx').readAsBytesSync(), guBytes);
      expect(downloader.asked[guDl.url], (guBytes.length, sha(guBytes)));
      expect(s.ready(ModelId.gujarati), isTrue);
    });

    test('a single-file model resumes and is checked', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final ranges = <String?>[];
      server.listen((req) async {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        ranges.add(range);
        final from = range == null ? 0 : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        if (range != null) req.response.statusCode = HttpStatus.partialContent;
        req.response.add(guBytes.sublist(from));
        await req.response.close();
      });
      final url = Uri.parse('http://127.0.0.1:${server.port}/gu.onnx');
      ModelStore real(String hash) => ModelStore(root, Downloader(), catalogue: {
            ModelId.gujarati: ModelSpec(
                id: ModelId.gujarati, folder: 'indic', download: ModelDownload(url, guBytes.length, hash), fileName: 'gu.int8.onnx'),
          });
      File('${root.path}/speech/indic/gu.int8.onnx.part')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(guBytes.sublist(0, 1000));
      await real(sha(guBytes)).download(ModelId.gujarati);
      expect(ranges, ['bytes=1000-']);
      expect(File('${root.path}/speech/indic/gu.int8.onnx').readAsBytesSync(), guBytes);

      File('${root.path}/speech/indic/gu.int8.onnx').deleteSync();
      await expectLater(
          real('0' * 64).download(ModelId.gujarati), throwsA(isA<DownloadFailed>().having((e) => e.reason, 'reason', 'corrupt')));
      expect(real('0' * 64).ready(ModelId.gujarati), isFalse);
    });

    test("bytesOnDisk counts a model's files", () async {
      final s = store();
      expect(s.bytesOnDisk(ModelId.englishFaster), 0);
      await s.download(ModelId.englishFaster);
      expect(s.bytesOnDisk(ModelId.englishFaster), encoderBytes.length + tokensBytes.length);
      await s.download(ModelId.gujarati);
      expect(s.bytesOnDisk(ModelId.gujarati), guBytes.length);
    });

    test('the old CTC model is removed', () async {
      final old = Directory('${root.path}/speech/parakeet')..createSync(recursive: true);
      File('${old.path}/model.int8.onnx').writeAsBytesSync([1, 2, 3]);
      File('${root.path}/speech/parakeet.tar.bz2.part').writeAsBytesSync([4]);
      final s = store();
      await s.download(ModelId.vad);
      await s.removeOldCtc();
      expect(old.existsSync(), isFalse);
      expect(filesLeft(), {'silero_vad.onnx'});
    });

    test('free storage needed: three times an archive, a file plus 100 MB', () {
      final c = catalogue();
      expect(minFreeToDownload(c[ModelId.englishFaster]!), 3 * archiveBytes.length);
      expect(minFreeToDownload(c[ModelId.gujarati]!), guBytes.length + 100 * 1024 * 1024);
    });
  });

  group('models', () {
    test('a model downloads to ready, and delete makes it missing again', () async {
      final c = models();
      expect(c.read(modelsProvider)[ModelId.englishFaster]!.phase, ModelPhase.missing);
      await c.read(modelsProvider.notifier).download(ModelId.englishFaster);
      expect(c.read(modelsProvider)[ModelId.englishFaster]!.phase, ModelPhase.ready);
      await c.read(modelsProvider.notifier).delete(ModelId.englishFaster);
      expect(c.read(modelsProvider)[ModelId.englishFaster]!.phase, ModelPhase.missing);
      expect(store().ready(ModelId.englishFaster), isFalse);
    });

    test('downloading Gujarati gets the shared tokens first', () async {
      final c = models();
      await c.read(modelsProvider.notifier).download(ModelId.gujarati);
      expect(downloader.fetched, [tokDl.url, guDl.url]);
      expect(c.read(modelsProvider)[ModelId.gujarati]!.phase, ModelPhase.ready);
      expect(c.read(modelsProvider)[ModelId.indicTokens]!.phase, ModelPhase.ready);
    });

    test('downloading Gujarati and Hindi together fetches the shared tokens once', () async {
      final c = models();
      final m = c.read(modelsProvider.notifier);
      await Future.wait([m.download(ModelId.gujarati), m.download(ModelId.hindi)]);
      expect(downloader.fetched.where((u) => u == tokDl.url), hasLength(1));
      expect(m.isReady(ModelId.gujarati) && m.isReady(ModelId.hindi), isTrue);
    });

    test('deleting Hindi keeps the shared tokens while Gujarati is there', () async {
      final c = models();
      final m = c.read(modelsProvider.notifier);
      await m.download(ModelId.gujarati);
      await m.download(ModelId.hindi);
      await m.delete(ModelId.hindi);
      expect(m.isReady(ModelId.indicTokens), isTrue);
      expect(m.isReady(ModelId.gujarati), isTrue);
    });

    test('deleting the last Indian model deletes the shared tokens too', () async {
      final c = models();
      final m = c.read(modelsProvider.notifier);
      await m.download(ModelId.gujarati);
      await m.delete(ModelId.gujarati);
      expect(m.isReady(ModelId.indicTokens), isFalse);
      expect(c.read(modelsProvider)[ModelId.indicTokens]!.phase, ModelPhase.missing);
      expect(filesLeft(), isEmpty);
    });

    test('the bytes to download count the shared tokens only while missing', () async {
      final c = models();
      final m = c.read(modelsProvider.notifier);
      expect(m.bytesToDownload(ModelId.gujarati), guBytes.length + indicTokensBytes.length);
      await m.download(ModelId.hindi);
      expect(m.bytesToDownload(ModelId.gujarati), guBytes.length);
      expect(m.bytesToDownload(ModelId.hindi), 0);
    });

    test('not enough free space fails as storage_low', () async {
      // Three times the archive is needed; a little less is there.
      final c = models(free: FakeFreeSpace()..value = 3 * archiveBytes.length - 1);
      await c.read(modelsProvider.notifier).download(ModelId.englishFaster);
      final st = c.read(modelsProvider)[ModelId.englishFaster]!;
      expect(st.phase, ModelPhase.failed);
      expect(st.message, 'storage_low');
      expect(downloader.fetched, isEmpty);
    });

    test('when the download is done it shows the full size while unpacking', () async {
      final c = models();
      final seen = <ModelState>[];
      c.listen(modelsProvider, (_, s) => seen.add(s[ModelId.englishFaster]!));
      await c.read(modelsProvider.notifier).download(ModelId.englishFaster);
      final total = archiveBytes.length;
      expect(seen.where((s) => s.phase == ModelPhase.downloading && s.done == total && s.total == total), isNotEmpty);
    });

    test('any error during the download ends in failed, not stuck downloading', () async {
      final c = models(using: ModelStore(root, BrokenDownloader(), catalogue: catalogue()));
      await c.read(modelsProvider.notifier).download(ModelId.gujarati);
      expect(c.read(modelsProvider)[ModelId.gujarati]!.phase, ModelPhase.failed);
      expect(c.read(modelsProvider)[ModelId.gujarati]!.message, 'network');
    });

    test('a full disk while unpacking says storage_low', () async {
      final c = models(using: FullDiskStore(root, catalogue()));
      await c.read(modelsProvider.notifier).download(ModelId.englishFaster);
      expect(c.read(modelsProvider)[ModelId.englishFaster]!.message, 'storage_low');
    });

    test('a double tap on Download downloads once', () async {
      final c = models();
      final m = c.read(modelsProvider.notifier);
      await Future.wait([m.download(ModelId.englishFaster), m.download(ModelId.englishFaster)]);
      expect(downloader.fetched, [packDl.url]);
      expect(c.read(modelsProvider)[ModelId.englishFaster]!.phase, ModelPhase.ready);
    });

    test('a shared part that failed in another download is not marked done', () async {
      final flaky = FlakyDownloader(downloader.files, tokDl.url);
      final c = models(using: ModelStore(root, flaky, catalogue: catalogue()));
      final m = c.read(modelsProvider.notifier);
      // The tokens' own download starts first and fails; Gujarati waits on it.
      await Future.wait([m.download(ModelId.indicTokens), m.download(ModelId.gujarati)]);
      expect(m.isReady(ModelId.indicTokens), isFalse);
      expect(c.read(modelsProvider)[ModelId.indicTokens]!.phase, isNot(ModelPhase.ready));
      expect(c.read(modelsProvider)[ModelId.gujarati]!.phase, ModelPhase.failed);
      // Trying again gets both.
      await m.download(ModelId.gujarati);
      expect(m.isReady(ModelId.indicTokens) && m.isReady(ModelId.gujarati), isTrue);
    });

    test('Download works again when the files are gone though it showed as done', () async {
      final c = models();
      final m = c.read(modelsProvider.notifier);
      await m.download(ModelId.englishFaster);
      await store().delete(ModelId.englishFaster); // e.g. removed outside the app
      expect(c.read(modelsProvider)[ModelId.englishFaster]!.phase, ModelPhase.ready);
      await m.download(ModelId.englishFaster);
      expect(downloader.fetched.where((u) => u == packDl.url), hasLength(2));
      expect(m.isReady(ModelId.englishFaster), isTrue);
    });
  });
}
