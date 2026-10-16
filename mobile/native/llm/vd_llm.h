// The task AI's C interface: llama.cpp behind six plain functions, called from
// Dart through FFI. One handle is one loaded model with one context; it is used
// by one thread at a time, except vd_llm_stop, which any thread may call.
#pragma once

#ifdef _WIN32
#define VD_LLM_API __declspec(dllexport)
#else
#define VD_LLM_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Loads the GGUF at model_path. Null on failure.
VD_LLM_API void* vd_llm_load(const char* model_path, int n_ctx, int n_threads);

// How many tokens text is, with the model's own tokenizer. -1 on failure.
VD_LLM_API int vd_llm_count_tokens(void* h, const char* text);

// Runs prompt (special tokens allowed) and returns the answer, constrained by
// the GBNF grammar (root "root"; empty for none), as malloc'd UTF-8 for
// vd_llm_free_string. Null on failure or when stopped; vd_llm_last_error says
// which.
VD_LLM_API char* vd_llm_generate(void* h, const char* prompt, const char* grammar, int max_tokens,
                                 float temperature, unsigned int seed);

// Why the last vd_llm_generate gave null: "stopped", "too_long", "grammar",
// "decode", or "" when it didn't.
VD_LLM_API const char* vd_llm_last_error(void* h);

// Makes a running vd_llm_generate give up soon (between tokens). Safe from any
// thread; cleared when the next vd_llm_generate starts.
VD_LLM_API void vd_llm_stop(void* h);

VD_LLM_API void vd_llm_free_string(char* s);

VD_LLM_API void vd_llm_close(void* h);

#ifdef __cplusplus
}
#endif
