import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/tasks/quote_check.dart';
import 'package:mobile_backend/engine/tasks/task_answer.dart';

import 'lines.dart';

FoundTask said(String? quote) => FoundTask(description: 'x', quote: quote);

void main() {
  const me = ['Nishchay', 'Nishu'];
  final meeting = [
    line(0, 'Person 1', "Okay let's get started. Quick updates on the launch."),
    line(12, 'Person 1', 'Great. Nishchay, can you send the quarterly report to Priya by Friday?'),
    line(18, 'Me', "Sure, I'll do that. I'll also fix the signup bug before tomorrow's standup."),
    line(25, 'Person 2', "I'll take care of the marketing email this week."),
    line(31, 'Person 1', 'Thanks. Priya, please update the roadmap slide.'),
    line(40, 'Person 1', 'Hello, hello, good morning. Nishchay, you need to finish the budget.'),
    line(50, 'Priya', 'Nishchay, client को demo कल तक भेजना है, okay?'),
    line(55, 'Rahul', 'मैं database migration Friday तक कर लूँगा।'),
    line(60, 'Person 1', 'નિશ્ચય, તું આ week ના end સુધીમાં budget sheet તૈયાર કરી દેજે.'),
    line(65, 'Person 1', 'Hey Nishu, quick one. Can you renew the domain?'),
    line(70, 'Person 1', "And I'll update the DNS records after that."),
  ];
  bool keep(String? quote, [List<Phrase>? lines]) => keepTask(said(quote), lines ?? meeting, ownerNames: me);

  test("the owner's own line is kept", () {
    expect(keep("I'll also fix the signup bug"), isTrue);
    expect(keep("Me: Sure, I'll do that."), isTrue, reason: "the label in the quote is read as the line's");
  });

  test('a line to him by name or "you" is kept', () {
    expect(keep('Nishchay, can you send the quarterly report to Priya by Friday?'), isTrue);
    expect(keep('Person 1: Hey Nishu, quick one. Can you renew the domain?'), isTrue);
    expect(keep('Priya: Nishchay, client को demo कल तक भेजना है, okay?'), isTrue);
  });

  test('"Priya, please update the slide" is dropped', () {
    expect(keep('Priya, please update the roadmap slide.'), isFalse);
    expect(keep("I'll take care of the marketing email this week."), isFalse, reason: "someone else's promise");
    expect(keep('मैं database migration Friday तक कर लूँगा।'), isFalse);
    expect(keep("I'll update the DNS records after that."), isFalse);
  });

  test('"Hello, …Nishchay, you need…" is kept (greeting)', () {
    expect(keep('Hello, hello, good morning. Nishchay, you need to finish the budget.'), isTrue);
  });

  test("his name in Gujarati script is not someone else's", () {
    expect(keep('નિશ્ચય, તું આ week ના end સુધીમાં budget sheet તૈયાર કરી દેજે.'), isTrue);
  });

  test('a quote not in the transcript is kept', () {
    expect(keep('send the slides to the board'), isTrue);
    expect(keep(null), isTrue);
    expect(keep(''), isTrue);
  });

  test('with no "Me" line, his own "I\'ll send it" is dropped', () {
    final noMe = [line(0, 'Person 1', 'Can someone send the deck?'), line(4, 'Person 2', "I'll send it tonight.")];
    expect(keep("I'll send it tonight.", noMe), isFalse);
    final noSpeakers = [line(0, null, 'Nishchay, please send the deck.'), line(4, null, "I'll send it tonight.")];
    expect(keep('Nishchay, please send the deck.', noSpeakers), isTrue);
    expect(keep("I'll send it tonight.", noSpeakers), isFalse);
  });

  test('where the quoted line starts', () {
    expect(quoteStartMs(said('fix the signup bug'), meeting), 18000);
    expect(quoteStartMs(said('Priya: Nishchay, client को demo'), meeting), 50000);
    expect(quoteStartMs(said('not said'), meeting), isNull);
    expect(quoteStartMs(said(null), meeting), isNull);
  });

  test('a short line like "OK." is not where every quote comes from', () {
    final lines = [
      line(5, 'Me', 'OK.'),
      line(180, 'Rahul', "I'll book the hall by Friday."),
    ];
    expect(keepTask(said("I'll book the hall by Friday"), lines, ownerNames: me), isFalse);
    expect(quoteStartMs(said("I'll book the hall by Friday"), lines), 180000);
    expect(quoteStartMs(said('OK.'), lines), 5000);
  });
}
