import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/data/settings_repository.dart';
import 'package:mobile_backend/engine/audio/recorder_controller.dart';
import 'package:mobile_backend/engine/permissions.dart';
import 'package:mobile_frontend/ui/record/record_screen.dart';
import 'package:mobile_frontend/ui/widgets/badge.dart';
import 'package:mobile_frontend/ui/widgets/orb.dart';

import 'fakes.dart';

class FakeRecorder extends RecorderController {
  FakeRecorder(this.initial);
  final RecorderState initial;
  final calls = <String>[];

  @override
  RecorderState build() => initial;
  @override
  Future<void> start({String? title}) async => calls.add('start:${title ?? ''}');
  @override
  Future<void> stop({String? message}) async => calls.add('stop');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
}

class FakeRepo implements RecordingsRepository {
  final deleted = <int>[];
  @override
  Future<void> delete(int id) async => deleted.add(id);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeSettings implements SettingsRepository {
  final values = <String, bool>{};
  @override
  Future<bool> getBool(String key, {bool orElse = false}) async => values[key] ?? orElse;
  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;
  final strings = <String, String>{};
  @override
  Future<String> getString(String key, {String orElse = ''}) async => strings[key] ?? orElse;
  @override
  Future<void> setString(String key, String value) async => strings[key] = value;
}

class FakePermissions implements PermissionsStatus {
  Map<String, bool> status = {'microphone': true, 'notifications': true, 'battery_unrestricted': true};
  final requested = <String>[];
  bool openedSettings = false;
  @override
  Future<Map<String, bool>> check() async => status;
  @override
  Future<void> request(String id) async => requested.add(id);
  @override
  Future<void> openSettings() async => openedSettings = true;
}

final sample = Recording(
  id: 7,
  title: 'Weekly review',
  kind: 'recording',
  startedAt: DateTime(2026, 10, 12, 14, 5),
  duration: const Duration(minutes: 2, seconds: 5),
  status: RecordingStatus.queued,
);

/// Settles the screen; while recording the mic's rings move for ever, so a few frames instead.
Future<void> settle(WidgetTester t) async {
  await t.pump();
  final rec = t.any(find.byType(Orb)) ? t.widget<Orb>(find.byType(Orb)).state : OrbState.idle;
  if (rec == OrbState.recording) {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  } else {
    await t.pumpAndSettle();
  }
}

void main() {
  late FakeRecorder recorder;
  late FakeRepo repo;
  late FakeSettings settings;
  late FakePermissions permissions;

  Future<void> pump(WidgetTester t, {RecorderState state = const RecorderState(), List<Recording>? list}) async {
    recorder = FakeRecorder(state);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          recorderProvider.overrideWith(() => recorder),
          recordingsProvider.overrideWith((ref) => Stream.value(list ?? [sample])),
          recordingsRepositoryProvider.overrideWithValue(repo),
          settingsRepositoryProvider.overrideWithValue(settings),
          permissionsProvider.overrideWithValue(permissions),
          recordingsRootProvider.overrideWithValue(Directory.systemTemp),
          ...quietBackend(),
        ],
        child: const MaterialApp(home: Scaffold(body: RecordScreen())),
      ),
    );
    await settle(t);
  }

  setUp(() {
    repo = FakeRepo();
    settings = FakeSettings()..values['battery_asked'] = true;
    permissions = FakePermissions();
  });

  testWidgets('idle shows the record button and the recordings below it', (t) async {
    await pump(t);
    expect(find.byKey(const Key('record-button')), findsOneWidget);
    expect(find.text('Weekly review'), findsOneWidget);
    expect(find.text('Waiting to be processed'), findsOneWidget);
    expect(find.text('12 Oct, 14:05 · 02:05'), findsOneWidget);
  });

  testWidgets('tapping Record starts recording with the title typed', (t) async {
    await pump(t);
    await t.enterText(find.byKey(const Key('title-field')), 'Standup');
    await t.tap(find.byKey(const Key('record-button')));
    await t.pumpAndSettle();
    expect(recorder.calls, ['start:Standup']);
  });

  testWidgets('the title is cleared when the recording stops from the notification', (t) async {
    await pump(t);
    await t.enterText(find.byKey(const Key('title-field')), 'Standup');
    await t.tap(find.byKey(const Key('record-button')));
    recorder.state = const RecorderState(phase: RecorderPhase.recording, recordingId: 1);
    await settle(t);
    // Stop pressed in the notification: the recorder goes idle without the screen's button.
    recorder.state = const RecorderState();
    await t.pumpAndSettle();
    expect(t.widget<TextField>(find.byKey(const Key('title-field'))).controller!.text, isEmpty);
  });

  testWidgets('while recording shows Stop and the time', (t) async {
    await pump(
      t,
      state: const RecorderState(phase: RecorderPhase.recording, recordingId: 1, elapsed: Duration(seconds: 3)),
    );
    expect(find.text('00:03'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    await t.tap(find.byKey(const Key('record-button')));
    expect(recorder.calls, ['stop']);
  });

  testWidgets('microphone refused shows why and offers settings', (t) async {
    await pump(t, state: const RecorderState(message: 'microphone_denied'));
    expect(find.text('Voice Desk needs the microphone to record. Allow it in Settings.'), findsOneWidget);
    await t.tap(find.text('Open settings'));
    expect(permissions.openedSettings, isTrue);
  });

  testWidgets('first recording asks to run unrestricted, once', (t) async {
    settings.values.clear();
    permissions.status = {...permissions.status, 'battery_unrestricted': false};
    await pump(t);
    await t.tap(find.byKey(const Key('record-button')));
    await t.pumpAndSettle();
    expect(find.textContaining('run unrestricted'), findsOneWidget);
    await t.tap(find.text('Allow'));
    await t.pumpAndSettle();
    expect(permissions.requested, contains('battery_unrestricted'));
    expect(settings.values['battery_asked'], isTrue);
    expect(recorder.calls, ['start:']);
  });

  testWidgets('swipe to delete, Undo keeps it', (t) async {
    await pump(t);
    await t.drag(find.text('Weekly review'), const Offset(-600, 0));
    await t.pumpAndSettle();
    expect(find.text('Recording deleted'), findsOneWidget);
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(find.text('Weekly review'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(repo.deleted, isEmpty);
  });

  testWidgets('swipe to delete without Undo deletes it', (t) async {
    await pump(t);
    await t.drag(find.text('Weekly review'), const Offset(-600, 0));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(repo.deleted, [7]);
  });

  testWidgets('the title stays when the recording could not start', (t) async {
    await pump(t);
    await t.enterText(find.byKey(const Key('title-field')), 'Standup');
    recorder.state = const RecorderState(phase: RecorderPhase.starting);
    await t.pump();
    recorder.state = const RecorderState(message: 'microphone_denied');
    await t.pumpAndSettle();
    expect(t.widget<TextField>(find.byKey(const Key('title-field'))).controller!.text, 'Standup');
  });

  testWidgets('a failed start or a failed recording is explained in words', (t) async {
    await pump(t, state: const RecorderState(message: 'start_failed'));
    expect(find.textContaining('start_failed'), findsNothing);
    expect(find.textContaining('Recording'), findsWidgets);
    await pump(t, state: const RecorderState(message: 'recording_failed'));
    expect(find.textContaining('recording_failed'), findsNothing);
  });

  testWidgets('the round mic says what the recorder is doing, as on the PC', (t) async {
    await pump(t);
    expect(find.byType(Orb), findsOneWidget);
    expect(find.text('Ready to record'), findsOneWidget);
    recorder.state = const RecorderState(phase: RecorderPhase.recording, recordingId: 1);
    await settle(t);
    expect(find.text('Recording'), findsOneWidget);
    recorder.state = const RecorderState(phase: RecorderPhase.paused, recordingId: 1);
    await settle(t);
    expect(find.text('Paused'), findsOneWidget);
  });

  testWidgets("each recording's status is a coloured badge", (t) async {
    await pump(t);
    expect(find.widgetWithText(VdBadge, 'Waiting to be processed'), findsOneWidget);
  });
}
