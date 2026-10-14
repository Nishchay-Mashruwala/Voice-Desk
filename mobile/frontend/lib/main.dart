import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_backend/start.dart';

import 'ui/app.dart';

Future<void> main() async {
  final backend = await openBackend();
  await keepPortrait();
  runApp(ProviderScope(overrides: backend, child: const VoiceDeskApp()));
}
