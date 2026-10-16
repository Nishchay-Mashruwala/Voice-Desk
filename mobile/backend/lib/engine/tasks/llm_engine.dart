import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// The task AI: a language model that counts tokens and writes answers.
abstract class LlmEngine {
  /// How many tokens [text] is, with the model's own tokenizer.
  Future<int> countTokens(String text);

  /// The model's answer to [prompt] (a whole chat prompt), following the GBNF
  /// [grammar] (empty for none). Throws [LlmFailed].
  Future<String> generate({
    required String prompt,
    required String grammar,
    int maxTokens = 1536,
    double temperature = 0.1,
    int seed = 1,
  });

  /// Makes the answer being written give up soon ([LlmFailed] `stopped`).
  /// Does nothing when none is.
  void stop();

  /// Unloads the model.
  Future<void> close();
}

/// Why the task AI couldn't answer: `load`, `stopped`, `too_long`, `grammar`,
/// `decode`, or `gone` (its isolate ended).
class LlmFailed implements Exception {
  const LlmFailed(this.reason);
  final String reason;

  @override
  String toString() => 'LlmFailed($reason)';
}

/// llama.cpp through the `vd_llm` library (`mobile/native/llm`), in an isolate
/// of its own: an answer takes minutes on a phone.
class LlamaEngine implements LlmEngine {
  LlamaEngine._(this._isolate, this._toIsolate, this._replies, this._handle, this._lib);

  final Isolate _isolate;
  final SendPort _toIsolate;
  final StreamIterator<Object?> _replies;
  final int _handle;
  final _VdLlm _lib;
  Future<void> _last = Future.value();
  bool _closed = false;

  /// [libraryPath]: `vd_llm.dll` on a PC (tests); null on the phone (the app's
  /// own `libvd_llm.so`).
  static Future<LlamaEngine> start(File model, {int threads = 4, int contextSize = 8192, String? libraryPath}) async {
    final fromIsolate = ReceivePort();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _run,
        _Start(fromIsolate.sendPort, model.path, threads, contextSize, libraryPath),
        errorsAreFatal: true,
        onError: fromIsolate.sendPort,
        onExit: fromIsolate.sendPort,
      );
    } on Object {
      fromIsolate.close();
      throw const LlmFailed('load');
    }
    final replies = StreamIterator<Object?>(fromIsolate);
    final first = await replies.moveNext() ? replies.current : null;
    if (first case [final SendPort port, final int handle]) {
      return LlamaEngine._(isolate, port, replies, handle, _VdLlm.open(libraryPath));
    }
    await replies.cancel();
    isolate.kill();
    throw const LlmFailed('load');
  }

  /// One request at a time; replies come back in order.
  Future<Object?> _ask(Object message) {
    if (_closed) return Future.error(const LlmFailed('gone'));
    final reply = _last.then((_) async {
      _toIsolate.send(message);
      final r = await _replies.moveNext() ? _replies.current : null;
      if (r is LlmFailed) throw r;
      if (r is int || r is String) return r;
      // Its isolate ended (a crash): nothing more will come from it.
      _closed = true;
      throw const LlmFailed('gone');
    });
    _last = reply.then((_) {}, onError: (_) {});
    return reply;
  }

  @override
  Future<int> countTokens(String text) async {
    final n = await _ask(('count', text)) as int;
    if (n < 0) throw const LlmFailed('decode');
    return n;
  }

  @override
  Future<String> generate({
    required String prompt,
    required String grammar,
    int maxTokens = 1536,
    double temperature = 0.1,
    int seed = 1,
  }) async =>
      await _ask(('generate', prompt, grammar, maxTokens, temperature, seed)) as String;

  @override
  void stop() {
    // From this isolate: the engine's is busy writing the answer.
    if (!_closed) _lib.stop(Pointer.fromAddress(_handle));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await _last;
    _closed = true;
    _toIsolate.send('close');
    // The model lives in native memory: the isolate frees it and says so before
    // it ends (as SherpaSpeech.close).
    try {
      await _replies.moveNext().timeout(const Duration(seconds: 30));
    } on Object {
      // Gone already, or stuck: end it anyway.
    }
    await _replies.cancel();
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _returnFreedMemory();
  }
}

/// The answer's text. One cut off at its length can end in the middle of a
/// character (Gujarati, Hindi): that is kept as it is, for the JSON check to
/// judge, not an error that ends the engine.
String answerText(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

/// As SherpaSpeech's: hands the freed memory back to the phone (bionic's
/// `mallopt`; Android only).
void _returnFreedMemory() {
  if (!Platform.isAndroid) return;
  try {
    final mallopt = DynamicLibrary.process().lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('mallopt');
    mallopt(-101, 0); // M_PURGE
    mallopt(-104, 0); // M_PURGE_ALL (Android 13+; ignored before)
  } on Object {
    // Not available: the memory is still reused by the next job.
  }
}

class _Start {
  const _Start(this.replyTo, this.model, this.threads, this.contextSize, this.libraryPath);
  final SendPort replyTo;
  final String model;
  final int threads, contextSize;
  final String? libraryPath;
}

/// The library's functions (`mobile/native/llm/vd_llm.h`).
class _VdLlm {
  _VdLlm(DynamicLibrary lib)
      : load = lib.lookupFunction<Pointer<Void> Function(Pointer<Utf8>, Int32, Int32), Pointer<Void> Function(Pointer<Utf8>, int, int)>('vd_llm_load'),
        countTokens = lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>), int Function(Pointer<Void>, Pointer<Utf8>)>('vd_llm_count_tokens'),
        generate = lib.lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Int32, Float, Uint32),
            Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, int, double, int)>('vd_llm_generate'),
        lastError = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>), Pointer<Utf8> Function(Pointer<Void>)>('vd_llm_last_error'),
        stop = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('vd_llm_stop', isLeaf: true),
        freeString = lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('vd_llm_free_string'),
        close = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('vd_llm_close');

  factory _VdLlm.open(String? libraryPath) => _VdLlm(DynamicLibrary.open(libraryPath ?? 'libvd_llm.so'));

  final Pointer<Void> Function(Pointer<Utf8>, int, int) load;
  final int Function(Pointer<Void>, Pointer<Utf8>) countTokens;
  final Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, int, double, int) generate;
  final Pointer<Utf8> Function(Pointer<Void>) lastError;
  final void Function(Pointer<Void>) stop;
  final void Function(Pointer<Utf8>) freeString;
  final void Function(Pointer<Void>) close;
}

void _run(_Start s) {
  final lib = _VdLlm.open(s.libraryPath);
  final path = s.model.toNativeUtf8();
  final h = lib.load(path, s.contextSize, s.threads);
  malloc.free(path);
  if (h == nullptr) {
    s.replyTo.send(const LlmFailed('load'));
    return;
  }
  final inbox = ReceivePort();
  s.replyTo.send([inbox.sendPort, h.address]);
  inbox.listen((message) {
    // Whatever goes wrong with one request is its answer, never the end of the
    // isolate (a request waiting for it would wait for ever).
    try {
      _answer(lib, h, s.replyTo, message, inbox);
    } on Object {
      s.replyTo.send(const LlmFailed('decode'));
    }
  });
}

/// Answers one request from [LlamaEngine].
void _answer(_VdLlm lib, Pointer<Void> h, SendPort replyTo, Object? message, ReceivePort inbox) {
  switch (message) {
    case ('count', final String text):
      final t = text.toNativeUtf8();
      replyTo.send(lib.countTokens(h, t));
      malloc.free(t);
    case ('generate', final String prompt, final String grammar, final int maxTokens, final double temperature, final int seed):
      final p = prompt.toNativeUtf8(), g = grammar.toNativeUtf8();
      final out = lib.generate(h, p, g, maxTokens, temperature, seed);
      malloc.free(p);
      malloc.free(g);
      if (out == nullptr) {
        replyTo.send(LlmFailed(lib.lastError(h).toDartString()));
        return;
      }
      final bytes = out.cast<Uint8>();
      var n = 0;
      while (bytes[n] != 0) {
        n++;
      }
      final text = answerText(Uint8List.fromList(bytes.asTypedList(n)));
      lib.freeString(out);
      replyTo.send(text);
    case 'close':
      lib.close(h);
      inbox.close();
      replyTo.send('closed');
  }
}
