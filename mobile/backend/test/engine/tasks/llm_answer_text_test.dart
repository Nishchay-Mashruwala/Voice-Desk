import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/tasks/llm_engine.dart';

void main() {
  test('an answer cut off in the middle of a character is still read', () {
    final whole = utf8.encode('{"summary": "ગુજરાતી');
    final cut = Uint8List.fromList(whole.sublist(0, whole.length - 1));
    expect(() => answerText(cut), returnsNormally);
    expect(answerText(cut), startsWith('{"summary": "ગુજરા'));
    expect(answerText(Uint8List.fromList(utf8.encode('ok'))), 'ok');
  });
}
