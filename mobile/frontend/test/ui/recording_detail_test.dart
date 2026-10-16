import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/data/speakers_repository.dart';
import 'package:mobile_backend/data/tasks_repository.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/data/transcript_repository.dart';
import 'package:mobile_backend/data/transcript_text.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/audio/player.dart';
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/speakers/grouping.dart';
import 'package:mobile_backend/engine/speakers/voice_training.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/tasks/task_settings.dart';
import 'package:mobile_frontend/ui/recording/recording_detail_screen.dart';
import 'package:mobile_frontend/ui/theme.dart';
import 'package:mobile_frontend/ui/widgets/badge.dart';

import 'fakes.dart';

class FakeRepo implements RecordingsRepository {
  final calls = <String>[];
  final pieceFiles = [File('a/piece-000.wav'), File('a/piece-001.wav')];
  @override
  Future<void> rename(int id, String title) async => calls.add('rename:$id:$title');
  @override
  Future<void> delete(int id) async => calls.add('delete:$id');
  @override
  Future<List<File>> pieces(int id) async => pieceFiles;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakePlayer implements Player {
  final calls = <String>[];
  List<File>? loaded;
  final _position = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  @override
  Future<Duration> load(List<File> pieces) async {
    loaded = pieces;
    calls.add('load');
    return const Duration(minutes: 2);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration to) async => calls.add('seek:${to.inSeconds}');
  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<bool> get playing => _playing.stream;
  bool disposed = false;
  @override
  Future<void> dispose() async => disposed = true;

  void emitPosition(Duration at) => _position.add(at);
}

/// Records the line edits the screen makes.
class FakeTranscripts implements TranscriptRepository {
  final calls = <String>[];
  Object? failWith;
  @override
  Future<void> editLine(int lineId, String text) async {
    if (failWith != null) throw failWith!;
    calls.add('edit:$lineId:$text');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Records the renames the screen asks for.
class FakeSpeakers implements SpeakersRepository {
  final calls = <String>[];

  /// Remembering finds too little of their speech (their lines were moved meanwhile).
  bool tooLittle = false;
  @override
  Future<void> rename(int meetingId, int groupId, String name, {required bool remember}) async {
    calls.add('rename:$meetingId:$groupId:$name:$remember');
    if (remember && tooLittle) throw const NotEnoughSpeech(1200);
  }

  @override
  Future<void> moveLine(int lineId, {int? groupId, required String label}) async =>
      calls.add('move:$lineId:$groupId:$label');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

SpeakerGroup speakerGroup(int id, String label, {int speechMs = 10000}) =>
    SpeakerGroup(id: id, label: label, print: Float32List(192), speechMs: speechMs);

final sample = Recording(
  id: 7,
  title: 'Weekly review',
  kind: 'recording',
  startedAt: DateTime(2026, 10, 12, 14, 5),
  duration: const Duration(minutes: 2),
  status: RecordingStatus.queued,
);

void main() {
  late FakeRepo repo;
  late FakePlayer player;

  Future<void> open(WidgetTester t) async {
    repo = FakeRepo();
    player = FakePlayer();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          recordingsProvider.overrideWith((ref) => Stream.value([sample])),
          recordingsRepositoryProvider.overrideWithValue(repo),
          playerProvider.overrideWithValue(player),
          transcriptProvider.overrideWith((ref, id) => Stream.value(const <Phrase>[])),
          processorProvider.overrideWith(IdleProcessor.new),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const RecordingDetailScreen(recordingId: 7))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('shows the title and status, and renames', (t) async {
    await open(t);
    expect(find.text('Weekly review'), findsOneWidget);
    expect(find.text('Waiting to be processed'), findsOneWidget);
    await t.enterText(find.byKey(const Key('title-edit')), 'Weekly');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(repo.calls, ['rename:7:Weekly']);
  });

  testWidgets('play loads the pieces, then plays', (t) async {
    await open(t);
    await t.tap(find.byKey(const Key('play-button')));
    await t.pumpAndSettle();
    expect(player.loaded, repo.pieceFiles);
    expect(player.calls, ['load', 'play']);
  });

  testWidgets('one player lives as long as the screen and its position is shown', (t) async {
    // Made by the provider itself (as in the app), not handed in as one fixed value.
    final made = <FakePlayer>[];
    repo = FakeRepo();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          recordingsProvider.overrideWith((ref) => Stream.value([sample])),
          recordingsRepositoryProvider.overrideWithValue(repo),
          playerProvider.overrideWith((ref) {
            final p = FakePlayer();
            made.add(p);
            ref.onDispose(p.dispose);
            return p;
          }),
          processorProvider.overrideWith(IdleProcessor.new),
        ],
        child: const MaterialApp(home: RecordingDetailScreen(recordingId: 7)),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('play-button')));
    await t.pumpAndSettle();
    made.last.emitPosition(const Duration(seconds: 30));
    await t.pumpAndSettle();

    expect(made, hasLength(1));
    expect(made.single.disposed, isFalse);
    expect(made.single.calls, ['load', 'play']);
    expect(find.text('00:30 / 02:00'), findsOneWidget);
  });

  testWidgets('delete asks, deletes and goes back', (t) async {
    await open(t);
    await t.tap(find.byKey(const Key('delete-button')));
    await t.pumpAndSettle();
    expect(find.text('Delete this recording?'), findsOneWidget);
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(repo.calls, ['delete:7']);
    expect(find.byType(RecordingDetailScreen), findsNothing);
  });

  testWidgets('a recording still in progress can be neither deleted nor played here', (t) async {
    repo = FakeRepo();
    player = FakePlayer();
    final live = Recording(
      id: 7,
      title: 'Weekly review',
      kind: 'recording',
      startedAt: DateTime(2026, 10, 12, 14, 5),
      duration: Duration.zero,
      status: RecordingStatus.recording,
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          recordingsProvider.overrideWith((ref) => Stream.value([live])),
          recordingsRepositoryProvider.overrideWithValue(repo),
          playerProvider.overrideWithValue(player),
          processorProvider.overrideWith(IdleProcessor.new),
        ],
        child: const MaterialApp(home: RecordingDetailScreen(recordingId: 7)),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('delete-button')));
    await t.tap(find.byKey(const Key('play-button')));
    await t.pumpAndSettle();
    expect(find.text('Delete this recording?'), findsNothing);
    expect(player.calls, isEmpty);
    expect(repo.calls, isEmpty);
  });

  group('transcript', () {
    late IdleProcessor processor;
    late FakeTranscripts transcripts;
    late FakeModels models;
    late FakeSpeakers speakers;
    late List<String> shared;
    late List<String> copied;
    late FakeTasks tasks;
    var modelState = <ModelId, ModelState>{};
    var speechSettings = const SpeechSettings(speakers: false);

    Future<void> openWith(
      WidgetTester t,
      Recording r,
      List<Phrase> lines, {
      List<SpeakerGroup> groups = const [],
      bool trained = false,
      List<String> people = const [],
      List<TaskItem> taskItems = const [],
      int? playFromMs,
    }) async {
      repo = FakeRepo();
      player = FakePlayer();
      processor = IdleProcessor();
      transcripts = FakeTranscripts();
      speakers = FakeSpeakers();
      shared = [];
      copied = [];
      tasks = FakeTasks(taskItems);
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      models = FakeModels(modelState);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            recordingsProvider.overrideWith((ref) => Stream.value([r])),
            recordingsRepositoryProvider.overrideWithValue(repo),
            playerProvider.overrideWithValue(player),
            transcriptProvider.overrideWith((ref, id) => Stream.value(lines)),
            transcriptRepositoryProvider.overrideWithValue(transcripts),
            speakersRepositoryProvider.overrideWithValue(speakers),
            shareTextProvider.overrideWithValue((text) async => shared.add(text)),
            speakerGroupsProvider.overrideWith((ref, id) => Stream.value(groups)),
            myVoiceProvider.overrideWith((ref) async => trained ? (Float32List(192), DateTime(2026, 10, 15)) : (null, null)),
            peopleProvider.overrideWith(
              (ref) => Stream.value([
                for (final (i, n) in people.indexed) RememberedPerson(id: i + 1, name: n, speechMs: 5000),
              ]),
            ),
            modelsProvider.overrideWith(() => models),
            speechSettingsProvider.overrideWith(() => FakeSpeechSettings(speechSettings)),
            processorProvider.overrideWith(() => processor),
            tasksRepositoryProvider.overrideWithValue(tasks),
            taskSettingsProvider.overrideWith(FakeTaskSettings.new),
            phoneClassProvider.overrideWith((ref) async => m31),
          ],
          child: MaterialApp(home: RecordingDetailScreen(recordingId: 7, playFromMs: playFromMs)),
        ),
      );
      await t.pumpAndSettle();
    }

    Recording withTasks(TasksStatus status, {String? summary, String? work}) => Recording(
          id: 7,
          title: 'Weekly review',
          kind: 'recording',
          startedAt: DateTime(2026, 10, 12, 14, 5),
          duration: const Duration(minutes: 2),
          status: RecordingStatus.done,
          tasksStatus: status,
          summary: summary,
          tasksWork: work ?? '',
        );

    final spoken = [
      const Phrase(startMs: 0, endMs: 4000, text: 'Nishchay, please send the report.', words: [], speaker: 'Person 1'),
      const Phrase(startMs: 12000, endMs: 15000, text: 'Sure, by Friday.', words: [], speaker: 'Me'),
    ];
    const report = TaskItem(id: 1, description: 'Send the report', meetingId: 7, due: 'by Friday', quoteMs: 12000, fromAi: true);

    group('tasks', () {
      testWidgets('the summary and its tasks show', (t) async {
        await openWith(t, withTasks(TasksStatus.found, summary: 'We planned the launch.'), spoken, taskItems: [report]);
        expect(find.text('Summary'), findsOneWidget);
        expect(find.text('We planned the launch.'), findsOneWidget);
        expect(find.text('Your tasks'), findsOneWidget);
        expect(find.text('Send the report'), findsOneWidget);
        await t.tap(find.byKey(const Key('task-done-1')));
        await t.pumpAndSettle();
        expect(tasks.calls, ['done:1:true']);
      });

      testWidgets('no tasks for him says so', (t) async {
        await openWith(t, withTasks(TasksStatus.found, summary: 'A chat.'), spoken);
        expect(find.text('No tasks for you in this recording.'), findsOneWidget);
      });

      testWidgets('Find tasks runs it', (t) async {
        await openWith(t, withTasks(TasksStatus.none), spoken);
        await t.tap(find.widgetWithText(OutlinedButton, 'Find tasks'));
        await t.pumpAndSettle();
        expect(processor.findingTasks, [7]);
      });

      testWidgets('Find tasks without the task model asks to download it first', (t) async {
        modelState = {ModelId.taskFaster: const ModelState(ModelPhase.missing)};
        addTearDown(() => modelState = {});
        await openWith(t, withTasks(TasksStatus.none), spoken);
        await t.tap(find.widgetWithText(OutlinedButton, 'Find tasks'));
        await t.pumpAndSettle();
        expect(find.text('Task AI (Faster) · 1107 MB'), findsOneWidget);
        await t.tap(find.text('Download'));
        await t.pumpAndSettle();
        expect(models.downloads, [ModelId.taskFaster]);
        expect(processor.findingTasks, [7]);
      });

      testWidgets('while finding it says so, and Find tasks waits', (t) async {
        await openWith(t, withTasks(TasksStatus.finding, summary: 'Old.'), spoken, taskItems: [report]);
        expect(find.text('Finding tasks…'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Find tasks'), findsNothing);
      });

      testWidgets('a failed step offers Try again', (t) async {
        await openWith(t, withTasks(TasksStatus.failed, work: 'invalid_json'), spoken);
        expect(find.text("Couldn't find tasks."), findsOneWidget);
        await t.tap(find.widgetWithText(TextButton, 'Try again'));
        await t.pumpAndSettle();
        expect(processor.findingTasks, [7]);
      });

      testWidgets('without Me lines the hint shows', (t) async {
        final others = [
          const Phrase(startMs: 0, endMs: 4000, text: 'Nishchay, please send the report.', words: [], speaker: 'Person 1'),
          const Phrase(startMs: 5000, endMs: 8000, text: 'Sure.', words: [], speaker: 'Person 2'),
        ];
        await openWith(t, withTasks(TasksStatus.found, summary: 'A chat.'), others);
        expect(find.text('Train your voice so your own promises are found too.'), findsOneWidget);
      });

      testWidgets('with a Me line, or a trained voice, no hint', (t) async {
        await openWith(t, withTasks(TasksStatus.found, summary: 'A chat.'), spoken);
        expect(find.text('Train your voice so your own promises are found too.'), findsNothing);
      });

      testWidgets('Where it was said plays from the line', (t) async {
        await openWith(t, withTasks(TasksStatus.found, summary: 'A chat.'), spoken, taskItems: [report]);
        await t.tap(find.byKey(const Key('task-menu-1')));
        await t.pumpAndSettle();
        await t.tap(find.text('Where it was said'));
        await t.pumpAndSettle();
        expect(player.calls, ['load', 'seek:12', 'play']);
      });

      testWidgets('opened at a line, it plays from there', (t) async {
        await openWith(t, withTasks(TasksStatus.found, summary: 'A chat.'), spoken, taskItems: [report], playFromMs: 12000);
        expect(player.calls, ['load', 'seek:12', 'play']);
      });
    });

    Recording withStatus(RecordingStatus status,
            {String? error,
            SpeechSetup setup = SpeechSetup.englishOnly,
            bool reprocessing = false,
            bool compressFailed = false,
            bool audioDeleted = false}) =>
        Recording(
      id: 7,
      title: 'Weekly review',
      kind: 'recording',
      startedAt: DateTime(2026, 10, 12, 14, 5),
      duration: const Duration(minutes: 2),
      status: status,
      error: error,
      setup: setup,
      reprocessing: reprocessing,
      compressFailed: compressFailed,
      audioDeleted: audioDeleted,
    );

    const lines = [
      Phrase(id: 1, startMs: 2000, endMs: 5000, text: 'first line', words: [Word('first', 2000, 3000), Word('line', 3000, 5000)]),
      Phrase(
        id: 2,
        startMs: 12000,
        endMs: 15000,
        text: 'second part',
        words: [Word('second', 12000, 13000), Word('part', 13000, 15000)],
      ),
    ];

    Phrase said(int id, int start, String text, String speaker, int group) => Phrase(
      id: id,
      startMs: start,
      endMs: start + 2000,
      text: text,
      words: [Word(text, start, start + 2000)],
      speaker: speaker,
      speakerGroup: group,
    );

    final conversation = [
      said(1, 0, 'hello', 'Person 1', 1),
      said(2, 2500, 'there', 'Person 1', 1),
      said(3, 5000, 'hi', 'Person 2', 2),
      said(4, 7500, 'again', 'Person 1', 1),
    ];
    final twoGroups = [speakerGroup(1, 'Person 1'), speakerGroup(2, 'Person 2')];

    testWidgets("a speaker's name shows where the speaker changes", (t) async {
      await openWith(t, withStatus(RecordingStatus.done), conversation, groups: twoGroups);
      expect(find.text('Person 1'), findsNWidgets(2)); // before "hello" and before "again"
      expect(find.text('Person 2'), findsOneWidget);
    });

    testWidgets('tap a name, rename, remembered', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), conversation, groups: twoGroups);
      await t.tap(find.text('Person 2'));
      await t.pumpAndSettle();
      expect(find.text('Rename Person 2 to'), findsOneWidget);
      expect(find.text('Saved on this phone only'), findsOneWidget);
      expect(t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isTrue);
      await t.enterText(find.byKey(const Key('speaker-name')), 'Kiran');
      await t.tap(find.widgetWithText(FilledButton, 'Rename'));
      await t.pumpAndSettle();
      expect(speakers.calls, ['rename:7:2:Kiran:true']);
      expect(find.text("Renamed — Kiran's voice will be recognised in future recordings"), findsOneWidget);
    });

    testWidgets('renamed without remembering', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), conversation, groups: twoGroups);
      await t.tap(find.text('Person 2'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('speaker-name')), 'Kiran');
      await t.tap(find.byType(CheckboxListTile));
      await t.tap(find.widgetWithText(FilledButton, 'Rename'));
      await t.pumpAndSettle();
      expect(speakers.calls, ['rename:7:2:Kiran:false']);
      expect(find.text('Renamed to Kiran'), findsOneWidget);
    });

    testWidgets("Me can't be renamed", (t) async {
      await openWith(
        t,
        withStatus(RecordingStatus.done),
        [said(1, 0, 'mine', 'Me', 1), said(2, 2500, 'theirs', 'Person 1', 2)],
        groups: [speakerGroup(1, 'Me'), speakerGroup(2, 'Person 1')],
      );
      await t.tap(find.text('Me'));
      await t.pumpAndSettle();
      expect(find.text("Your own lines can't be renamed"), findsOneWidget);
      expect(find.byKey(const Key('speaker-name')), findsNothing);
    });

    testWidgets('an empty name is refused', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), conversation, groups: twoGroups);
      await t.tap(find.text('Person 2'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Rename'));
      await t.pumpAndSettle();
      expect(find.text('Type a name'), findsOneWidget);
      expect(speakers.calls, isEmpty);
    });

    testWidgets('too little of their speech: their voice is not offered to be remembered', (t) async {
      await openWith(
        t,
        withStatus(RecordingStatus.done),
        conversation,
        groups: [speakerGroup(1, 'Person 1'), speakerGroup(2, 'Person 2', speechMs: 1500)],
      );
      await t.tap(find.text('Person 2'));
      await t.pumpAndSettle();
      expect(find.text('Not enough of their speech to remember the voice (needs 2 s or more)'), findsOneWidget);
      expect(t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged, isNull);
      await t.enterText(find.byKey(const Key('speaker-name')), 'Kiran');
      await t.tap(find.widgetWithText(FilledButton, 'Rename'));
      await t.pumpAndSettle();
      expect(speakers.calls, ['rename:7:2:Kiran:false']);
    });

    Future<void> saidBy(WidgetTester t, String start) async {
      await t.longPress(find.text(start));
      await t.pumpAndSettle();
      await t.tap(find.text('Said by…'));
      await t.pumpAndSettle();
    }

    testWidgets('Said by moves only that line', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), conversation, groups: twoGroups, people: ['Kiran']);
      await saidBy(t, '00:05');
      expect(find.text('Me'), findsNothing); // not trained
      expect(find.widgetWithText(ListTile, 'Person 1'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Kiran'), findsOneWidget);
      expect(find.text('Someone else…'), findsOneWidget);
      await t.tap(find.widgetWithText(ListTile, 'Person 1'));
      await t.pumpAndSettle();
      expect(speakers.calls, ['move:3:1:Person 1']);
    });

    testWidgets('Said by Me, or a remembered person not in this recording', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), conversation,
          groups: twoGroups, trained: true, people: ['Kiran']);
      await saidBy(t, '00:05');
      await t.tap(find.widgetWithText(ListTile, 'Me'));
      await t.pumpAndSettle();
      await saidBy(t, '00:07');
      await t.tap(find.widgetWithText(ListTile, 'Kiran'));
      await t.pumpAndSettle();
      expect(speakers.calls, ['move:3:null:Me', 'move:4:null:Kiran']);
    });

    testWidgets('Someone else asks for a name', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), conversation, groups: twoGroups);
      await saidBy(t, '00:05');
      await t.tap(find.text('Someone else…'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Save'));
      await t.pumpAndSettle();
      expect(find.text('Type a name'), findsOneWidget);
      await t.enterText(find.byKey(const Key('said-by-name')), 'Asha');
      await t.tap(find.widgetWithText(FilledButton, 'Save'));
      await t.pumpAndSettle();
      expect(speakers.calls, ['move:3:null:Asha']);
    });

    testWidgets('Copy transcript puts it on the clipboard', (t) async {
      final r = withStatus(RecordingStatus.done);
      await openWith(t, r, lines);
      await t.tap(find.byKey(const Key('share-button')));
      await t.pumpAndSettle();
      await t.tap(find.text('Copy transcript'));
      await t.pumpAndSettle();
      expect(copied, [transcriptText(r, lines)]);
      expect(find.text('Copied to clipboard'), findsOneWidget);
    });

    testWidgets('Share… hands the text to the share sheet', (t) async {
      final r = withStatus(RecordingStatus.done);
      await openWith(t, r, lines);
      await t.tap(find.byKey(const Key('share-button')));
      await t.pumpAndSettle();
      await t.tap(find.text('Share…'));
      await t.pumpAndSettle();
      expect(shared, [transcriptText(r, lines)]);
    });

    testWidgets('Copy this line copies just that line', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), lines);
      await t.longPress(find.text('00:12'));
      await t.pumpAndSettle();
      await t.tap(find.text('Copy this line'));
      await t.pumpAndSettle();
      expect(copied, ['second part']);
      expect(find.text('Copied to clipboard'), findsOneWidget);
    });

    testWidgets('no Share without lines', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), const []);
      expect(find.byKey(const Key('share-button')), findsNothing);
    });

    testWidgets('a text-only recording can be read and shared, not played or processed again', (t) async {
      final r = withStatus(RecordingStatus.done, audioDeleted: true);
      await openWith(t, r, lines);
      await t.tap(find.byKey(const Key('share-button')));
      await t.pumpAndSettle();
      await t.tap(find.text('Copy transcript'));
      await t.pumpAndSettle();
      expect(copied, [transcriptText(r, lines)]);
      expect(find.text('The audio for this recording is no longer available.'), findsOneWidget);
      expect(find.byKey(const Key('play-button')), findsNothing);
      expect(find.text('first'), findsOneWidget);
      await t.tap(find.text('part'));
      await t.pumpAndSettle();
      expect(player.calls, isEmpty);
      expect(t.widget<IconButton>(find.byKey(const Key('process-again'))).onPressed, isNull);
    });

    testWidgets("audio that couldn't be compressed after three tries says so", (t) async {
      await openWith(t, withStatus(RecordingStatus.done, compressFailed: true), lines);
      expect(find.text("Couldn't compress this recording's audio; it's kept as it was"), findsOneWidget);
    });

    testWidgets('a text-only recording says nothing about compressing', (t) async {
      await openWith(t, withStatus(RecordingStatus.done, compressFailed: true, audioDeleted: true), lines);
      expect(find.text("Couldn't compress this recording's audio; it's kept as it was"), findsNothing);
    });

    testWidgets('Process again on audio that went meanwhile says so', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), lines);
      processor.processAgainError = const NoAudio(7);
      await t.tap(find.byKey(const Key('process-again')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Process again'));
      await t.pumpAndSettle();
      expect(find.text('The audio for this recording is no longer available.'), findsOneWidget);
    });

    testWidgets('a speakers step that failed says so above the text, with Try again', (t) async {
      await openWith(t, withStatus(RecordingStatus.done, error: 'speakers_failed'), lines);
      expect(find.text("Couldn't tell who said what in this recording."), findsOneWidget);
      expect(find.text('first'), findsOneWidget);
      await t.tap(find.text('Try again'));
      expect(processor.retried, [7]);
    });

    testWidgets('a typed name that is one of the speakers joins them, spelled as they are', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), conversation, groups: twoGroups);
      await saidBy(t, '00:05');
      await t.tap(find.text('Someone else…'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('said-by-name')), 'person 1');
      await t.tap(find.widgetWithText(FilledButton, 'Save'));
      await t.pumpAndSettle();
      expect(speakers.calls, ['move:3:1:Person 1']);
    });

    testWidgets('too little speech to remember after all: renamed, and said why', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), conversation, groups: twoGroups);
      speakers.tooLittle = true;
      await t.tap(find.text('Person 2'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('speaker-name')), 'Kiran');
      await t.tap(find.widgetWithText(FilledButton, 'Rename'));
      await t.pumpAndSettle();
      expect(speakers.calls, ['rename:7:2:Kiran:true', 'rename:7:2:Kiran:false']);
      expect(
        find.text('Renamed to Kiran. Not enough of their speech to remember the voice (needs 2 s or more)'),
        findsOneWidget,
      );
    });

    testWidgets('"Me" is not a name to give someone', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), conversation, groups: twoGroups);
      await t.tap(find.text('Person 2'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('speaker-name')), 'me');
      await t.tap(find.widgetWithText(FilledButton, 'Rename'));
      await t.pumpAndSettle();
      expect(find.text('Type a name'), findsOneWidget);
      expect(speakers.calls, isEmpty);
    });

    testWidgets('lines show with their times, and tapping a word plays from it', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), lines);
      expect(find.text('00:02'), findsOneWidget);
      expect(find.text('00:12'), findsOneWidget);
      await t.tap(find.text('part'));
      await t.pumpAndSettle();
      expect(player.calls, ['load', 'seek:13', 'play']);
    });

    testWidgets('the word being spoken is highlighted, not the whole line', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), lines);
      await t.tap(find.text('second'));
      await t.pumpAndSettle();
      player.emitPosition(const Duration(milliseconds: 13500));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.text('part')).style?.color, VdColors.light.accent);
      expect(t.widget<Text>(find.text('second')).style?.color, isNot(VdColors.light.accent));
      expect(t.widget<Text>(find.text('first')).style?.color, isNot(VdColors.light.accent));
    });

    testWidgets('the transcript follows the word being spoken', (t) async {
      final many = [
        for (var i = 0; i < 60; i++)
          Phrase(startMs: i * 2000, endMs: i * 2000 + 2000, text: 'word$i', words: [Word('word$i', i * 2000, i * 2000 + 2000)]),
      ];
      await openWith(t, withStatus(RecordingStatus.done), many);
      await t.tap(find.text('word0'));
      await t.pumpAndSettle();
      player.emitPosition(const Duration(milliseconds: 55 * 2000 + 500));
      await t.pumpAndSettle();
      final word = find.text('word55');
      expect(word, findsOneWidget);
      final screen = t.view.physicalSize / t.view.devicePixelRatio;
      expect(t.getRect(word).bottom, lessThanOrEqualTo(screen.height));
      expect(t.getRect(word).top, greaterThanOrEqualTo(0));
    });

    testWidgets('a recording with no speech says so', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), const []);
      expect(find.text('No speech found in this recording.'), findsOneWidget);
    });

    testWidgets('a failed one offers Try again', (t) async {
      await openWith(t, withStatus(RecordingStatus.error, error: 'speech_failed'), const []);
      expect(find.text("Couldn't turn this into text."), findsOneWidget);
      await t.tap(find.text('Try again'));
      expect(processor.retried, [7]);
    });

    testWidgets('long-press a line and fix its words', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), lines);
      await t.longPress(find.text('00:02'));
      await t.pumpAndSettle();
      await t.tap(find.text('Fix the words'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byKey(const Key('line-edit'))).controller!.text, 'first line');
      await t.enterText(find.byKey(const Key('line-edit')), 'first fine line');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(transcripts.calls, ['edit:1:first fine line']);
      expect(find.byKey(const Key('line-edit')), findsNothing);
    });

    testWidgets('Save is off for an empty line', (t) async {
      await openWith(t, withStatus(RecordingStatus.error, error: 'speech_failed'), lines);
      await t.longPress(find.text('00:12'));
      await t.pumpAndSettle();
      await t.tap(find.text('Fix the words'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('line-edit')), '   ');
      await t.pump();
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    });

    testWidgets('a line gone meanwhile says so', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), lines);
      transcripts.failWith = const LineGone(1);
      await t.longPress(find.text('00:02'));
      await t.pumpAndSettle();
      await t.tap(find.text('Fix the words'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('line-edit')), 'first fine line');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('That line is no longer there'), findsOneWidget);
    });

    testWidgets('no fixing while the recording is being processed', (t) async {
      await openWith(t, withStatus(RecordingStatus.processing), lines);
      await t.longPress(find.text('00:02'));
      await t.pumpAndSettle();
      expect(find.text('Fix the words'), findsNothing);
    });

    testWidgets("Process again asks, with More accurate and the recording's languages pre-set", (t) async {
      const gujarati = SpeechSetup(languages: {Lang.en, Lang.gu});
      await openWith(t, withStatus(RecordingStatus.done, setup: gujarati), lines);
      await t.tap(find.byKey(const Key('process-again')));
      await t.pumpAndSettle();
      expect(find.text('Process “Weekly review” again?'), findsOneWidget);
      expect(
        find.text('The same audio with the same settings gives the same words. '
            'To try for better ones, choose another accuracy or languages.'),
        findsOneWidget,
      );
      expect(find.text('Your fixes to its lines will be replaced.'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Process again'));
      await t.pumpAndSettle();
      expect(processor.again, [(7, const SpeechSetup(languages: {Lang.en, Lang.gu}, english: EnglishModel.accurate))]);
    });

    testWidgets('choosing Faster and English only is what is processed', (t) async {
      await openWith(t, withStatus(RecordingStatus.error, error: 'speech_failed', setup: const SpeechSetup(languages: {Lang.en, Lang.gu})), lines);
      await t.tap(find.byKey(const Key('process-again')));
      await t.pumpAndSettle();
      await t.tap(find.text('Faster'));
      await t.tap(find.text('ગુજરાતી Gujarati'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Process again'));
      await t.pumpAndSettle();
      expect(processor.again, [(7, SpeechSetup.englishOnly)]);
    });

    testWidgets('Cancel does nothing', (t) async {
      await openWith(t, withStatus(RecordingStatus.done), lines);
      await t.tap(find.byKey(const Key('process-again')));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(processor.again, isEmpty);
    });

    testWidgets('Process again uses the speaker detection setting', (t) async {
      speechSettings = const SpeechSettings(); // speakers on
      addTearDown(() => speechSettings = const SpeechSettings(speakers: false));
      await openWith(t, withStatus(RecordingStatus.done), lines);
      await t.tap(find.byKey(const Key('process-again')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Process again'));
      await t.pumpAndSettle();
      expect(processor.again.single.$2.speakers, isTrue);
    });

    testWidgets('Process again names what it must download first', (t) async {
      modelState = {ModelId.englishAccurate: const ModelState(ModelPhase.missing)};
      addTearDown(() => modelState = {});
      await openWith(t, withStatus(RecordingStatus.done), lines);
      await t.tap(find.byKey(const Key('process-again')));
      await t.pumpAndSettle();
      expect(find.text('Downloads 482 MB first.'), findsOneWidget); // More accurate is pre-set
      await t.tap(find.text('Faster'));
      await t.pumpAndSettle();
      expect(find.textContaining('first.'), findsNothing);
    });

    testWidgets('a recording waiting to be processed can be processed again with other choices', (t) async {
      await openWith(t, withStatus(RecordingStatus.queued), lines);
      expect(t.widget<IconButton>(find.byKey(const Key('process-again'))).onPressed, isNotNull);
    });

    testWidgets('a failed re-run says the text shown is the earlier one', (t) async {
      await openWith(t, withStatus(RecordingStatus.error, error: 'speech_failed', reprocessing: true), lines);
      expect(
        find.text("Processing it again didn't finish. The text below is the earlier one; "
            'Try again continues where it stopped.'),
        findsOneWidget,
      );
      expect(find.text("Couldn't turn this into text."), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('the accuracy choice is off when English is unticked', (t) async {
      await openWith(t, withStatus(RecordingStatus.done, setup: const SpeechSetup(languages: {Lang.en, Lang.gu})), lines);
      await t.tap(find.byKey(const Key('process-again')));
      await t.pumpAndSettle();
      SegmentedButton<EnglishModel> choice() => t.widget<SegmentedButton<EnglishModel>>(find.byType(SegmentedButton<EnglishModel>));
      expect(choice().onSelectionChanged, isNotNull);
      await t.tap(find.text('English'));
      await t.pumpAndSettle();
      expect(choice().onSelectionChanged, isNull);
    });

    testWidgets('Process again is not offered while processing', (t) async {
      await openWith(t, withStatus(RecordingStatus.processing), lines);
      expect(t.widget<IconButton>(find.byKey(const Key('process-again'))).onPressed, isNull);
    });

    testWidgets('one that stopped the app twice says how to help', (t) async {
      await openWith(t, withStatus(RecordingStatus.error, error: 'speech_crashed'), const []);
      expect(find.textContaining('stopped the app twice'), findsOneWidget);
    });
  });

  testWidgets('the status tag sits below the title, which reads as a heading, not a box', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        recordingsProvider.overrideWith((ref) => Stream.value([sample])),
        recordingsRepositoryProvider.overrideWithValue(FakeRepo()),
        playerProvider.overrideWithValue(FakePlayer()),
        transcriptProvider.overrideWith((ref, id) => Stream.value(const <Phrase>[])),
        processorProvider.overrideWith(IdleProcessor.new),
      ],
      child: MaterialApp(theme: vdTheme(Brightness.dark), home: const RecordingDetailScreen(recordingId: 7)),
    ));
    await t.pumpAndSettle();
    final title = t.getRect(find.byKey(const Key('title-edit')));
    final tag = t.getRect(find.widgetWithText(VdBadge, 'Waiting to be processed'));
    expect(tag.top, greaterThanOrEqualTo(title.bottom + 4));
    final decoration = t.widget<InputDecorator>(find.descendant(of: find.byKey(const Key('title-edit')), matching: find.byType(InputDecorator))).decoration;
    expect(decoration.filled, isFalse);
    expect(decoration.enabledBorder, InputBorder.none);
  });

  testWidgets('compressed while playing: the player is loaded again where it was', (t) async {
    repo = FakeRepo();
    player = FakePlayer();
    final recordings = StreamController<List<Recording>>();
    Recording done({String? audioPath}) => Recording(
      id: 7,
      title: 'Weekly review',
      kind: 'recording',
      startedAt: DateTime(2026, 10, 12, 14, 5),
      duration: const Duration(minutes: 2),
      status: RecordingStatus.done,
      audioPath: audioPath,
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          recordingsProvider.overrideWith((ref) => recordings.stream),
          recordingsRepositoryProvider.overrideWithValue(repo),
          playerProvider.overrideWithValue(player),
          transcriptProvider.overrideWith((ref, id) => Stream.value(const <Phrase>[])),
          processorProvider.overrideWith(IdleProcessor.new),
        ],
        child: const MaterialApp(home: RecordingDetailScreen(recordingId: 7)),
      ),
    );
    recordings.add([done()]);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('play-button')));
    await t.pumpAndSettle();
    player.emitPosition(const Duration(seconds: 75));
    await t.pumpAndSettle();
    expect(player.calls, ['load', 'play']);
    recordings.add([done(audioPath: 'rec/7/audio.flac')]);
    await t.pumpAndSettle();
    expect(player.calls, ['load', 'play', 'pause', 'load', 'seek:75', 'play']);
    await recordings.close();
  });
}
