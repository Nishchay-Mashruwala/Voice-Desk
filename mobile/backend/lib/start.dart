import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:path_provider/path_provider.dart';

import 'data/db.dart';
import 'data/providers.dart';
import 'data/recordings_repository.dart';
import 'engine/audio/recording_notification.dart';
import 'engine/models/downloader.dart';
import 'engine/models/model_store.dart';
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
  final documents = await getApplicationDocumentsDirectory();
  final root = Directory('${documents.path}/recordings');
  await root.create(recursive: true);
  final recordings = LocalRecordingsRepository(db, root);
  await recordings.recoverInterrupted();
  await recordings.removeOrphanFolders();

  final models = Directory('${(await getApplicationSupportDirectory()).path}/models');
  await models.create(recursive: true);
  // Plan 2a's English model gave way to its transducer variant.
  await ModelStore(models, Downloader()).removeOldCtc();

  return [
    databaseProvider.overrideWithValue(db),
    // drift_flutter keeps `voicedesk` in the documents folder.
    databaseFileProvider.overrideWithValue(File('${documents.path}/voicedesk.sqlite')),
    recordingsRootProvider.overrideWithValue(root),
    modelsRootProvider.overrideWithValue(models),
  ];
}
