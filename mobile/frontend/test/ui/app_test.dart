import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_frontend/ui/app.dart';

import 'fakes.dart';

void main() {
  testWidgets('shows Record, Tasks and Settings tabs, Record first', (t) async {
    await t.pumpWidget(ProviderScope(overrides: quietBackend(), child: const VoiceDeskApp()));
    expect(find.text('Record'), findsWidgets);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    await t.tap(find.text('Tasks'));
    await t.pumpAndSettle();
    expect(find.text('Tasks appear here after your recordings are processed.'), findsOneWidget);
  });

  testWidgets('the app asks for portrait only', (t) async {
    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    await keepPortrait();
    final call = calls.singleWhere((c) => c.method == 'SystemChrome.setPreferredOrientations');
    expect(call.arguments, ['DeviceOrientation.portraitUp']);
  });
}
