import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_frontend/ui/theme.dart';
import 'package:mobile_frontend/ui/widgets/badge.dart';
import 'package:mobile_frontend/ui/widgets/page_header.dart';

Widget app(Widget child) => MaterialApp(
  theme: vdTheme(Brightness.dark),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('the page header reads as one sentence with its subtitle', (t) async {
    await t.pumpWidget(
      app(const PageHeader(lead: 'Speak, and it ', highlight: 'writes', tail: '.', subtitle: 'It keeps going.')),
    );
    expect(find.bySemanticsLabel('Speak, and it writes.'), findsOneWidget);
    expect(find.text('writes'), findsOneWidget);
    expect(find.text('It keeps going.'), findsOneWidget);
  });

  testWidgets('a badge shows its text in its kind of colour', (t) async {
    await t.pumpWidget(
      app(
        const Column(
          children: [
            VdBadge('Recording…', kind: BadgeKind.rec),
            VdBadge('Waiting to be processed'),
          ],
        ),
      ),
    );
    expect(t.widget<Text>(find.text('Recording…')).style!.color, VdColors.rec);
    expect(t.widget<Text>(find.text('Waiting to be processed')).style!.color, VdColors.dark.muted);
  });
}
