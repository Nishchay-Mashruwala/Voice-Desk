import 'package:flutter/foundation.dart';

/// A word and when it was said (ms from the recording's start).
@immutable
class Word {
  const Word(this.text, this.startMs, this.endMs);

  final String text;
  final int startMs;
  final int endMs;

  @override
  bool operator ==(Object other) => other is Word && other.text == text && other.startMs == startMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(text, startMs, endMs);

  @override
  String toString() => 'Word($text, $startMs–$endMs)';
}

/// What was said between two pauses: one line of the transcript.
@immutable
class Phrase {
  const Phrase({required this.startMs, required this.endMs, required this.text, required this.words});

  final int startMs;
  final int endMs;
  final String text;
  final List<Word> words;

  @override
  bool operator ==(Object other) =>
      other is Phrase &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      other.text == text &&
      listEquals(other.words, words);

  @override
  int get hashCode => Object.hash(startMs, endMs, text, Object.hashAll(words));

  @override
  String toString() => 'Phrase($startMs–$endMs: $text)';
}
