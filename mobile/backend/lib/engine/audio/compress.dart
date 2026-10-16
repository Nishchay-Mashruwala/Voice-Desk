import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'flac.dart';
import 'wav.dart';

/// How a FLAC is written (tests give one that gets it wrong).
typedef FlacWriter = Future<void> Function(Stream<Int16List> samples, File out, {required int totalSamples});

/// Joins a finished recording's WAV [pieces] into one `audio.flac` in [dir],
/// decoded back and compared sample for sample before it is kept. Returns
/// whether it was. An `audio.flac` already there is checked the same way (a
/// power cut can leave one cut short) and made again if it doesn't match.
/// Never deletes the pieces (the repository does, once it is kept), and leaves
/// no `audio.flac.part` behind.
Future<bool> compressPieces(List<File> pieces, Directory dir, {FlacWriter write = writeFlac}) async {
  final part = File('${dir.path}/$kFlacName.part');
  final flac = File('${dir.path}/$kFlacName');
  try {
    if (part.existsSync()) part.deleteSync(); // a killed app's half-written one
    final total = pieces.fold(0, (sum, p) => sum + max(0, p.lengthSync() - kWavHeaderBytes) ~/ 2);
    if (flac.existsSync()) {
      if (await _matches(flac, pieces, total)) return true;
      flac.deleteSync();
    }
    await write(_wavSamples(pieces), part, totalSamples: total);
    if (!await _same(part, pieces, total)) {
      part.deleteSync();
      return false;
    }
    part.renameSync(flac.path);
    return true;
  } on Object {
    if (part.existsSync()) part.deleteSync();
    return false;
  }
}

/// [_same], for a file that may not even be a FLAC.
Future<bool> _matches(File flac, List<File> pieces, int total) async {
  try {
    return await _same(flac, pieces, total);
  } on Object {
    return false;
  }
}

/// The pieces' samples, about a second at a time.
Stream<Int16List> _wavSamples(List<File> pieces) async* {
  for (final p in pieces) {
    final raf = await p.open();
    try {
      await raf.setPosition(kWavHeaderBytes);
      while (true) {
        final bytes = await raf.read(kBytesPerSecond);
        if (bytes.length < 2) break;
        yield Int16List.fromList(bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.length ~/ 2));
      }
    } finally {
      await raf.close();
    }
  }
}

/// Whether [flac] holds exactly the pieces' [total] samples.
Future<bool> _same(File flac, List<File> pieces, int total) async {
  if ((await readFlacInfo(flac)).totalSamples != total) return false;
  final wav = StreamIterator(_wavSamples(pieces));
  var chunk = Int16List(0), at = 0;
  try {
    await for (final frame in readFlac(flac)) {
      for (var i = 0; i < frame.length; i++) {
        if (at == chunk.length) {
          if (!await wav.moveNext()) return false;
          chunk = wav.current;
          at = 0;
        }
        if (frame[i] != chunk[at++]) return false;
      }
    }
    return at == chunk.length && !await wav.moveNext();
  } finally {
    await wav.cancel();
  }
}
