import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/speakers/grouping.dart';
import 'db.dart';
import 'recording.dart';
import 'recordings_repository.dart';
import 'settings_repository.dart';
import 'speakers_repository.dart';
import 'tasks_repository.dart';
import 'transcript.dart';
import 'transcript_repository.dart';

/// Overridden in `main()` once the database is open (and in tests).
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider not overridden'));

/// `<app documents>/recordings`; overridden in `main()`.
final recordingsRootProvider = Provider<Directory>((ref) => throw UnimplementedError('recordingsRootProvider not overridden'));

final recordingsRepositoryProvider = Provider<RecordingsRepository>(
  (ref) => LocalRecordingsRepository(ref.watch(databaseProvider), ref.watch(recordingsRootProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => SettingsRepository(ref.watch(databaseProvider)));

/// All recordings, newest first.
final recordingsProvider = StreamProvider<List<Recording>>((ref) => ref.watch(recordingsRepositoryProvider).watchAll());

final speakersRepositoryProvider = Provider<SpeakersRepository>((ref) => SpeakersRepository(ref.watch(databaseProvider)));

/// A recording's speaker groups, updated as they are renamed.
final speakerGroupsProvider = StreamProvider.family<List<SpeakerGroup>, int>(
  (ref, id) => ref.watch(speakersRepositoryProvider).watchGroups(id),
);

/// The people whose voices are remembered, by name.
final peopleProvider = StreamProvider<List<RememberedPerson>>((ref) => ref.watch(speakersRepositoryProvider).watchPeople());

final transcriptRepositoryProvider = Provider<TranscriptRepository>((ref) => TranscriptRepository(ref.watch(databaseProvider)));

/// The database file (and its journal), for Storage's "App data"; overridden in
/// `main()` (none in tests).
final databaseFileProvider = Provider<File?>((ref) => null);

/// What the app's own data takes: the database (transcripts, voice prints, settings).
final appDataBytesProvider = FutureProvider.autoDispose<int>((ref) async {
  final db = ref.watch(databaseFileProvider);
  if (db == null) return 0;
  var bytes = 0;
  for (final f in [db, File('${db.path}-wal'), File('${db.path}-shm')]) {
    if (f.existsSync()) bytes += f.lengthSync();
  }
  return bytes;
});

/// Recordings with audio and its size, largest first; read again as recordings change.
final audioSizesProvider = FutureProvider.autoDispose<List<(Recording, int)>>((ref) {
  ref.watch(recordingsProvider);
  return ref.read(recordingsRepositoryProvider).audioSizes();
});

/// A recording's transcript lines, updated as they are saved.
final transcriptProvider = StreamProvider.family<List<Phrase>, int>(
  (ref, id) => ref.watch(transcriptRepositoryProvider).watch(id),
);

final tasksRepositoryProvider = Provider<TasksRepository>((ref) => TasksRepository(ref.watch(databaseProvider)));

/// Every task (the Tasks tab): open ones in the owner's order, then done ones.
final tasksProvider = StreamProvider<List<TaskItem>>((ref) => ref.watch(tasksRepositoryProvider).watchAll());

/// A recording's tasks.
final recordingTasksProvider = StreamProvider.family<List<TaskItem>, int>(
  (ref, id) => ref.watch(tasksRepositoryProvider).watchFor(id),
);
