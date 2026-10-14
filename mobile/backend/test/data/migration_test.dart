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
}
