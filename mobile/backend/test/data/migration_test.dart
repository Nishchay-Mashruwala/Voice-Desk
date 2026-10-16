import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('a version-1 database opens as version 2 with its recordings kept', () async {
    final file = File('${Directory.systemTemp.createTempSync('mig').path}/v1.db');
    // The version-1 tables, exactly as Plan 1's app created them.
    final raw = sqlite3.open(file.path)
      ..execute('CREATE TABLE "meetings" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "title" TEXT NOT NULL, '
          '"kind" TEXT NOT NULL DEFAULT \'recording\', "contact" TEXT NULL, "started_at" INTEGER NOT NULL, '
          '"duration_ms" INTEGER NULL, "status" TEXT NOT NULL, "step" TEXT NULL, "error" TEXT NULL, '
          '"summary" TEXT NULL, "audio_path" TEXT NULL)')
      ..execute('CREATE TABLE "settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))')
      ..execute("INSERT INTO meetings (title, started_at, status, duration_ms) VALUES ('Weekly', 1760000000, 'queued', 5000)")
      ..execute('PRAGMA user_version = 1');
    raw.close();

    final db = AppDatabase(NativeDatabase(file));
    final m = (await db.select(db.meetings).get()).single;
    expect(m.title, 'Weekly');
    expect(m.processedMs, 0);
    expect(m.attempts, 0);
    expect(await db.select(db.transcriptLines).get(), isEmpty);
    await db.close();
  });

  test('a version-2 database opens as version 3 with its recordings English-only', () async {
    final file = File('${Directory.systemTemp.createTempSync('mig').path}/v2.db');
    // The version-2 tables, as Plan 2a's app created them.
    final raw = sqlite3.open(file.path)
      ..execute('CREATE TABLE "meetings" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "title" TEXT NOT NULL, '
          '"kind" TEXT NOT NULL DEFAULT \'recording\', "contact" TEXT NULL, "started_at" INTEGER NOT NULL, '
          '"duration_ms" INTEGER NULL, "status" TEXT NOT NULL, "step" TEXT NULL, "error" TEXT NULL, '
          '"summary" TEXT NULL, "audio_path" TEXT NULL, "processed_ms" INTEGER NOT NULL DEFAULT 0, '
          '"attempts" INTEGER NOT NULL DEFAULT 0)')
      ..execute('CREATE TABLE "settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))')
      ..execute('CREATE TABLE "transcript_lines" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
          '"meeting_id" INTEGER NOT NULL REFERENCES meetings (id) ON DELETE CASCADE, "start_ms" INTEGER NOT NULL, '
          '"end_ms" INTEGER NOT NULL, "text" TEXT NOT NULL, "words_json" TEXT NOT NULL)')
      ..execute("INSERT INTO meetings (title, started_at, status, duration_ms, processed_ms) "
          "VALUES ('Weekly', 1760000000, 'done', 5000, 5000)")
      ..execute("INSERT INTO transcript_lines (meeting_id, start_ms, end_ms, text, words_json) "
          "VALUES (1, 0, 900, 'hello', '[[\"hello\",0,900]]')")
      ..execute('PRAGMA user_version = 2');
    raw.close();

    final db = AppDatabase(NativeDatabase(file));
    final m = (await db.select(db.meetings).get()).single;
    expect((m.languages, m.preferIndic, m.englishModel), ('en', 'gu', 'faster'));
    expect(m.processedMs, 5000);
    expect((await db.select(db.transcriptLines).get()).single.content, 'hello');
    await db.close();
  });

  test('a version-3 database opens as version 4 with no drafts', () async {
    final file = File('${Directory.systemTemp.createTempSync('mig').path}/v3.db');
    // The version-3 tables, as Plan 2b's app created them.
    final raw = sqlite3.open(file.path)
      ..execute('CREATE TABLE "meetings" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "title" TEXT NOT NULL, '
          '"kind" TEXT NOT NULL DEFAULT \'recording\', "contact" TEXT NULL, "started_at" INTEGER NOT NULL, '
          '"duration_ms" INTEGER NULL, "status" TEXT NOT NULL, "step" TEXT NULL, "error" TEXT NULL, '
          '"summary" TEXT NULL, "audio_path" TEXT NULL, "processed_ms" INTEGER NOT NULL DEFAULT 0, '
          '"attempts" INTEGER NOT NULL DEFAULT 0, "languages" TEXT NOT NULL DEFAULT \'en\', '
          '"prefer_indic" TEXT NOT NULL DEFAULT \'gu\', "english_model" TEXT NOT NULL DEFAULT \'faster\')')
      ..execute('CREATE TABLE "settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))')
      ..execute('CREATE TABLE "transcript_lines" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
          '"meeting_id" INTEGER NOT NULL REFERENCES meetings (id) ON DELETE CASCADE, "start_ms" INTEGER NOT NULL, '
          '"end_ms" INTEGER NOT NULL, "text" TEXT NOT NULL, "words_json" TEXT NOT NULL)')
      ..execute("INSERT INTO meetings (title, started_at, status, duration_ms, processed_ms, languages) "
          "VALUES ('Weekly', 1760000000, 'done', 5000, 5000, 'en,gu')")
      ..execute("INSERT INTO transcript_lines (meeting_id, start_ms, end_ms, text, words_json) "
          "VALUES (1, 0, 900, 'hello', '[]')")
      ..execute('PRAGMA user_version = 3');
    raw.close();

    final db = AppDatabase(NativeDatabase(file));
    final m = (await db.select(db.meetings).get()).single;
    expect((m.reprocessing, m.languages), (false, 'en,gu'));
    expect((await db.select(db.transcriptLines).get()).single.draft, isFalse);
    await db.close();
  });

  test('a version-4 database opens as version 5, old recordings without speakers', () async {
    final file = File('${Directory.systemTemp.createTempSync('mig').path}/v4.db');
    // The version-4 tables, as Plan 2c-a's app created them.
    final raw = sqlite3.open(file.path)
      ..execute('CREATE TABLE "meetings" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "title" TEXT NOT NULL, '
          '"kind" TEXT NOT NULL DEFAULT \'recording\', "contact" TEXT NULL, "started_at" INTEGER NOT NULL, '
          '"duration_ms" INTEGER NULL, "status" TEXT NOT NULL, "step" TEXT NULL, "error" TEXT NULL, '
          '"summary" TEXT NULL, "audio_path" TEXT NULL, "processed_ms" INTEGER NOT NULL DEFAULT 0, '
          '"attempts" INTEGER NOT NULL DEFAULT 0, "languages" TEXT NOT NULL DEFAULT \'en\', '
          '"prefer_indic" TEXT NOT NULL DEFAULT \'gu\', "english_model" TEXT NOT NULL DEFAULT \'faster\', '
          '"reprocessing" INTEGER NOT NULL DEFAULT 0 CHECK ("reprocessing" IN (0, 1)))')
      ..execute('CREATE TABLE "settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))')
      ..execute('CREATE TABLE "transcript_lines" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
          '"meeting_id" INTEGER NOT NULL REFERENCES meetings (id) ON DELETE CASCADE, "start_ms" INTEGER NOT NULL, '
          '"end_ms" INTEGER NOT NULL, "text" TEXT NOT NULL, "words_json" TEXT NOT NULL, '
          '"draft" INTEGER NOT NULL DEFAULT 0 CHECK ("draft" IN (0, 1)))')
      ..execute("INSERT INTO meetings (title, started_at, status, duration_ms) VALUES ('Weekly', 1760000000, 'done', 5000)")
      ..execute("INSERT INTO transcript_lines (meeting_id, start_ms, end_ms, text, words_json) VALUES (1, 0, 900, 'hello', '[]')")
      ..execute('PRAGMA user_version = 4');
    raw.close();

    final db = AppDatabase(NativeDatabase(file));
    expect((await db.select(db.meetings).get()).single.speakers, isFalse);
    final line = (await db.select(db.transcriptLines).get()).single;
    expect((line.voicesJson, line.speaker, line.speakerGroup), ('[]', null, null));
    expect(await db.select(db.meetingSpeakers).get(), isEmpty);
    expect(await db.select(db.people).get(), isEmpty);
    await db.close();
  });

  test('a version-5 database opens as version 6, all audio still there', () async {
    final file = File('${Directory.systemTemp.createTempSync('mig').path}/v5.db');
    // The version-5 meetings table, as Plan 3's app created it.
    final raw = sqlite3.open(file.path)
      ..execute('CREATE TABLE "meetings" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "title" TEXT NOT NULL, '
          '"kind" TEXT NOT NULL DEFAULT \'recording\', "contact" TEXT NULL, "started_at" INTEGER NOT NULL, '
          '"duration_ms" INTEGER NULL, "status" TEXT NOT NULL, "step" TEXT NULL, "error" TEXT NULL, '
          '"summary" TEXT NULL, "audio_path" TEXT NULL, "processed_ms" INTEGER NOT NULL DEFAULT 0, '
          '"attempts" INTEGER NOT NULL DEFAULT 0, "languages" TEXT NOT NULL DEFAULT \'en\', '
          '"prefer_indic" TEXT NOT NULL DEFAULT \'gu\', "english_model" TEXT NOT NULL DEFAULT \'faster\', '
          '"reprocessing" INTEGER NOT NULL DEFAULT 0 CHECK ("reprocessing" IN (0, 1)), '
          '"speakers" INTEGER NOT NULL DEFAULT 0 CHECK ("speakers" IN (0, 1)))')
      ..execute('CREATE TABLE "settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))')
      ..execute("INSERT INTO meetings (title, started_at, status, duration_ms) VALUES ('Weekly', 1760000000, 'done', 5000)")
      ..execute('PRAGMA user_version = 5');
    raw.close();

    final db = AppDatabase(NativeDatabase(file));
    final m = (await db.select(db.meetings).get()).single;
    expect((m.audioDeleted, m.flacFailures), (false, 0));
    await db.close();
  });

  test('a version-6 database opens as version 7, no recording waiting for tasks', () async {
    final file = File('${Directory.systemTemp.createTempSync('mig').path}/v6.db');
    // The version-6 meetings table, as Plan 2c-b's app created it.
    final raw = sqlite3.open(file.path)
      ..execute('CREATE TABLE "meetings" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "title" TEXT NOT NULL, '
          '"kind" TEXT NOT NULL DEFAULT \'recording\', "contact" TEXT NULL, "started_at" INTEGER NOT NULL, '
          '"duration_ms" INTEGER NULL, "status" TEXT NOT NULL, "step" TEXT NULL, "error" TEXT NULL, '
          '"summary" TEXT NULL, "audio_path" TEXT NULL, "processed_ms" INTEGER NOT NULL DEFAULT 0, '
          '"attempts" INTEGER NOT NULL DEFAULT 0, "languages" TEXT NOT NULL DEFAULT \'en\', '
          '"prefer_indic" TEXT NOT NULL DEFAULT \'gu\', "english_model" TEXT NOT NULL DEFAULT \'faster\', '
          '"reprocessing" INTEGER NOT NULL DEFAULT 0 CHECK ("reprocessing" IN (0, 1)), '
          '"speakers" INTEGER NOT NULL DEFAULT 0 CHECK ("speakers" IN (0, 1)), '
          '"audio_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("audio_deleted" IN (0, 1)), '
          '"flac_failures" INTEGER NOT NULL DEFAULT 0)')
      ..execute('CREATE TABLE "settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))')
      ..execute("INSERT INTO meetings (title, started_at, status, duration_ms) VALUES ('Weekly', 1760000000, 'done', 5000)")
      ..execute('PRAGMA user_version = 6');
    raw.close();

    final db = AppDatabase(NativeDatabase(file));
    final m = (await db.select(db.meetings).get()).single;
    expect((m.tasksStatus, m.tasksPart, m.tasksWork), ('none', 0, ''));
    expect(await db.select(db.tasks).get(), isEmpty);
    await db.close();
  });
}
