import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_frontend/start_app.dart';

void main() {
  test('the app starts even when the portrait lock is never answered', () async {
    // Started by Android in the background (after an update or a restart) there
    // is no window yet, and the platform never answers the orientation request.
    Widget? shown;
    await startApp(
      openBackend: () async => const [],
      keepPortrait: () => Completer<void>().future,
      run: (app) => shown = app,
    ).timeout(const Duration(seconds: 2));
    expect(shown, isA<ProviderScope>());
  });
}
