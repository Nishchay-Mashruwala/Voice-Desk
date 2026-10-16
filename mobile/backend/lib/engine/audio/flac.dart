import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Lossless FLAC of the recordings' 16 kHz mono 16-bit audio (RFC 9639): fixed
/// predictors and Rice coding, which is what speech needs; no FFmpeg. Writes
/// and reads a frame at a time, so an hour never sits in memory.

/// A recording's compressed audio, in its folder (written as `audio.flac.part` first).
const kFlacName = 'audio.flac';

/// Samples per frame (the last one is shorter).
const kFlacBlock = 4096;

/// A seek point every 10 s, for quick and exact seeking.
const kSeekEverySamples = 160000;

const _rate = 16000;

/// What a FLAC file holds.
class FlacInfo {
  const FlacInfo({required this.totalSamples, required this.seekPoints, required this.firstFrameOffset});
  final int totalSamples;

  /// (first sample of a frame, its byte offset from the first frame).
  final List<(int, int)> seekPoints;

  /// Where the first frame starts in the file.
  final int firstFrameOffset;
}

/// Writes [samples] (16 kHz mono, [totalSamples] of them in all) as FLAC to [out].
Future<void> writeFlac(Stream<Int16List> samples, File out, {required int totalSamples}) async {
  // The frame holding each 10 s mark (a seek point names its frame's first sample).
  final points = [for (var s = 0; s < totalSamples; s += kSeekEverySamples) s ~/ kFlacBlock * kFlacBlock];
  final metadataBytes = 4 + 4 + 34 + (points.isEmpty ? 0 : 4 + 18 * points.length);
  final raf = await out.open(mode: FileMode.write);
  try {
    await raf.writeFrom(Uint8List(metadataBytes)); // filled in at the end
    final block = Int16List(kFlacBlock);
    var filled = 0, frame = 0, offset = 0, count = 0;
    var minFrame = 0, maxFrame = 0;
    final offsets = <int, int>{};
    final pending = BytesBuilder(copy: false);

    Future<void> emit(Int16List x) async {
      final bytes = _encodeFrame(x, frame);
      offsets[frame * kFlacBlock] = offset;
      offset += bytes.length;
      minFrame = frame == 0 ? bytes.length : min(minFrame, bytes.length);
      maxFrame = max(maxFrame, bytes.length);
      frame++;
      pending.add(bytes);
      if (pending.length >= 1 << 18) await raf.writeFrom(pending.takeBytes());
    }

    await for (final chunk in samples) {
      var at = 0;
      while (at < chunk.length) {
        final n = min(kFlacBlock - filled, chunk.length - at);
        block.setRange(filled, filled + n, chunk, at);
        filled += n;
        at += n;
        count += n;
        if (filled == kFlacBlock) {
          await emit(block);
          filled = 0;
        }
      }
    }
    if (filled > 0) await emit(Int16List.sublistView(block, 0, filled));
    if (count != totalSamples) throw StateError('FLAC: $count samples, $totalSamples expected');
    await raf.writeFrom(pending.takeBytes());

    final w = _BitWriter();
    for (final c in 'fLaC'.codeUnits) {
      w.bits(c, 8);
    }
    w.bits(points.isEmpty ? 1 : 0, 1); // last metadata block?
    w.bits(0, 7); // STREAMINFO
    w.bits(34, 24);
    w.bits(kFlacBlock, 16);
    w.bits(kFlacBlock, 16);
    w.bits(minFrame, 24);
    w.bits(maxFrame, 24);
    w.bits(_rate, 20);
    w.bits(0, 3); // 1 channel
    w.bits(15, 5); // 16 bits
    w.bits(totalSamples >> 32, 4);
    w.bits(totalSamples & 0xFFFFFFFF, 32);
    for (var i = 0; i < 16; i++) {
      w.bits(0, 8); // MD5 unknown: the conversion compares every sample instead
    }
    if (points.isNotEmpty) {
      w.bits(1, 1);
      w.bits(3, 7); // SEEKTABLE
      w.bits(18 * points.length, 24);
      for (final s in points) {
        w.bits(0, 32);
        w.bits(s, 32);
        w.bits(0, 32);
        w.bits(offsets[s]!, 32);
        w.bits(min(kFlacBlock, totalSamples - s), 16);
      }
    }
    await raf.setPosition(0);
    await raf.writeFrom(w.take());
    // On the storage before it is checked: the pieces go once it is.
    await raf.flush();
  } finally {
    await raf.close();
  }
}

/// The file's length and seek points; [FormatException] if it isn't a FLAC this app reads.
Future<FlacInfo> readFlacInfo(File f) async {
  final raf = await f.open();
  try {
    Future<Uint8List> read(int n) async {
      final b = await raf.read(n);
      if (b.length < n) throw const FormatException('FLAC: too short');
      return b;
    }

    final magic = await read(4);
    if (String.fromCharCodes(magic) != 'fLaC') throw const FormatException('Not a FLAC file');
    int? total;
    final points = <(int, int)>[];
    var last = false;
    while (!last) {
      final h = await read(4);
      last = h[0] & 0x80 != 0;
      final type = h[0] & 0x7F;
      final length = h[1] << 16 | h[2] << 8 | h[3];
      final body = await read(length);
      final d = ByteData.sublistView(body);
      if (type == 0) {
        final rate = d.getUint16(10) << 4 | body[12] >> 4;
        final channels = (body[12] >> 1 & 7) + 1;
        final bits = ((body[12] & 1) << 4 | body[13] >> 4) + 1;
        if (rate != _rate || channels != 1 || bits != 16) throw const FormatException('FLAC: not 16 kHz mono 16-bit');
        total = (body[13] & 0x0F) << 32 | d.getUint32(14);
      } else if (type == 3) {
        for (var at = 0; at + 18 <= length; at += 18) {
          final sample = d.getUint32(at) << 32 | d.getUint32(at + 4);
          if (d.getUint32(at) == 0xFFFFFFFF) continue; // a placeholder
          points.add((sample, d.getUint32(at + 8) << 32 | d.getUint32(at + 12)));
        }
      }
    }
    if (total == null) throw const FormatException('FLAC: no STREAMINFO');
    return FlacInfo(totalSamples: total, seekPoints: points, firstFrameOffset: await raf.position());
  } finally {
    await raf.close();
  }
}

/// How long a FLAC of this app's plays (from its STREAMINFO).
Duration flacDuration(File f) {
  final raf = f.openSync();
  try {
    final b = raf.readSync(26);
    if (b.length < 26 || String.fromCharCodes(b.sublist(0, 4)) != 'fLaC') throw const FormatException('Not a FLAC file');
    final total = (b[21] & 0x0F) << 32 | ByteData.sublistView(b).getUint32(22);
    return Duration(microseconds: total * Duration.microsecondsPerSecond ~/ _rate);
  } finally {
    raf.closeSync();
  }
}

/// The samples from [fromSample] on, a frame at a time.
Stream<Int16List> readFlac(File f, {int fromSample = 0}) async* {
  final info = await readFlacInfo(f);
  if (fromSample >= info.totalSamples) return;
  var start = (0, 0);
  for (final p in info.seekPoints) {
    if (p.$1 <= fromSample && p.$1 >= start.$1) start = p;
  }
  final raf = await f.open();
  try {
    await raf.setPosition(info.firstFrameOffset + start.$2);
    final r = _BitReader(raf);
    var sample = start.$1;
    while (sample < info.totalSamples) {
      await r.fill(1 << 16);
      final frame = r.frame();
      final end = sample + frame.length;
      if (end > fromSample) yield fromSample > sample ? Int16List.sublistView(frame, fromSample - sample) : frame;
      sample = end;
    }
  } finally {
    await raf.close();
  }
}

// --- Encoding -------------------------------------------------------------

Uint8List _encodeFrame(Int16List x, int number) {
  final n = x.length;
  final w = _BitWriter();
  w.bits(0x3FFE, 14); // sync
  w.bits(0, 1);
  w.bits(0, 1); // fixed block size
  final sizeCode = n == kFlacBlock ? 12 : (n <= 256 ? 6 : 7);
  w.bits(sizeCode, 4);
  w.bits(5, 4); // 16 kHz
  w.bits(0, 4); // mono
  w.bits(4, 3); // 16 bits
  w.bits(0, 1);
  _frameNumber(w, number);
  if (sizeCode == 6) w.bits(n - 1, 8);
  if (sizeCode == 7) w.bits(n - 1, 16);
  w.bits(_crc8(w.bytes, 0, w.length), 8);
  _subframe(w, x);
  w.align();
  w.bits(_crc16(w.bytes, 0, w.length), 16);
  return w.take();
}

/// A frame number in FLAC's UTF-8-like coding.
void _frameNumber(_BitWriter w, int v) {
  if (v < 0x80) return w.bits(v, 8);
  final more = v < 0x800 ? 1 : v < 0x10000 ? 2 : v < 0x200000 ? 3 : v < 0x4000000 ? 4 : 5;
  w.bits((0xFF << (7 - more)) & 0xFF | v >> (6 * more), 8);
  for (var i = more - 1; i >= 0; i--) {
    w.bits(0x80 | (v >> (6 * i)) & 0x3F, 8);
  }
}

/// The smallest of CONSTANT, FIXED orders 0–4 (Rice partitions) and VERBATIM.
void _subframe(_BitWriter w, Int16List x) {
  final n = x.length;
  if (x.every((v) => v == x[0])) {
    w.bits(0, 8); // CONSTANT
    return w.bits(x[0] & 0xFFFF, 16);
  }
  var bestBits = 16 * n;
  int? bestOrder;
  late Int32List bestResidual;
  late (int, List<int>) bestRice;
  for (var order = 0; order <= 4 && order < n; order++) {
    final residual = _fixedResidual(x, order);
    final (bits, partitions, params) = _rice(residual, n, order);
    final total = 16 * order + 6 + bits;
    if (total < bestBits) {
      bestBits = total;
      bestOrder = order;
      bestResidual = residual;
      bestRice = (partitions, params);
    }
  }
  if (bestOrder == null) {
    w.bits(2, 8); // VERBATIM
    for (final v in x) {
      w.bits(v & 0xFFFF, 16);
    }
    return;
  }
  final order = bestOrder;
  w.bits((0x08 | order) << 1, 8); // FIXED, order
  for (var i = 0; i < order; i++) {
    w.bits(x[i] & 0xFFFF, 16);
  }
  final (p, params) = bestRice;
  w.bits(0, 2); // Rice, 4-bit parameters
  w.bits(p, 4);
  final size = n >> p;
  var i = 0;
  for (var part = 0; part < 1 << p; part++) {
    final k = params[part];
    w.bits(k, 4);
    final end = (part + 1) * size - order;
    for (; i < end; i++) {
      final v = bestResidual[i];
      final u = v >= 0 ? v << 1 : (-v << 1) - 1;
      w.zeros(u >> k);
      w.bits(1, 1);
      if (k > 0) w.bits(u & ((1 << k) - 1), k);
    }
  }
}

Int32List _fixedResidual(Int16List x, int order) {
  final out = Int32List(x.length - order);
  for (var i = order; i < x.length; i++) {
    out[i - order] = switch (order) {
      0 => x[i],
      1 => x[i] - x[i - 1],
      2 => x[i] - 2 * x[i - 1] + x[i - 2],
      3 => x[i] - 3 * x[i - 1] + 3 * x[i - 2] - x[i - 3],
      _ => x[i] - 4 * x[i - 1] + 6 * x[i - 2] - 4 * x[i - 3] + x[i - 4],
    };
  }
  return out;
}

/// The best Rice partition order and parameters for [residual]: (bits, order, parameters).
/// Partition sums are made once at the finest order allowed, then merged pairwise.
(int, int, List<int>) _rice(Int32List residual, int n, int order) {
  var maxP = 0;
  while (maxP < 8 && n % (1 << (maxP + 1)) == 0 && (n >> (maxP + 1)) > order) {
    maxP++;
  }
  var size = n >> maxP;
  var sums = List<int>.filled(1 << maxP, 0);
  var counts = List<int>.filled(1 << maxP, 0);
  for (var i = 0; i < residual.length; i++) {
    final v = residual[i];
    final part = (i + order) ~/ size;
    sums[part] += v >= 0 ? v << 1 : (-v << 1) - 1;
    counts[part]++;
  }
  var best = (1 << 62, 0, const <int>[]);
  for (var p = maxP; p >= 0; p--) {
    var bits = 0;
    final params = <int>[];
    for (var j = 0; j < sums.length; j++) {
      final (k, cost) = _riceParameter(sums[j], counts[j]);
      bits += 4 + cost;
      params.add(k);
    }
    if (bits < best.$1) best = (bits, p, params);
    if (p > 0) {
      sums = [for (var j = 0; j < sums.length; j += 2) sums[j] + sums[j + 1]];
      counts = [for (var j = 0; j < counts.length; j += 2) counts[j] + counts[j + 1]];
      size *= 2;
    }
  }
  return best;
}

/// The parameter (0–14) that codes [count] values summing to [sum] in the
/// fewest bits, and about how many bits (never fewer than it takes).
(int, int) _riceParameter(int sum, int count) {
  var bestK = 0, bestCost = 1 << 62;
  for (var k = 0; k <= 14; k++) {
    final cost = count * (k + 1) + (sum >> k);
    if (cost < bestCost) {
      bestCost = cost;
      bestK = k;
    }
  }
  return (bestK, bestCost);
}

class _BitWriter {
  Uint8List bytes = Uint8List(1 << 14);
  int length = 0;
  int _acc = 0, _n = 0;

  void _put(int b) {
    if (length == bytes.length) bytes = Uint8List(bytes.length * 2)..setRange(0, length, bytes);
    bytes[length++] = b;
  }

  /// The low [count] (≤ 32) bits of [value].
  void bits(int value, int count) {
    _acc = _acc << count | value & ((1 << count) - 1);
    _n += count;
    while (_n >= 8) {
      _n -= 8;
      _put(_acc >> _n & 0xFF);
    }
    _acc &= (1 << _n) - 1;
  }

  void zeros(int count) {
    for (; count >= 32; count -= 32) {
      bits(0, 32);
    }
    if (count > 0) bits(0, count);
  }

  void align() {
    if (_n > 0) bits(0, 8 - _n);
  }

  Uint8List take() => Uint8List.sublistView(bytes, 0, length);
}

// --- Decoding -------------------------------------------------------------

class _BitReader {
  _BitReader(this._raf);
  final RandomAccessFile _raf;
  Uint8List _buf = Uint8List(0);
  int _pos = 0; // byte position of the next whole byte in _buf
  int _acc = 0, _n = 0; // bits read ahead from _buf
  bool _eof = false;

  /// Makes at least [bytes] available (fewer at the end of the file).
  Future<void> fill(int bytes) async {
    if (_eof || _buf.length - _pos >= bytes) return;
    final more = await _raf.read(max(bytes, 1 << 16));
    if (more.isEmpty) _eof = true;
    _buf = Uint8List(_buf.length - _pos + more.length)
      ..setRange(0, _buf.length - _pos, _buf, _pos)
      ..setRange(_buf.length - _pos, _buf.length - _pos + more.length, more);
    _pos = 0;
  }

  int bits(int count) {
    while (_n < count) {
      if (_pos >= _buf.length) throw const FormatException('FLAC: frame cut off');
      _acc = _acc << 8 | _buf[_pos++];
      _n += 8;
    }
    _n -= count;
    final v = _acc >> _n & ((1 << count) - 1);
    _acc &= (1 << _n) - 1;
    return v;
  }

  int signed(int count) {
    final v = bits(count);
    return v >= 1 << (count - 1) ? v - (1 << count) : v;
  }

  /// Zeros before the next 1.
  int unary() {
    var q = 0;
    while (true) {
      if (_n == 0) {
        if (_pos >= _buf.length) throw const FormatException('FLAC: frame cut off');
        _acc = _buf[_pos++];
        _n = 8;
      }
      final top = _acc >> (_n - 1) & 1;
      _n--;
      _acc &= (1 << _n) - 1;
      if (top == 1) return q;
      q++;
    }
  }

  /// Where the next unread byte is (with no bits left over).
  int get bytePos => _pos - _n ~/ 8;

  void align() {
    final drop = _n % 8;
    _n -= drop;
    _acc &= (1 << _n) - 1;
  }

  Int16List frame() {
    final start = bytePos;
    if (bits(14) != 0x3FFE) throw const FormatException('FLAC: lost sync');
    bits(2);
    final sizeCode = bits(4);
    bits(4); // sample rate (STREAMINFO's)
    if (bits(4) != 0) throw const FormatException('FLAC: not mono');
    if (bits(3) != 4) throw const FormatException('FLAC: not 16-bit');
    bits(1);
    final first = bits(8);
    var more = 0;
    while (more < 6 && first & (0x80 >> more) != 0) {
      more++;
    }
    for (var i = 1; i < more; i++) {
      bits(8);
    }
    final n = switch (sizeCode) {
      12 => kFlacBlock,
      6 => bits(8) + 1,
      7 => bits(16) + 1,
      _ => throw const FormatException('FLAC: block size not this app\'s'),
    };
    final headerEnd = bytePos;
    final crc8 = bits(8);
    if (crc8 != _crc8(_buf, start, headerEnd)) throw const FormatException('FLAC: header CRC');

    final out = Int16List(n);
    if (bits(1) != 0) throw const FormatException('FLAC: bad subframe');
    final type = bits(6);
    if (bits(1) != 0) throw const FormatException('FLAC: wasted bits not supported');
    if (type == 0) {
      out.fillRange(0, n, signed(16));
    } else if (type == 1) {
      for (var i = 0; i < n; i++) {
        out[i] = signed(16);
      }
    } else if (type >= 8 && type <= 12) {
      final order = type - 8;
      for (var i = 0; i < order; i++) {
        out[i] = signed(16);
      }
      if (bits(2) != 0) throw const FormatException('FLAC: residual coding not supported');
      final p = bits(4);
      final size = n >> p;
      var i = order;
      for (var part = 0; part < 1 << p; part++) {
        final k = bits(4);
        if (k == 15) throw const FormatException('FLAC: escaped partition not supported');
        final end = (part + 1) * size;
        for (; i < end; i++) {
          final u = unary() << k | (k > 0 ? bits(k) : 0);
          final r = u & 1 == 0 ? u >> 1 : -(u >> 1) - 1;
          out[i] = r +
              switch (order) {
                0 => 0,
                1 => out[i - 1],
                2 => 2 * out[i - 1] - out[i - 2],
                3 => 3 * out[i - 1] - 3 * out[i - 2] + out[i - 3],
                _ => 4 * out[i - 1] - 6 * out[i - 2] + 4 * out[i - 3] - out[i - 4],
              };
        }
      }
    } else {
      throw const FormatException('FLAC: subframe type not this app\'s');
    }
    align();
    final end = bytePos;
    final crc16 = bits(16);
    if (crc16 != _crc16(_buf, start, end)) throw const FormatException('FLAC: frame CRC');
    return out;
  }
}

final _crc8Table = Uint8List.fromList([
  for (var i = 0; i < 256; i++)
    () {
      var c = i;
      for (var b = 0; b < 8; b++) {
        c = c & 0x80 != 0 ? (c << 1 ^ 0x07) & 0xFF : c << 1 & 0xFF;
      }
      return c;
    }(),
]);

final _crc16Table = Uint16List.fromList([
  for (var i = 0; i < 256; i++)
    () {
      var c = i << 8;
      for (var b = 0; b < 8; b++) {
        c = c & 0x8000 != 0 ? (c << 1 ^ 0x8005) & 0xFFFF : c << 1 & 0xFFFF;
      }
      return c;
    }(),
]);

/// FLAC's CRC-8 and CRC-16 of [b], for tests.
@visibleForTesting
int flacCrc8(Uint8List b) => _crc8(b, 0, b.length);
@visibleForTesting
int flacCrc16(Uint8List b) => _crc16(b, 0, b.length);

int _crc8(Uint8List b, int from, int to) {
  var c = 0;
  for (var i = from; i < to; i++) {
    c = _crc8Table[c ^ b[i]];
  }
  return c;
}

int _crc16(Uint8List b, int from, int to) {
  var c = 0;
  for (var i = from; i < to; i++) {
    c = (c << 8 & 0xFFFF) ^ _crc16Table[(c >> 8) ^ b[i]];
  }
  return c;
}
