import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/audio/free_space.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('needs 200 MB free to start', () {
    expect(canStartRecording(kMinFreeToStart - 1), isFalse);
    expect(canStartRecording(kMinFreeToStart), isTrue);
    expect(kMinFreeToStart, 200 * 1024 * 1024);
  });

  test('must stop below 50 MB', () {
    expect(mustStopRecording(kMinFreeWhileRecording - 1), isTrue);
    expect(mustStopRecording(kMinFreeWhileRecording), isFalse);
    expect(kMinFreeWhileRecording, 50 * 1024 * 1024);
  });

  test('AndroidFreeSpace asks the platform for the recordings folder', () async {
    const channel = MethodChannel('voicedesk/storage');
    MethodCall? seen;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return 123456789;
    });
    expect(await AndroidFreeSpace('/data/x/recordings').bytesFree(), 123456789);
    expect(seen?.method, 'freeBytes');
    expect(seen?.arguments, '/data/x/recordings');
  });
}
