import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/audio/player.dart';
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

    Future<void> openWith(WidgetTester t, Recording r, List<Phrase> lines) async {
      repo = FakeRepo();
      player = FakePlayer();
      processor = IdleProcessor();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            recordingsProvider.overrideWith((ref) => Stream.value([r])),
            recordingsRepositoryProvider.overrideWithValue(repo),
            playerProvider.overrideWithValue(player),
            transcriptProvider.overrideWith((ref, id) => Stream.value(lines)),
            processorProvider.overrideWith(() => processor),
          ],
          child: const MaterialApp(home: RecordingDetailScreen(recordingId: 7)),
        ),
      );
      await t.pumpAndSettle();
    }

    Recording withStatus(RecordingStatus status, {String? error}) => Recording(
      id: 7,
      title: 'Weekly review',
      kind: 'recording',
      startedAt: DateTime(2026, 10, 12, 14, 5),
      duration: const Duration(minutes: 2),
      status: status,
      error: error,
    );

    const lines = [
      Phrase(startMs: 2000, endMs: 5000, text: 'first line', words: [Word('first', 2000, 3000), Word('line', 3000, 5000)]),
      Phrase(
        startMs: 12000,
        endMs: 15000,
        text: 'second part',
        words: [Word('second', 12000, 13000), Word('part', 13000, 15000)],
      ),
    ];

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
}
