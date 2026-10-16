import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/engine/audio/recorder_controller.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_frontend/ui/record/record_screen.dart';
import 'package:mobile_frontend/ui/widgets/badge.dart';

import 'fakes.dart';
import 'record_screen_test.dart' show FakeRecorder, FakeRepo, FakeSettings;

void main() {
  Future<void> show(
    WidgetTester t, {
    ProcessingState processing = const ProcessingState(),
    List<Recording> list = const [],
  }) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...quietBackend(processing: processing),
          recorderProvider.overrideWith(() => FakeRecorder(const RecorderState())),
          recordingsProvider.overrideWith((ref) => Stream.value(list)),
          recordingsRepositoryProvider.overrideWithValue(FakeRepo()),
          settingsRepositoryProvider.overrideWithValue(FakeSettings()),
          recordingsRootProvider.overrideWithValue(Directory.systemTemp),
        ],
        child: const MaterialApp(home: Scaffold(body: RecordScreen())),
      ),
    );
    // While processing, its spinner turns for ever: a few frames, not pumpAndSettle.
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets('the processing line names the recording, percent and time left', (t) async {
    await show(
      t,
      processing: const ProcessingState(
        recordingId: 1,
        title: 'Weekly review',
        progress: 0.4,
        left: Duration(minutes: 3),
      ),
    );
    expect(find.text('Turning “Weekly review” into text · 40% · about 3 min left'), findsOneWidget);
  });

  testWidgets('without an estimate yet it gives the percent only', (t) async {
    await show(t, processing: const ProcessingState(recordingId: 1, title: 'Weekly review', progress: 0));
    expect(find.text('Turning “Weekly review” into text · 0%'), findsOneWidget);
  });

  testWidgets('after the text, finding who said what is said', (t) async {
    await show(t,
        processing: const ProcessingState(recordingId: 1, title: 'Weekly review', progress: 1, step: 'speakers'));
    expect(find.text('Finding who said what in “Weekly review”'), findsOneWidget);
  });

  testWidgets('finding tasks names the recording and the part', (t) async {
    await show(t,
        processing: const ProcessingState(recordingId: 1, title: 'Weekly review', progress: 1, step: 'tasks', part: 2, parts: 3));
    expect(find.text('Finding tasks in “Weekly review” · part 2 of 3'), findsOneWidget);
  });

  testWidgets('a recording read in one part has no part number', (t) async {
    await show(t, processing: const ProcessingState(recordingId: 1, title: 'Weekly review', progress: 1, step: 'tasks', part: 1));
    expect(find.text('Finding tasks in “Weekly review”'), findsOneWidget);
  });

  testWidgets('waiting for charge is said', (t) async {
    await show(t, processing: const ProcessingState(waiting: 'charge'));
    expect(find.text('Waiting for charging to turn recordings into text'), findsOneWidget);
  });

  testWidgets('the tile shows Processing 40%', (t) async {
    await show(
      t,
      list: [
        Recording(
          id: 1,
          title: 'Weekly review',
          kind: 'recording',
          startedAt: DateTime(2026, 10, 13, 9),
          duration: const Duration(seconds: 100),
          status: RecordingStatus.processing,
          processedMs: 40000,
        ),
      ],
    );
    expect(find.widgetWithText(VdBadge, 'Processing 40%'), findsOneWidget);
  });

  testWidgets('a text-only recording says so on its tile', (t) async {
    await show(
      t,
      list: [
        Recording(
          id: 1,
          title: 'Old review',
          kind: 'recording',
          startedAt: DateTime(2026, 8, 13, 9),
          duration: const Duration(seconds: 100),
          status: RecordingStatus.done,
          audioDeleted: true,
        ),
      ],
    );
    expect(find.widgetWithText(VdBadge, 'Text only'), findsOneWidget);
  });
}
