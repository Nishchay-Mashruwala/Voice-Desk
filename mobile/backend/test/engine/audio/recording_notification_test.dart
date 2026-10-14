import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/audio/recording_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      (call) async {
        calls.add(call.method);
        return call.method == 'isRunningService' ? true : null;
      },
    );
  });

  test('Android does not bring the service back after killing the app', () {
    initForegroundTask();
    expect(FlutterForegroundTask.foregroundTaskOptions!.allowAutoRestart, isFalse);
  });

  test('a service restarted by Android stops instead of claiming to record', () async {
    await RecordingTaskHandler().onStart(DateTime.now(), TaskStarter.system);
    expect(calls, contains('stopService'));
  });

  test('a service started by the app keeps running', () async {
    await RecordingTaskHandler().onStart(DateTime.now(), TaskStarter.developer);
    expect(calls, isNot(contains('stopService')));
  });

  test('a notification service that does not start is reported, not ignored', () async {
    initForegroundTask();
    // The mock says a service is already running, so the plugin refuses to start another.
    await expectLater(ForegroundService().recording.show('Weekly'), throwsA(anything));
  });

  group('one service for recording and processing', () {
    late bool running;
    late List<MethodCall> service;

    setUp(() {
      running = false;
      service = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_foreground_task/methods'),
        (call) async {
          switch (call.method) {
            case 'isRunningService':
              return running;
            case 'startService':
              running = true;
            case 'stopService':
              running = false;
          }
          service.add(call);
          return null;
        },
      );
      initForegroundTask();
    });

    List<String> methods() => service.map((c) => c.method).toList();
    Map<Object?, Object?> args(MethodCall c) => c.arguments as Map<Object?, Object?>;

    test('processing alone starts the service as dataSync with its text', () async {
      await ForegroundService().processing.show('Weekly', 0.4, const Duration(minutes: 3));
      final start = service.singleWhere((c) => c.method == 'startService');
      expect(args(start)['serviceTypes'], [ForegroundServiceTypes.dataSync.rawValue]);
      expect(args(start)['notificationContentTitle'], 'Weekly');
      expect(args(start)['notificationContentText'], 'Processing · 40% · about 3 min left');
    });

    test('recording during processing restarts the service with the microphone and shows the recording', () async {
      final s = ForegroundService();
      await s.processing.show('Old', 0.5, null);
      await s.recording.show('Standup');
      expect(methods(), ['startService', 'stopService', 'startService']);
      final start = service.last;
      expect(args(start)['serviceTypes'],
          [ForegroundServiceTypes.microphone.rawValue, ForegroundServiceTypes.dataSync.rawValue]);
      expect(args(start)['notificationContentTitle'], 'Standup');
      expect(args(start)['notificationContentText'], 'Recording · 00:00');
    });

    test('when recording stops the processing text comes back', () async {
      final s = ForegroundService();
      await s.processing.show('Old', 0.5, null);
      await s.recording.show('Standup');
      await s.recording.hide();
      expect(service.last.method, 'updateService');
      expect(args(service.last)['notificationContentTitle'], 'Old');
      expect(args(service.last)['notificationContentText'], 'Processing · 50%');
    });

    test('waiting for charge says Plug in to continue', () async {
      await ForegroundService().processing.showWaiting('Weekly', 'charge');
      final start = service.singleWhere((c) => c.method == 'startService');
      expect(args(start)['notificationContentTitle'], 'Weekly');
      expect(args(start)['notificationContentText'], 'Plug in to continue');
    });

    test('with nothing running the service stops', () async {
      final s = ForegroundService();
      await s.processing.show('Old', 0.5, null);
      await s.processing.hide();
      expect(methods().last, 'stopService');
      expect(running, isFalse);
    });
  });
}
