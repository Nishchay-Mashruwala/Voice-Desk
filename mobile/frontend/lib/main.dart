import 'package:flutter/material.dart';
import 'package:mobile_backend/start.dart';

import 'start_app.dart';
import 'ui/app.dart';
import 'ui/licences.dart';

Future<void> main() {
  registerModelLicences();
  return startApp(openBackend: openBackend, keepPortrait: keepPortrait, run: runApp);
}
