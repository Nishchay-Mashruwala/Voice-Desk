import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/tasks/task_answer.dart';

void main() {
  test('the answer parses, and a broken one throws', () {
    final a = TaskAnswer.parse('{"summary": "A sync.", "tasks": ['
        '{"description": "Send the report", "assigned_by": "Person 1", "due": "by Friday", "quote": "send the report"},'
        '{"description": "  ", "assigned_by": null, "due": null, "quote": null}]}');
    expect(a.summary, 'A sync.');
    expect(a.tasks, [const FoundTask(description: 'Send the report', assignedBy: 'Person 1', due: 'by Friday', quote: 'send the report')],
        reason: 'an empty description is dropped');
    expect(() => TaskAnswer.parse('{"summary": "cut off'), throwsFormatException);
    expect(() => TaskAnswer.parse('{"tasks": []}'), throwsFormatException);
    expect(() => TaskAnswer.parse('[]'), throwsFormatException);
  });

  test('a task goes to JSON and back', () {
    const t = FoundTask(description: 'Call the bank', assignedBy: 'Self', quote: 'call the bank');
    expect(FoundTask.fromJson(t.toJson()), t);
    expect(t.toJson(), {'description': 'Call the bank', 'assigned_by': 'Self', 'due': null, 'quote': 'call the bank'});
  });

  test('a garbled label is snapped back', () {
    final snapped = snapLabels([
      const FoundTask(description: 'a', assignedBy: 'Speaker :1'),
      const FoundTask(description: 'b', assignedBy: 'person 1'),
      const FoundTask(description: 'c', assignedBy: 'me'),
      const FoundTask(description: 'd', assignedBy: 'SELF'),
      const FoundTask(description: 'e', assignedBy: 'Priya'),
      const FoundTask(description: 'f'),
    ], {'Person 1', 'Speaker 1', 'Me'});
    expect([for (final t in snapped) t.assignedBy], ['Speaker 1', 'Person 1', 'Self', 'Self', 'Priya', null]);
  });
}
