import 'package:flutter/foundation.dart';

import '../engine/speakers/voice_print.dart';

/// A word and when it was said (ms from the recording's start).
@immutable
class Word {
  const Word(this.text, this.startMs, this.endMs, [this.conf]);

  final String text;
  final int startMs;
  final int endMs;

  /// How sure the recognizer was (0..1); null when it doesn't say.
  final double? conf;

  @override
  bool operator ==(Object other) =>
      other is Word && other.text == text && other.startMs == startMs && other.endMs == endMs && other.conf == conf;

  @override
  int get hashCode => Object.hash(text, startMs, endMs, conf);

  @override
  String toString() => 'Word($text, $startMs–$endMs${conf == null ? '' : ', $conf'})';
}

/// What was said between two pauses: one line of the transcript.
@immutable
class Phrase {
  const Phrase({
    required this.startMs,
    required this.endMs,
    required this.text,
    required this.words,
    this.id,
    this.voices = const [],
    this.speaker,
    this.speakerGroup,
  });

  /// Its line in the database (null for lines not saved yet).
  final int? id;

  final int startMs;
  final int endMs;
  final String text;
  final List<Word> words;

  /// Voice prints of its audio (for who said it); not part of equality.
  final List<VoicePiece> voices;

  /// Who said it (the name shown), and their group in the recording; null
  /// without speaker detection.
  final String? speaker;
  final int? speakerGroup;

  /// The same line with [voices].
  Phrase withVoices(List<VoicePiece> voices) => Phrase(
      startMs: startMs,
      endMs: endMs,
      text: text,
      words: words,
      id: id,
      voices: voices,
      speaker: speaker,
      speakerGroup: speakerGroup);

  /// The same line said by [speaker] (of [group]).
  Phrase withSpeaker(String? speaker, int? group) => Phrase(
      startMs: startMs,
      endMs: endMs,
      text: text,
      words: words,
      id: id,
      voices: voices,
      speaker: speaker,
      speakerGroup: group);

  @override
  bool operator ==(Object other) =>
      other is Phrase &&
      other.id == id &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      other.text == text &&
      listEquals(other.words, words) &&
      other.speaker == speaker &&
      other.speakerGroup == speakerGroup;

  @override
  int get hashCode => Object.hash(id, startMs, endMs, text, Object.hashAll(words), speaker, speakerGroup);

  @override
  String toString() => 'Phrase($startMs–$endMs${speaker == null ? '' : ' $speaker'}: $text)';
}
