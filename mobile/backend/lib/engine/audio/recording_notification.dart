import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pipeline/processing_notice.dart';

/// The "Recording · 12:34" notification that keeps recording alive with the
/// screen off. Its buttons arrive on [buttons] as `pause`, `resume`, `stop`.
abstract class RecordingNotification {
  Future<void> show(String title);
  Future<void> update(Duration elapsed, {required bool paused});
  Future<void> hide();
  Stream<String> get buttons;
}

/// "12:34", or "1:02:03" past an hour.
String clock(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Call once at app start.
void initForegroundTask() {
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'recording',
      channelName: 'Recording',
      channelDescription: 'Shown while Voice Desk records',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      allowWakeLock: true,
      // Recording lives in the app's engine: after Android kills the app nothing
      // would record, so the service must not come back and say "Recording".
      allowAutoRestart: false,
    ),
  );
}

/// Runs in the service's isolate: forwards notification buttons to the app.
@pragma('vm:entry-point')
void startRecordingTaskHandler() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

class RecordingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Restarted by Android after the app was killed: nothing is recording any
    // more (the app recovers the audio when it next opens).
    if (starter == TaskStarter.system) await FlutterForegroundTask.stopService();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) => FlutterForegroundTask.sendDataToMain(id);
}

/// The white microphone in the status bar (manifest meta-data → res/drawable/ic_notification.xml).
const _icon = NotificationIcon(metaDataName: 'com.rajvee.mobile.NOTIFICATION_ICON');

/// The one foreground service (flutter_foreground_task) behind both the
/// recording and the processing notification: recording wins while both run;
/// with neither, the service stops. Recording needs the microphone type, so a
/// service running for processing only is restarted with it.
class ForegroundService {
  ForegroundService() {
    FlutterForegroundTask.addTaskDataCallback(_onData);
    recording = _RecordingNotice(this);
    processing = _ProcessingNotice(this);
  }

  late final RecordingNotification recording;
  late final ProcessingNotice processing;

  final _buttons = StreamController<String>.broadcast();
  _Shown? _recording;
  _Shown? _processing;
  bool _running = false;
  bool _withMicrophone = false;
  Future<void> _work = Future.value();

  void _onData(Object data) {
    if (data is String) _buttons.add(data);
  }

  /// Shows what should be shown now; one change at a time.
  Future<void> _apply() {
    final next = _work.then((_) => _render());
    _work = next.catchError((Object _) {});
    return next;
  }

  Future<void> _render() async {
    final shown = _recording ?? _processing;
    if (shown == null) {
      if (_running) await FlutterForegroundTask.stopService();
      _running = false;
      return;
    }
    final microphone = _recording != null;
    if (_running && microphone && !_withMicrophone) {
      await FlutterForegroundTask.stopService();
      _running = false;
    }
    if (!_running) {
      // The plugin returns failures instead of throwing them.
      final result = await FlutterForegroundTask.startService(
        serviceId: 101,
        serviceTypes: [if (microphone) ForegroundServiceTypes.microphone, ForegroundServiceTypes.dataSync],
        notificationTitle: shown.title,
        notificationText: shown.text,
        notificationIcon: _icon,
        notificationButtons: shown.buttons,
        callback: startRecordingTaskHandler,
      );
      if (result is ServiceRequestFailure) throw result.error;
      _running = true;
      _withMicrophone = microphone;
    } else {
      await FlutterForegroundTask.updateService(
        notificationTitle: shown.title,
        notificationText: shown.text,
        notificationIcon: _icon,
        notificationButtons: shown.buttons,
      );
    }
  }
}

class _Shown {
  const _Shown(this.title, this.text, [this.buttons = const []]);
  final String title;
  final String text;
  final List<NotificationButton> buttons;
}

class _RecordingNotice implements RecordingNotification {
  _RecordingNotice(this._service);
  final ForegroundService _service;
  String _title = '';

  List<NotificationButton> _buttonsFor({required bool paused}) => [
        paused ? const NotificationButton(id: 'resume', text: 'Resume') : const NotificationButton(id: 'pause', text: 'Pause'),
        const NotificationButton(id: 'stop', text: 'Stop'),
      ];

  @override
  Future<void> show(String title) {
    _title = title;
    _service._recording = _Shown(title, 'Recording · 00:00', _buttonsFor(paused: false));
    return _service._apply();
  }

  @override
  Future<void> update(Duration elapsed, {required bool paused}) {
    _service._recording =
        _Shown(_title, '${paused ? 'Paused' : 'Recording'} · ${clock(elapsed)}', _buttonsFor(paused: paused));
    return _service._apply();
  }

  @override
  Future<void> hide() {
    _service._recording = null;
    return _service._apply();
  }

  @override
  Stream<String> get buttons => _service._buttons.stream;
}

class _ProcessingNotice implements ProcessingNotice {
  _ProcessingNotice(this._service);
  final ForegroundService _service;

  @override
  Future<void> show(String title, double progress, Duration? left) async {
    _service._processing = _Shown(title, processingText(progress, left));
    try {
      await _service._apply();
    } on Object {
      // Processing goes on without its notification.
    }
  }

  @override
  Future<void> showWaiting(String title, String why) async {
    _service._processing = _Shown(title, why == 'cool' ? 'Waiting for the phone to cool down' : 'Plug in to continue');
    try {
      await _service._apply();
    } on Object {
      // Waiting goes on without its notification.
    }
  }

  @override
  Future<void> hide() async {
    _service._processing = null;
    try {
      await _service._apply();
    } on Object {
      // Nothing to hide.
    }
  }
}

/// "Processing · 40% · about 3 min left".
String processingText(double progress, Duration? left) {
  final percent = (progress * 100).floor();
  if (left == null) return 'Processing · $percent%';
  final minutes = (left.inSeconds / 60).ceil().clamp(1, 1 << 30);
  return 'Processing · $percent% · about $minutes min left';
}

final foregroundServiceProvider = Provider<ForegroundService>((ref) => ForegroundService());
