import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/models/downloader.dart';

void main() {
  late HttpServer server;
  late Uint8List data;
  late String hash;
  final ranges = <String?>[];
  late Directory dir;

  setUp(() async {
    data = Uint8List.fromList(List.generate(300 * 1024, (i) => (i * 7) % 251));
    hash = sha256.convert(data).toString();
    ranges.clear();
    dir = Directory.systemTemp.createTempSync('dl');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final range = req.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      if (req.uri.path == '/stall') {
        // Sends a third, then goes quiet without closing (a dropped network).
        req.response.contentLength = data.length;
        req.response.add(data.sublist(0, 102400));
        await req.response.flush();
        return;
      }
      if (req.uri.path == '/moved') {
        req.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/file');
        await req.response.close();
        return;
      }
      var from = 0;
      if (range != null) {
        from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        req.response.statusCode = HttpStatus.partialContent;
      }
      req.response.contentLength = data.length - from;
      req.response.add(data.sublist(from));
      await req.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  Uri url([String path = '/file', String host = '127.0.0.1']) => Uri.parse('http://$host:${server.port}$path');

  test('downloads and checks the file', () async {
    final dest = File('${dir.path}/model.bin');
    var last = 0;
    await Downloader().fetch(url('/moved'), dest, size: data.length, sha256: hash, onBytes: (n) => last = n);
    expect(dest.readAsBytesSync(), data);
    expect(File('${dest.path}.part').existsSync(), isFalse);
    expect(last, data.length);
  });

  test('resumes a partial download', () async {
    final dest = File('${dir.path}/model.bin');
    File('${dest.path}.part').writeAsBytesSync(data.sublist(0, 102400));
    await Downloader().fetch(url(), dest, size: data.length, sha256: hash);
    expect(ranges, contains('bytes=102400-'));
    expect(dest.readAsBytesSync(), data);
  });

  test('a corrupt file is deleted and fails', () async {
    final dest = File('${dir.path}/model.bin');
    await expectLater(
      Downloader().fetch(url(), dest, size: data.length, sha256: '0' * 64),
      throwsA(isA<DownloadFailed>().having((e) => e.reason, 'reason', 'corrupt')),
    );
    expect(dest.existsSync(), isFalse);
    expect(File('${dest.path}.part').existsSync(), isFalse);
  });

  test("tries the next address when one doesn't answer", () async {
    final dest = File('${dir.path}/model.bin');
    final downloader = Downloader(
      lookup: (host) async => [InternetAddress('10.255.255.1'), InternetAddress.loopbackIPv4],
      connectTimeout: const Duration(milliseconds: 300),
    );
    await downloader.fetch(url('/file', 'files.test'), dest, size: data.length, sha256: hash);
    expect(dest.readAsBytesSync(), data);
  });

  test('a download that stalls fails as network and keeps what it got', () async {
    final dest = File('${dir.path}/model.bin');
    final downloader = Downloader(readTimeout: const Duration(milliseconds: 300));
    await expectLater(
      downloader.fetch(url('/stall'), dest, size: data.length, sha256: hash),
      throwsA(isA<DownloadFailed>().having((e) => e.reason, 'reason', 'network')),
    );
    expect(File('${dest.path}.part').lengthSync(), 102400);
  }, timeout: const Timeout(Duration(seconds: 20)));
}
