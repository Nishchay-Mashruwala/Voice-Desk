import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'wav.dart';

/// Writes recorded PCM into 1-minute WAV pieces (`piece-000.wav`, …), so a
/// crash loses at most the piece being written, whose header `finalizeWav`
/// repairs on the next start.
class PieceWriter {
  PieceWriter(this.dir, {this.pieceBytes = kBytesPerSecond * 60});

  final Directory dir;
  final int pieceBytes;

  /// Called with how many pieces are finished each time one is (its header
  /// written, the next one opened): processing can start on it.
  void Function(int finishedPieces)? onPieceFinished;

  final List<File> _pieces = [];
  RandomAccessFile? _open;
  int _inPiece = 0;
  int _dataBytes = 0;

  /// All PCM bytes written so far; the recording's length is this / [kBytesPerSecond].
  int get dataBytes => _dataBytes;

  Future<void> add(Uint8List pcm) async {
    var at = 0;
    while (at < pcm.length) {
      if (_open == null || _inPiece == pieceBytes) await _nextPiece();
      final n = min(pieceBytes - _inPiece, pcm.length - at);
      await _open!.writeFrom(pcm, at, at + n);
      _inPiece += n;
      _dataBytes += n;
      at += n;
    }
    await _open?.flush();
  }

  /// Finishes the last piece; returns every piece in order.
  Future<List<File>> close() async {
    await _closePiece();
    return List.unmodifiable(_pieces);
  }

  Future<void> _nextPiece() async {
    await _closePiece();
    if (_pieces.isNotEmpty) onPieceFinished?.call(_pieces.length);
    final f = File('${dir.path}/piece-${_pieces.length.toString().padLeft(3, '0')}.wav');
    _pieces.add(f);
    _open = await f.open(mode: FileMode.write);
    await _open!.writeFrom(wavHeader(0)); // the real size goes in when the piece ends
    _inPiece = 0;
  }

  Future<void> _closePiece() async {
    final open = _open;
    if (open == null) return;
    _open = null;
    await open.close();
    await finalizeWav(_pieces.last);
  }
}
