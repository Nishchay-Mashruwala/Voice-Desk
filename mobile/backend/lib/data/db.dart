import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'db.g.dart';

/// Recordings and calls (named as the desktop's table).
class Meetings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  /// `recording` or `call`.
  TextColumn get kind => text().withDefault(const Constant('recording'))();
  TextColumn get contact => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  IntColumn get durationMs => integer().nullable()();
  /// `RecordingStatus.id`.
  TextColumn get status => text()();
  TextColumn get step => text().nullable()();
  TextColumn get error => text().nullable()();
  TextColumn get summary => text().nullable()();
  /// The FLAC file once processed (Plan 2); until then the pieces in the recording's folder.
  TextColumn get audioPath => text().nullable()();

  /// Speech to text is done up to here (ms from the start); a job resumes here.
  IntColumn get processedMs => integer().withDefault(const Constant(0))();

  /// Processing jobs started since the last one that finished: a job cut off
  /// twice (the app killed while processing) stops with a message.
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

/// One phrase of a recording's transcript.
class TranscriptLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get meetingId => integer().references(Meetings, #id, onDelete: KeyAction.cascade)();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
  TextColumn get content => text().named('text')();

  /// `[["word", startMs, endMs], …]`.
  TextColumn get wordsJson => text()();
}

/// Small key/value settings.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Meetings, Settings, TranscriptLines])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// The app's database file.
  AppDatabase.open() : super(driftDatabase(name: 'voicedesk'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(transcriptLines);
            await m.addColumn(meetings, meetings.processedMs);
            await m.addColumn(meetings, meetings.attempts);
          }
        },
        beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
      );
}
