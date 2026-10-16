import 'package:flutter_test/flutter_test.dart';

import '../../tool/word_errors.dart';

void main() {
  test('word errors: one substitution and one missing word count 2', () {
    expect(wordErrors('I am fine thank you', 'I am by thank'), 2);
  });

  test('case and punctuation are not errors; Gujarati words count like any', () {
    expect(wordErrors('Good, good, good.', 'good good good'), 0);
    expect(wordErrors('હા એનું background', 'હા એનુ background'), 1);
    expect(wordErrors('', 'hello'), 1);
  });
}
