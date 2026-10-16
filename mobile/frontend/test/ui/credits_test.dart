import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/permissions.dart';
import 'package:mobile_frontend/ui/licences.dart';
import 'package:mobile_frontend/ui/settings/credits_screen.dart';
import 'package:mobile_frontend/ui/settings/settings_screen.dart';

import 'fakes.dart';
import 'settings_screen_test.dart' show FakePermissions;

void main() {
  testWidgets('About opens Licences & credits with every credit', (t) async {
    t.view.physicalSize = const Size(1080, 8100);
    t.view.devicePixelRatio = 2.7;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWithValue(FakePermissions()),
        appVersionProvider.overrideWith((ref) async => '1.0.0'),
        ...quietBackend(),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Licences & credits'));
    await t.pumpAndSettle();
    expect(find.byType(CreditsScreen), findsOneWidget);
    expect(
      find.text('Speech model by NVIDIA (Parakeet), CC BY 4.0; converted to ONNX int8 by the sherpa-onnx project.'),
      findsOneWidget,
    );
    for (final what in ['AI4Bharat', 'Parismita Global Solutions', 'Silero VAD', 'CAM++', 'sherpa-onnx, by', 'SCOWL']) {
      expect(find.textContaining(what), findsWidgets, reason: what);
    }
    expect(find.byKey(const Key('credit')), findsNWidgets(7));
    expect(find.text('All licences'), findsOneWidget);
  });

  test('All licences shows the models’ licences too', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerModelLicences();
    registerModelLicences(); // once is enough, however often it is called
    final packages = <String>[];
    final texts = <String>[];
    await for (final l in LicenseRegistry.licenses) {
      packages.addAll(l.packages);
      texts.add(l.paragraphs.map((p) => p.text).join('\n'));
    }
    for (final p in ['Parakeet', 'IndicConformer', 'IndicConformer phone versions', 'Silero VAD', 'CAM++', 'English word list']) {
      expect(packages.where((x) => x == p), hasLength(1), reason: p);
    }
    expect(texts.any((t) => t.contains('Copyright (c) 2024 AI4Bhārat')), isTrue);
    expect(texts.any((t) => t.contains('Copyright (c) 2020-present Silero Team')), isTrue);
    expect(texts.any((t) => t.contains('Kevin Atkinson')), isTrue);
    expect(texts.any((t) => t.contains('Attribution 4.0 International')), isTrue);
  });
}
