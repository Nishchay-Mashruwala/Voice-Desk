import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/data/retention.dart';
import 'package:mobile_backend/engine/audio/free_space.dart';
import 'package:mobile_backend/engine/audio/recorder_controller.dart' show freeSpaceProvider;
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_frontend/ui/settings/storage_screen.dart';
import 'package:mobile_frontend/ui/widgets/badge.dart';

import 'fakes.dart';

/// The recordings the Storage page sees; records what it deletes.
class FakeRecordings implements RecordingsRepository {
  List<(Recording, int)> sizes = const [];
  List<Recording> older = const [];
  final deleted = <int>[];
  @override
  Future<List<(Recording, int)>> audioSizes() async => sizes;
  @override
  Future<List<Recording>> audioOlderThan(DateTime cutoff) async => older;
  @override
  Future<void> delete(int id) async => deleted.add(id);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeKeepAudio extends KeepAudio {
  FakeKeepAudio(this.initial);
  final int initial;
  final sets = <int>[];
  @override
  Future<int> build() async => initial;
  @override
  Future<void> set(int days) async {
    sets.add(days);
    state = AsyncData(days);
  }
}

Recording rec(int id, String title) => Recording(
  id: id,
  title: title,
  kind: 'recording',
  startedAt: DateTime(2026, 10, id),
  duration: const Duration(minutes: 3),
  status: RecordingStatus.done,
);

class FakeFreeSpace implements FreeSpace {
  int value = 3200000000;
  @override
  Future<int> bytesFree() async => value;
}

void main() {
  late FakeModels models;
  late IdleProcessor processor;
  late FakeFreeSpace free;
  late FakeRecordings recordings;
  late FakeKeepAudio keep;

  Future<void> show(
    WidgetTester t, {
    Map<ModelId, ModelState> state = const {},
    List<ModelId> needed = const [ModelId.vad, ModelId.englishFaster],
    ProcessingState processing = const ProcessingState(),
    List<(Recording, int)> sizes = const [],
    int keepDays = 30,
    PhoneClass phone = m31,
  }) async {
    t.view.physicalSize = const Size(1080, 4000);
    t.view.devicePixelRatio = 2.7;
    addTearDown(t.view.reset);
    models = FakeModels(state);
    processor = IdleProcessor(processing);
    free = FakeFreeSpace();
    recordings = FakeRecordings()..sizes = sizes;
    keep = FakeKeepAudio(keepDays);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(ProviderScope(
      overrides: [
        ...quietBackend(models: models, processor: processor, phone: phone),
        neededModelIdsProvider.overrideWithValue(needed),
        freeSpaceProvider.overrideWithValue(free),
        recordingsProvider.overrideWith((ref) => Stream.value(const <Recording>[])),
        recordingsRepositoryProvider.overrideWithValue(recordings),
        keepAudioProvider.overrideWith(() => keep),
        appDataBytesProvider.overrideWith((ref) async => 3000000),
      ],
      child: const MaterialApp(home: StorageScreen()),
    ));
    await t.pumpAndSettle();
  }

  const missing = ModelState(ModelPhase.missing);

  testWidgets('every model is listed with its state', (t) async {
    await show(t, state: {
      ModelId.englishAccurate: missing,
      ModelId.hindi: missing,
      ModelId.gujarati: const ModelState(ModelPhase.downloading, done: 89000000, total: 197663066),
    });
    for (final name in [
      'Voice activity',
      'English speech model (Faster)',
      'English speech model (More accurate)',
      'Gujarati model',
      'Hindi model',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('Hindi/Gujarati words'), findsNothing);
    expect(find.text('45%'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '3.2 GB'), findsOneWidget);
  });

  testWidgets('downloaded is a green tag', (t) async {
    await show(t, state: {ModelId.hindi: missing, ModelId.englishAccurate: missing, ModelId.taskAccurate: missing});
    final tags = t.widgetList<VdBadge>(find.widgetWithText(VdBadge, 'Downloaded')).toList();
    expect(tags, hasLength(5)); // voice activity, Faster, Gujarati, speaker detection, Task AI (Faster)
    expect(tags.every((b) => b.kind == BadgeKind.ok), isTrue);
  });

  testWidgets('Download starts it', (t) async {
    await show(t, state: {ModelId.hindi: missing});
    await t.tap(find.byKey(const Key('download-hindi')));
    await t.pump();
    expect(models.downloads, [ModelId.hindi]);
  });

  testWidgets('Delete asks, then deletes and says what was freed', (t) async {
    await show(t);
    await t.tap(find.byKey(const Key('delete-englishAccurate')));
    await t.pumpAndSettle();
    expect(find.text('Delete English speech model (More accurate)?'), findsOneWidget);
    expect(find.text('Frees 482 MB. You can download it again here.'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Delete'));
    await t.pumpAndSettle();
    expect(models.deletes, [ModelId.englishAccurate]);
    expect(find.text('Deleted — 482 MB freed'), findsOneWidget);
  });

  testWidgets('a model the settings need says so before deleting', (t) async {
    await show(t);
    await t.tap(find.byKey(const Key('delete-englishFaster')));
    await t.pumpAndSettle();
    expect(
      find.text('Frees 108 MB, but the speech settings or a recording waiting to be processed need it: '
          'they wait until it is downloaded again.'),
      findsOneWidget,
    );
  });

  testWidgets("a model can't be deleted while processing", (t) async {
    await show(t, processing: const ProcessingState(recordingId: 1, title: 'Weekly review'));
    await t.tap(find.byKey(const Key('delete-gujarati')));
    await t.pumpAndSettle();
    expect(find.text("It's in use right now — try again when processing has finished"), findsOneWidget);
    expect(models.deletes, isEmpty);
  });

  testWidgets("a model the settings don't use says so", (t) async {
    await show(t, needed: const [ModelId.vad, ModelId.englishFaster]);
    expect(find.text('198 MB · Not used by your settings'), findsNWidgets(2)); // Gujarati and Hindi
    expect(find.text('482 MB · Not used by your settings'), findsOneWidget);
    expect(find.textContaining('136 MB'), findsNothing); // sizes here come from the catalogue
    expect(find.text('108 MB'), findsOneWidget); // Faster is used: no note
  });

  testWidgets('processing that starts while Delete is being confirmed stops the delete', (t) async {
    await show(t);
    await t.tap(find.byKey(const Key('delete-hindi')));
    await t.pumpAndSettle();
    processor.startWorkingOn(1);
    await t.tap(find.widgetWithText(FilledButton, 'Delete'));
    await t.pumpAndSettle();
    expect(models.deletes, isEmpty);
    expect(find.text("It's in use right now — try again when processing has finished"), findsOneWidget);
  });

  testWidgets('the free space shown is read again after a delete', (t) async {
    await show(t);
    expect(find.widgetWithText(ListTile, '3.2 GB'), findsOneWidget);
    free.value = 3400000000; // the deleted model's room is free now
    await t.tap(find.byKey(const Key('delete-hindi')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Delete'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '3.4 GB'), findsOneWidget);
  });

  testWidgets('Storage lists both task models on an 8 GB phone', (t) async {
    await show(t, phone: const PhoneClass(totalRamBytes: 73 * 1024 * 1024 * 1024 ~/ 10, dotProduct: true),
        state: {ModelId.taskAccurate: missing});
    expect(find.text('Task AI (Faster)'), findsOneWidget);
    expect(find.text('Task AI (More accurate)'), findsOneWidget);
    expect(find.text('2497 MB'), findsOneWidget);
    expect(find.byKey(const Key('download-taskAccurate')), findsOneWidget);
  });

  testWidgets("a phone that can't run the 4B doesn't list it unless it is there", (t) async {
    await show(t, state: {ModelId.taskAccurate: missing});
    expect(find.text('Task AI (Faster)'), findsOneWidget);
    expect(find.text('Task AI (More accurate)'), findsNothing);
  });

  testWidgets('lists the speaker model', (t) async {
    await show(t, state: {ModelId.speakers: const ModelState(ModelPhase.missing)});
    expect(find.text('Speaker detection'), findsOneWidget);
    expect(find.byKey(const Key('download-speakers')), findsOneWidget);
  });

  group('recordings', () {
    final sizes = [(rec(1, 'Big review'), 30000000), (rec(2, 'Small chat'), 12000000)];

    testWidgets('on this phone adds up recordings, models, app data and free space', (t) async {
      await show(t, sizes: sizes);
      final models = ModelId.values.fold(0, (sum, id) => sum + kCatalogue[id]!.download.size);
      expect(find.text('On this phone'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '42 MB'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '${(models / 1000000).round()} MB'), findsWidgets);
      expect(find.widgetWithText(ListTile, '3.0 MB'), findsOneWidget); // small sizes keep a decimal (not "0 MB")
      expect(find.widgetWithText(ListTile, '3.2 GB'), findsOneWidget);
      expect(find.text('2 recordings with audio · 42 MB'), findsOneWidget);
    });

    testWidgets('recordings with audio are listed largest first', (t) async {
      await show(t, sizes: sizes);
      expect(t.getTopLeft(find.text('Big review')).dy, lessThan(t.getTopLeft(find.text('Small chat')).dy));
      expect(find.textContaining('30 MB'), findsOneWidget);
    });

    testWidgets('Delete asks, then deletes after the Undo time; Undo keeps it', (t) async {
      await show(t, sizes: sizes);
      await t.tap(find.byKey(const Key('delete-recording-2')));
      await t.pumpAndSettle();
      expect(find.text('Delete this recording?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await t.pumpAndSettle();
      expect(find.text('Small chat'), findsNothing);
      await t.tap(find.text('Undo'));
      await t.pumpAndSettle();
      expect(find.text('Small chat'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
      expect(recordings.deleted, isEmpty);

      await t.tap(find.byKey(const Key('delete-recording-2')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(recordings.deleted, [2]);
    });

    testWidgets('Undo after leaving Storage still keeps the recording', (t) async {
      await show(t, sizes: sizes);
      await t.tap(find.byKey(const Key('delete-recording-2')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await t.pumpAndSettle();
      // The page goes (here: replaced), the snack stays on the app's messenger.
      final undo = t.widget<SnackBarAction>(find.byType(SnackBarAction));
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: Text('elsewhere'))));
      undo.onPressed();
      await t.pump(const Duration(seconds: 6));
      expect(recordings.deleted, isEmpty);
    });

    testWidgets('a shorter period asks first and says how many', (t) async {
      await show(t, sizes: sizes);
      expect(find.text("Older recordings' audio is deleted; their text stays."), findsOneWidget);
      recordings.older = [rec(1, 'Big review'), rec(2, 'Small chat')];
      await t.tap(find.byKey(const Key('keep-audio')));
      await t.pumpAndSettle();
      await t.tap(find.text('7 days').last);
      await t.pumpAndSettle();
      expect(find.text('Delete the audio of 2 recordings older than 7 days now? Their text stays.'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(keep.sets, isEmpty);
      await t.tap(find.byKey(const Key('keep-audio')));
      await t.pumpAndSettle();
      await t.tap(find.text('7 days').last);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await t.pumpAndSettle();
      expect(keep.sets, [7]);
    });

    testWidgets('a longer period just changes', (t) async {
      await show(t, sizes: sizes);
      await t.tap(find.byKey(const Key('keep-audio')));
      await t.pumpAndSettle();
      await t.tap(find.text('Forever').last);
      await t.pumpAndSettle();
      expect(keep.sets, [0]);
    });
  });
}
