import 'db.dart';

/// Small saved flags ("asked about battery once", …).
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<bool> getBool(String key, {bool orElse = false}) async {
    final row = await (_db.select(_db.settings)..where((s) => s.key.equals(key))).getSingleOrNull();
    return row == null ? orElse : row.value == 'true';
  }

  Future<void> setBool(String key, bool value) =>
      _db.into(_db.settings).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: '$value'));

  Future<String> getString(String key, {String orElse = ''}) async =>
      (await (_db.select(_db.settings)..where((s) => s.key.equals(key))).getSingleOrNull())?.value ?? orElse;

  Future<void> setString(String key, String value) =>
      _db.into(_db.settings).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}
