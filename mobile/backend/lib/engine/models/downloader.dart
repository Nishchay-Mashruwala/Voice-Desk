import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:crypto/crypto.dart';

/// Why a download didn't finish: `corrupt`, `network` or `http_<status>`.
class DownloadFailed implements Exception {
  const DownloadFailed(this.reason);
  final String reason;

  @override
  String toString() => 'DownloadFailed($reason)';
}

/// Downloads a file that resumes where it stopped and only counts when its
/// size and SHA-256 match. Each address of a host is tried in turn: a network
/// can fail to reach one of them (this one can't reach one of GitHub's).
class Downloader {
  Downloader({
    Future<List<InternetAddress>> Function(String host)? lookup,
    this.connectTimeout = const Duration(seconds: 10),
    this.readTimeout = const Duration(seconds: 30),
  }) : _lookup = lookup ?? InternetAddress.lookup;

  final Future<List<InternetAddress>> Function(String host) _lookup;
  final Duration connectTimeout;

  /// A connection that sends nothing for this long has stalled (Wi-Fi to mobile
  /// data, a captive portal): the download fails and can be tried again.
  final Duration readTimeout;

  Future<void> fetch(Uri url, File dest, {required int size, required String sha256, void Function(int bytesDone)? onBytes}) async {
    final part = File('${dest.path}.part');
    await dest.parent.create(recursive: true);
    final client = HttpClient()
      ..connectionFactory = _connect
      ..autoUncompress = false;
    try {
      var have = part.existsSync() ? part.lengthSync() : 0;
      if (have > size) {
        part.deleteSync();
        have = 0;
      }
      if (have < size) await _download(client, url, part, have, onBytes);
    } on DownloadFailed catch (e) {
      debugPrint('Voice Desk: download of $url failed: ${e.reason}');
      rethrow;
    } on Exception catch (e) {
      // The screens say "check the connection"; the log says what happened.
      debugPrint('Voice Desk: download of $url failed: $e');
      throw const DownloadFailed('network');
    } finally {
      client.close(force: true);
    }
    if (part.lengthSync() != size || await _sha256(part) != sha256) {
      part.deleteSync();
      throw const DownloadFailed('corrupt');
    }
    if (dest.existsSync()) dest.deleteSync();
    await part.rename(dest.path);
    onBytes?.call(size);
  }

  Future<void> _download(HttpClient client, Uri url, File part, int have, void Function(int)? onBytes) async {
    var at = url;
    for (var hops = 0; hops < 8; hops++) {
      final req = await client.getUrl(at);
      req.followRedirects = false;
      // The bytes as they are: a server allowed to gzip (Hugging Face does, for
      // text files) sends another size, and ranges would count the gzip's bytes.
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final res = await req.close().timeout(readTimeout);
      if (res.isRedirect) {
        await res.drain<void>();
        at = at.resolve(res.headers.value(HttpHeaders.locationHeader)!);
        continue;
      }
      if (res.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        await res.drain<void>();
        return; // the part file is already whole
      }
      if (res.statusCode != HttpStatus.ok && res.statusCode != HttpStatus.partialContent) {
        await res.drain<void>();
        throw DownloadFailed('http_${res.statusCode}');
      }
      // A server that ignores the range sends everything again.
      final append = res.statusCode == HttpStatus.partialContent;
      var done = append ? have : 0;
      final sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in res.timeout(readTimeout)) {
          sink.add(chunk);
          done += chunk.length;
          onBytes?.call(done);
        }
      } finally {
        await sink.close();
      }
      return;
    }
    throw const DownloadFailed('network');
  }

  /// Connects to the host's addresses one after another; TLS keeps the host name.
  Future<ConnectionTask<Socket>> _connect(Uri url, String? proxyHost, int? proxyPort) async {
    final addresses = await _lookup(url.host);
    Object? last;
    for (final address in addresses) {
      try {
        final raw = await Socket.connect(address, url.port, timeout: connectTimeout);
        Socket socket = raw;
        if (url.scheme == 'https') {
          try {
            socket = await SecureSocket.secure(raw, host: url.host).timeout(connectTimeout);
          } on Object {
            raw.destroy();
            rethrow;
          }
        }
        return ConnectionTask.fromSocket(Future.value(socket), socket.destroy);
      } on Exception catch (e) {
        last = e;
      }
    }
    throw last ?? SocketException('No address for ${url.host}');
  }

  static Future<String> _sha256(File f) async => (await sha256.bind(f.openRead()).first).toString();
}
