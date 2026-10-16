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
  /// The checked FLAC once processing ended (`audio.flac`); until then the
  /// pieces in the recording's folder.
  TextColumn get audioPath => text().nullable()();

  /// Speech to text is done up to here (ms from the start); a job resumes here.
  IntColumn get processedMs => integer().withDefault(const Constant(0))();

  /// Processing jobs started since the last one that finished: a job cut off
  /// twice (the app killed while processing) stops with a message.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// How it is turned into text (`SpeechSetup`), fixed when it is made:
  /// languages (`en,gu`), Hindi or Gujarati when unclear, the English model.
  TextColumn get languages => text().withDefault(const Constant('en'))();
  TextColumn get preferIndic => text().withDefault(const Constant('gu'))();
  TextColumn get englishModel => text().withDefault(const Constant('faster'))();

  /// Being processed again: its new lines are drafts until the run completes.
  BoolColumn get reprocessing => boolean().withDefault(const Constant(false))();

  /// Made with speaker detection on (part of its setup).
  BoolColumn get speakers => boolean().withDefault(const Constant(false))();

  /// Its audio was deleted by "Keep recordings for" (the text stays).
  BoolColumn get audioDeleted => boolean().withDefault(const Constant(false))();

  /// Times its FLAC didn't match the pieces (it stops trying at 3).
  IntColumn get flacFailures => integer().withDefault(const Constant(0))();

  /// Its summary and tasks (`TasksStatus.id`): none, waiting, finding, found, failed.
  TextColumn get tasksStatus => text().withDefault(const Constant('none'))();

  /// The task step continues from this part (a step that gave way, or was cut off).
  IntColumn get tasksPart => integer().withDefault(const Constant(0))();

  /// The parts' answers so far (JSON), or why it failed.
  TextColumn get tasksWork => text().withDefault(const Constant(''))();
}

/// One phrase of a recording's transcript.
class TranscriptLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get meetingId => integer().references(Meetings, #id, onDelete: KeyAction.cascade)();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
  TextColumn get content => text().named('text')();

  /// `[["word", startMs, endMs], …]`, with the confidence as a fourth value when known.
  TextColumn get wordsJson => text()();

  /// A line of a run of Process again not finished yet: not shown; it replaces
  /// the recording's lines when the run completes.
  BoolColumn get draft => boolean().withDefault(const Constant(false))();

  /// Voice prints: `[[startMs, endMs, "<base64 float32>"], …]`.
  TextColumn get voicesJson => text().withDefault(const Constant('[]'))();

  /// Who said it (the name shown) and the recording's speaker group.
  TextColumn get speaker => text().nullable()();
  IntColumn get speakerGroup => integer().nullable()();
}

/// A recording's speakers: one row per group the speakers step found.
class MeetingSpeakers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get meetingId => integer().references(Meetings, #id, onDelete: KeyAction.cascade)();
  IntColumn get groupId => integer()();
  TextColumn get label => text()();
  TextColumn get printB64 => text()();
  IntColumn get speechMs => integer()();
  BoolColumn get draft => boolean().withDefault(const Constant(false))();
}

/// People whose voices are recognised in new recordings.
class People extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// The name in lowercase: one person per name, whatever its case.
  TextColumn get nameKey => text().unique()();
  TextColumn get printB64 => text()();
  IntColumn get speechMs => integer()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// The owner's tasks: found in a recording by the task AI, or added by him.
@DataClassName('TaskRow')
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The recording it came from (null: added on the Tasks tab).
  IntColumn get meetingId => integer().nullable().references(Meetings, #id, onDelete: KeyAction.cascade)();
  TextColumn get description => text()();
  TextColumn get assignedBy => text().nullable()();
  TextColumn get due => text().nullable()();
  TextColumn get quote => text().nullable()();

  /// Where the quoted line starts in the recording.
  IntColumn get quoteMs => integer().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();

  /// Its place on the Tasks tab.
  IntColumn get position => integer()();

  /// Found by the task AI (not added by the owner).
  BoolColumn get fromAi => boolean().withDefault(const Constant(false))();

  /// Changed or ticked by the owner: a re-run keeps it.
  BoolColumn get edited => boolean().withDefault(const Constant(false))();

  /// An AI task the owner deleted: hidden, kept so a re-run doesn't find it again.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}

/// Small key/value settings.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Meetings, Settings, TranscriptLines, MeetingSpeakers, People, Tasks])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// The app's database file.
  AppDatabase.open() : super(driftDatabase(name: 'voicedesk'));

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(transcriptLines);
            await m.addColumn(meetings, meetings.processedMs);
            await m.addColumn(meetings, meetings.attempts);
          }
          if (from < 3) {
            await m.addColumn(meetings, meetings.languages);
            await m.addColumn(meetings, meetings.preferIndic);
            await m.addColumn(meetings, meetings.englishModel);
          }
          if (from < 4) {
            await m.addColumn(meetings, meetings.reprocessing);
            // From version 1 the lines table was just created, with this column.
            if (from >= 2) await m.addColumn(transcriptLines, transcriptLines.draft);
          }
          if (from < 5) {
            await m.addColumn(meetings, meetings.speakers);
            if (from >= 2) {
              await m.addColumn(transcriptLines, transcriptLines.voicesJson);
              await m.addColumn(transcriptLines, transcriptLines.speaker);
              await m.addColumn(transcriptLines, transcriptLines.speakerGroup);
            }
            await m.createTable(meetingSpeakers);
            await m.createTable(people);
          }
          if (from < 6) {
            await m.addColumn(meetings, meetings.audioDeleted);
            await m.addColumn(meetings, meetings.flacFailures);
          }
          if (from < 7) {
            await m.addColumn(meetings, meetings.tasksStatus);
            await m.addColumn(meetings, meetings.tasksPart);
            await m.addColumn(meetings, meetings.tasksWork);
            await m.createTable(tasks);
          }
        },
        beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
      );
}
