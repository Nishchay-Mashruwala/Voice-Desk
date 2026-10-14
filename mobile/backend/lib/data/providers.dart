import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db.dart';
import 'recording.dart';
import 'recordings_repository.dart';
import 'settings_repository.dart';
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

final transcriptRepositoryProvider = Provider<TranscriptRepository>((ref) => TranscriptRepository(ref.watch(databaseProvider)));

/// A recording's transcript lines, updated as they are saved.
final transcriptProvider = StreamProvider.family<List<Phrase>, int>(
  (ref, id) => ref.watch(transcriptRepositoryProvider).watch(id),
);
