import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'ui/app.dart';

/// Opens the backend and shows the app.
///
/// The portrait lock isn't waited for: started by Android in the background
/// (the notification library restarts the app after an update or a reboot)
/// there is no window yet, the request is never answered, and the app stayed
/// black. The manifest keeps the app in portrait anyway.
Future<void> startApp({
  required Future<List<Override>> Function() openBackend,
  required Future<void> Function() keepPortrait,
  required void Function(Widget app) run,
}) async {
  final backend = await openBackend();
  unawaited(keepPortrait());
  run(ProviderScope(overrides: backend, child: const VoiceDeskApp()));
}
