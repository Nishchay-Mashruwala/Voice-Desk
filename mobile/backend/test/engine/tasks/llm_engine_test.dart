import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/tasks/llm_engine.dart';
import 'package:mobile_backend/engine/tasks/task_grammar.dart';

/// Runs the real task model on the PC. Needs:
/// - VOICEDESK_LLM_MODEL: Qwen3-1.7B-Q4_K_M.gguf (the catalogue's file);
/// - VOICEDESK_LLM_LIB: vd_llm.dll (mobile/native/llm/build_windows.ps1).
void main() {
  final model = Platform.environment['VOICEDESK_LLM_MODEL'];
  final lib = Platform.environment['VOICEDESK_LLM_LIB'];
  final skip = model == null || lib == null ? 'set VOICEDESK_LLM_MODEL and VOICEDESK_LLM_LIB' : false;

  Future<LlamaEngine> start() => LlamaEngine.start(File(model!), libraryPath: lib, contextSize: 4096);

  const prompt = '<|im_start|>system\nYou extract action items. Output only the requested JSON.<|im_end|>\n'
      '<|im_start|>user\nTranscript:\n"""\n[00:00] Priya: Nishchay, please send the budget by Friday.\n'
      '[00:05] Me: Sure, I will.\n"""\n\nExtract the user\'s action items and summarize.<|im_end|>\n'
      '<|im_start|>assistant\n<think>\n\n</think>\n\n';

  test("counts tokens with the model's tokenizer", () async {
    final e = await start();
    addTearDown(e.close);
    expect(await e.countTokens('Hello world'), inInclusiveRange(2, 3));
    expect(await e.countTokens(''), 0);
    final english = await e.countTokens('Please send the budget by Friday.');
    final gujarati = await e.countTokens('કૃપા કરીને શુક્રવાર સુધીમાં બજેટ મોકલો.');
    expect(gujarati, greaterThan(english));
  }, skip: skip);

  test('an answer follows the grammar', () async {
    final e = await start();
    addTearDown(e.close);
    final answer = jsonDecode(await e.generate(prompt: prompt, grammar: kTaskGrammar, maxTokens: 400)) as Map;
    expect(answer.keys, containsAll(['summary', 'tasks']));
    expect(answer['tasks'], isA<List>());
  }, skip: skip);

  test('the same seed gives the same answer', () async {
    final e = await start();
    addTearDown(e.close);
    final a = await e.generate(prompt: prompt, grammar: kTaskGrammar, maxTokens: 200, seed: 7);
    final b = await e.generate(prompt: prompt, grammar: kTaskGrammar, maxTokens: 200, seed: 7);
    expect(b, a);
  }, skip: skip);

  test('a prompt longer than the context fails as too long', () async {
    final e = await start();
    addTearDown(e.close);
    await expectLater(
      e.generate(prompt: 'word ' * 5000, grammar: kTaskGrammar),
      throwsA(isA<LlmFailed>().having((f) => f.reason, 'reason', 'too_long')),
    );
  }, skip: skip);

  test('stop gives up the answer being written', () async {
    final e = await start();
    addTearDown(e.close);
    final answer = e.generate(prompt: prompt, grammar: '', maxTokens: 1500);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    e.stop();
    await expectLater(answer, throwsA(isA<LlmFailed>().having((f) => f.reason, 'reason', 'stopped')));
    // Usable again afterwards.
    expect(await e.countTokens('Hello world'), inInclusiveRange(2, 3));
  }, skip: skip);

  test('a missing model fails to start', () async {
    await expectLater(
      LlamaEngine.start(File('${Directory.systemTemp.path}/no-such-model.gguf'), libraryPath: lib),
      throwsA(isA<LlmFailed>().having((f) => f.reason, 'reason', 'load')),
    );
  }, skip: skip);

  test('closing frees it', () async {
    int rss() => ProcessInfo.currentRss;
    final e = await start();
    await e.countTokens('warm up');
    await e.close();
    final before = rss();
    for (var i = 0; i < 3; i++) {
      final again = await start();
      await again.generate(prompt: prompt, grammar: kTaskGrammar, maxTokens: 20);
      await again.close();
    }
    expect(rss() - before, lessThan(300 * 1024 * 1024));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
}
