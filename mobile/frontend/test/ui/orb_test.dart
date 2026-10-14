import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_frontend/ui/theme.dart';
import 'package:mobile_frontend/ui/widgets/orb.dart';

void main() {
  var taps = 0;

  Future<void> show(WidgetTester t, OrbState state) async {
    taps = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: vdTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: Orb(state: state, level: 0.5, onPressed: () => taps++),
          ),
        ),
      ),
    );
  }

  testWidgets('idle: a mic to start recording', (t) async {
    await show(t, OrbState.idle);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
    await t.tap(find.byType(Orb));
    expect(taps, 1);
  });

  testWidgets('recording: a stop button with rings that keep moving', (t) async {
    await show(t, OrbState.recording);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 500));
    expect(t.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('paused: still a stop button, and nothing moves', (t) async {
    await show(t, OrbState.paused);
    expect(find.text('Stop'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 500));
    expect(t.binding.hasScheduledFrame, isFalse);
  });
}
