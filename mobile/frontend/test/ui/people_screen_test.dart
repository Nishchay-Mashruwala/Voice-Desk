import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/speakers_repository.dart';
import 'package:mobile_frontend/ui/settings/people_screen.dart';
import 'package:mobile_frontend/ui/settings/voice_training_screen.dart';

import 'fakes.dart';

/// Records what the People screen asks for.
class FakePeople implements SpeakersRepository {
  final calls = <String>[];
  @override
  Future<void> renamePerson(int id, String name) async => calls.add('rename:$id:$name');
  @override
  Future<void> forgetPerson(int id) async => calls.add('forget:$id');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late FakePeople repo;

  Future<void> show(WidgetTester t, {List<String> people = const ['Asha', 'Kiran']}) async {
    repo = FakePeople();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...quietBackend(myVoice: (Float32List(192), DateTime(2026, 10, 15))),
          speakersRepositoryProvider.overrideWithValue(repo),
          peopleProvider.overrideWith(
            (ref) => Stream.value([
              for (final (i, n) in people.indexed) RememberedPerson(id: i + 1, name: n, speechMs: 5000),
            ]),
          ),
        ],
        child: const MaterialApp(home: PeopleScreen()),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('your voice is at the top and opens the training', (t) async {
    await show(t);
    expect(find.text('Your voice'), findsOneWidget);
    expect(find.text('Voice saved 15 Oct 2026'), findsOneWidget);
    await t.tap(find.text('Your voice'));
    await t.pumpAndSettle();
    expect(find.byType(VoiceTrainingScreen), findsOneWidget);
  });

  testWidgets('People lists the remembered names; Forget asks, then forgets', (t) async {
    await show(t);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Kiran'), findsOneWidget);
    await t.tap(find.byKey(const Key('forget-2')));
    await t.pumpAndSettle();
    expect(find.text("Forget Kiran's voice?"), findsOneWidget);
    expect(find.text('Their name stays on past recordings.'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(repo.calls, isEmpty);
    await t.tap(find.byKey(const Key('forget-2')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Forget'));
    await t.pumpAndSettle();
    expect(repo.calls, ['forget:2']);
  });

  testWidgets('a remembered person can be renamed', (t) async {
    await show(t);
    await t.tap(find.byKey(const Key('rename-1')));
    await t.pumpAndSettle();
    expect(find.text('Rename Asha to'), findsOneWidget);
    await t.enterText(find.byKey(const Key('person-name')), 'Asha Patel');
    await t.tap(find.widgetWithText(FilledButton, 'Rename'));
    await t.pumpAndSettle();
    expect(repo.calls, ['rename:1:Asha Patel']);
  });

  testWidgets('an empty name, or Me, is refused', (t) async {
    await show(t);
    await t.tap(find.byKey(const Key('rename-1')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('person-name')), 'Me');
    await t.tap(find.widgetWithText(FilledButton, 'Rename'));
    await t.pumpAndSettle();
    expect(find.text('Type a name'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('no one remembered yet says how to add someone', (t) async {
    await show(t, people: const []);
    expect(find.textContaining('No one yet'), findsOneWidget);
  });
}
