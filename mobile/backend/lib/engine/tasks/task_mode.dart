import '../../data/transcript.dart';
import '../speakers/grouping.dart' show kMeLabel;

/// Which prompt a recording gets: a meeting's (the owner's action items) or a
/// to-do list's (everything the owner noted for himself).
enum TaskMode { meeting, todo }

/// A to-do list when every line with a speaker is the owner's, or when the
/// recording has one voice and no voice is trained (the owner recording
/// alone). A meeting otherwise, recordings made without speaker detection too.
TaskMode taskMode(List<Phrase> lines, {required bool voiceTrained}) {
  final speakers = {for (final l in lines) l.speaker};
  if (speakers.contains(null) || speakers.isEmpty) return TaskMode.meeting;
  if (speakers.every((s) => s == kMeLabel)) return TaskMode.todo;
  return speakers.length == 1 && !voiceTrained ? TaskMode.todo : TaskMode.meeting;
}

/// Whether a line says it is the owner's ("Me"). Without one, only tasks said
/// to him are found (and the recording's screen says to train his voice).
bool hasMe(List<Phrase> lines) => lines.any((l) => l.speaker == kMeLabel);
