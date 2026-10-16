// See vd_llm.h. Sampling is the desktop's llama-server's with the request it
// sends (temperature 0.1, the other settings left at the server's defaults):
// top-k 40, top-p 0.95, min-p 0.05, then the temperature, with the grammar
// checked the server's way: the token the chain picks is kept if the grammar
// allows it, else the grammar is applied to every token and the chain run again.
#include "vd_llm.h"

#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "llama.h"

namespace {

struct Handle {
  llama_model* model = nullptr;
  llama_context* ctx = nullptr;
  const llama_vocab* vocab = nullptr;
  std::atomic<bool> stop{false};
  const char* error = "";
};

void quiet_log(ggml_log_level level, const char* text, void*) {
  if (level >= GGML_LOG_LEVEL_WARN) fputs(text, stderr);
}

std::once_flag backend_once;

std::vector<llama_token> tokenize(const llama_vocab* vocab, const char* text, bool special) {
  const int len = (int)strlen(text);
  const int n = -llama_tokenize(vocab, text, len, nullptr, 0, special, special);
  std::vector<llama_token> tokens(n > 0 ? n : 0);
  if (n > 0 && llama_tokenize(vocab, text, len, tokens.data(), n, special, special) != n) tokens.clear();
  return tokens;
}

// Every token with its logit, for the samplers.
void candidates(llama_context* ctx, int n_vocab, std::vector<llama_token_data>& cur) {
  const float* logits = llama_get_logits_ith(ctx, -1);
  cur.resize(n_vocab);
  for (int i = 0; i < n_vocab; i++) cur[i] = llama_token_data{i, logits[i], 0.0f};
}

llama_token sample(Handle* h, llama_sampler* chain, llama_sampler* grammar, std::vector<llama_token_data>& cur) {
  const int n_vocab = llama_vocab_n_tokens(h->vocab);
  candidates(h->ctx, n_vocab, cur);
  llama_token_data_array all{cur.data(), cur.size(), -1, false};
  llama_sampler_apply(chain, &all);
  llama_token id = all.data[all.selected].id;
  if (grammar) {
    llama_token_data one{id, 1.0f, 0.0f};
    llama_token_data_array single{&one, 1, -1, false};
    llama_sampler_apply(grammar, &single);
    if (std::isinf(single.data[0].logit)) {
      candidates(h->ctx, n_vocab, cur);
      llama_token_data_array again{cur.data(), cur.size(), -1, false};
      llama_sampler_apply(grammar, &again);
      llama_sampler_apply(chain, &again);
      id = again.data[again.selected].id;
    }
    llama_sampler_accept(grammar, id);
  }
  llama_sampler_accept(chain, id);
  return id;
}

char* copy(const std::string& s) {
  char* out = (char*)malloc(s.size() + 1);
  if (out) memcpy(out, s.c_str(), s.size() + 1);
  return out;
}

}  // namespace

extern "C" {

void* vd_llm_load(const char* model_path, int n_ctx, int n_threads) {
  std::call_once(backend_once, [] {
    llama_log_set(quiet_log, nullptr);
    llama_backend_init();
  });
  llama_model_params mp = llama_model_default_params();
  mp.n_gpu_layers = 0;
  llama_model* model = llama_model_load_from_file(model_path, mp);
  if (!model) return nullptr;
  llama_context_params cp = llama_context_default_params();
  cp.n_ctx = n_ctx;
  cp.n_batch = 512;
  cp.n_ubatch = 512;
  cp.n_threads = n_threads;
  cp.n_threads_batch = n_threads;
  // As the desktop runs llama-server: flash attention on, the KV cache in q8_0.
  cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
  cp.type_k = GGML_TYPE_Q8_0;
  cp.type_v = GGML_TYPE_Q8_0;
  cp.no_perf = true;
  llama_context* ctx = llama_init_from_model(model, cp);
  if (!ctx) {
    llama_model_free(model);
    return nullptr;
  }
  Handle* h = new Handle();
  h->model = model;
  h->ctx = ctx;
  h->vocab = llama_model_get_vocab(model);
  return h;
}

int vd_llm_count_tokens(void* p, const char* text) {
  if (!p || !text) return -1;
  if (!*text) return 0;
  const auto tokens = tokenize(((Handle*)p)->vocab, text, false);
  return tokens.empty() ? -1 : (int)tokens.size();
}

char* vd_llm_generate(void* p, const char* prompt, const char* grammar_text, int max_tokens, float temperature,
                      unsigned int seed) {
  if (!p) return nullptr;
  Handle* h = (Handle*)p;
  h->stop = false;
  h->error = "";
  llama_memory_clear(llama_get_memory(h->ctx), true);

  std::vector<llama_token> tokens = tokenize(h->vocab, prompt, true);
  if (tokens.empty() || (int)tokens.size() + max_tokens > (int)llama_n_ctx(h->ctx)) {
    h->error = "too_long";
    return nullptr;
  }

  llama_sampler* grammar = nullptr;
  if (grammar_text && *grammar_text) {
    grammar = llama_sampler_init_grammar(h->vocab, grammar_text, "root");
    if (!grammar) {
      h->error = "grammar";
      return nullptr;
    }
  }
  llama_sampler* chain = llama_sampler_chain_init(llama_sampler_chain_default_params());
  llama_sampler_chain_add(chain, llama_sampler_init_top_k(40));
  llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.95f, 1));
  llama_sampler_chain_add(chain, llama_sampler_init_min_p(0.05f, 1));
  llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature));
  llama_sampler_chain_add(chain, llama_sampler_init_dist(seed));

  std::string out;
  bool ok = true;
  const int n_batch = (int)llama_n_batch(h->ctx);
  for (size_t i = 0; ok && i < tokens.size(); i += n_batch) {
    if (h->stop) {
      h->error = "stopped";
      ok = false;
      break;
    }
    const int n = (int)std::min(tokens.size() - i, (size_t)n_batch);
    if (llama_decode(h->ctx, llama_batch_get_one(tokens.data() + i, n)) != 0) {
      h->error = "decode";
      ok = false;
    }
  }
  std::vector<llama_token_data> cur;
  for (int i = 0; ok && i < max_tokens; i++) {
    if (h->stop) {
      h->error = "stopped";
      ok = false;
      break;
    }
    llama_token id = sample(h, chain, grammar, cur);
    if (llama_vocab_is_eog(h->vocab, id)) break;
    char piece[256];
    const int n = llama_token_to_piece(h->vocab, id, piece, sizeof piece, 0, false);
    if (n > 0) out.append(piece, n);
    if (llama_decode(h->ctx, llama_batch_get_one(&id, 1)) != 0) {
      h->error = "decode";
      ok = false;
    }
  }
  llama_sampler_free(chain);
  if (grammar) llama_sampler_free(grammar);
  return ok ? copy(out) : nullptr;
}

const char* vd_llm_last_error(void* p) { return p ? ((Handle*)p)->error : "decode"; }

void vd_llm_stop(void* p) {
  if (p) ((Handle*)p)->stop = true;
}

void vd_llm_free_string(char* s) { free(s); }

void vd_llm_close(void* p) {
  if (!p) return;
  Handle* h = (Handle*)p;
  llama_free(h->ctx);
  llama_model_free(h->model);
  delete h;
}

}  // extern "C"
