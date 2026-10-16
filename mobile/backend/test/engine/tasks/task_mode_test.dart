import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/tasks/task_mode.dart';

import 'lines.dart';

void main() {
  test('to-do list when only Me speaks, or one voice without a trained voice; meeting otherwise', () {
    final onlyMe = [line(0, 'Me', 'Buy milk.'), line(4, 'Me', 'Call the bank.')];
    expect(taskMode(onlyMe, voiceTrained: true), TaskMode.todo);
    final oneVoice = [line(0, 'Person 1', 'Buy milk.'), line(4, 'Person 1', 'Call the bank.')];
    expect(taskMode(oneVoice, voiceTrained: false), TaskMode.todo);
    expect(taskMode(oneVoice, voiceTrained: true), TaskMode.meeting, reason: 'not the owner: someone else talking');
    final two = [line(0, 'Person 1', 'Hi.'), line(4, 'Me', 'Hello.')];
    expect(taskMode(two, voiceTrained: true), TaskMode.meeting);
    final noDetection = [line(0, null, 'Buy milk.')];
    expect(taskMode(noDetection, voiceTrained: false), TaskMode.meeting, reason: 'recordings made without speaker detection');
  });

  test('a recording with a Me line has the owner in it', () {
    expect(hasMe([line(0, 'Person 1', 'Hi.'), line(4, 'Me', 'Hello.')]), isTrue);
    expect(hasMe([line(0, 'Person 1', 'Hi.'), line(4, null, 'Hello.')]), isFalse);
  });
}
