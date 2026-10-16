import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/db.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/engine/setup_flag.dart';

void main() {
  test('setup is not done on a new phone, and stays done once finished', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(c.dispose);
    expect(await c.read(setupDoneProvider.future), isFalse);
    await c.read(setupDoneProvider.notifier).finish();
    final again = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(again.dispose);
    expect(await again.read(setupDoneProvider.future), isTrue);
  });
}
