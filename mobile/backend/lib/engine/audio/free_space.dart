import 'package:flutter/services.dart';

/// Don't start a recording with less free storage than this.
const kMinFreeToStart = 200 * 1024 * 1024;

/// Stop (and save) a recording when free storage drops below this.
const kMinFreeWhileRecording = 50 * 1024 * 1024;

bool canStartRecording(int freeBytes) => freeBytes >= kMinFreeToStart;

bool mustStopRecording(int freeBytes) => freeBytes < kMinFreeWhileRecording;

/// Free storage where recordings are kept.
abstract class FreeSpace {
  Future<int> bytesFree();
}

/// Android's StatFs for the recordings folder (MainActivity, channel `voicedesk/storage`).
class AndroidFreeSpace implements FreeSpace {
  AndroidFreeSpace(this.path);

  final String path;
  static const _channel = MethodChannel('voicedesk/storage');

  @override
  Future<int> bytesFree() async => (await _channel.invokeMethod<int>('freeBytes', path))!;
}
