import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';

/// The first-start setup has been gone through (it shows once).
const kSetupDoneKey = 'setup_done';

final setupDoneProvider = AsyncNotifierProvider<SetupDone, bool>(SetupDone.new);

class SetupDone extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.read(settingsRepositoryProvider).getBool(kSetupDoneKey);

  Future<void> finish() async {
    await ref.read(settingsRepositoryProvider).setBool(kSetupDoneKey, true);
    state = const AsyncData(true);
  }
}
