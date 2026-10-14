import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:path_provider/path_provider.dart';

import 'data/db.dart';
import 'data/providers.dart';
import 'data/recordings_repository.dart';
import 'engine/audio/recording_notification.dart';
import 'engine/models/speech_model.dart';

/// Gets the backend ready at app start and returns what the app's
/// `ProviderScope` needs: opens the database and the recordings folder, sets
/// up the recording notification, and recovers recordings a crash or a kill
/// cut off.
Future<List<Override>> openBackend() async {
  WidgetsFlutterBinding.ensureInitialized();
  initForegroundTask();
  // A recording notification left by a killed app: nothing is recording now.
  if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();

  final db = AppDatabase.open();
  final root = Directory('${(await getApplicationDocumentsDirectory()).path}/recordings');
  await root.create(recursive: true);
  await LocalRecordingsRepository(db, root).recoverInterrupted();

  final models = Directory('${(await getApplicationSupportDirectory()).path}/models');
  await models.create(recursive: true);

  return [
    databaseProvider.overrideWithValue(db),
    recordingsRootProvider.overrideWithValue(root),
    modelsRootProvider.overrideWithValue(models),
  ];
}
