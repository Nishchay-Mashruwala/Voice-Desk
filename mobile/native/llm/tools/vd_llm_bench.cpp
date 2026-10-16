// Times the task AI on a phone: loads a model, counts a prompt's tokens and
// generates an answer, printing each step's time. Run through adb shell:
//   vd_llm_bench <model.gguf> <prompt.txt> <grammar.gbnf|-> [max_tokens] [threads]
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>

#include "../vd_llm.h"

static std::string read(const char* path) {
  std::ifstream in(path, std::ios::binary);
  std::stringstream s;
  s << in.rdbuf();
  return s.str();
}

static double since(std::chrono::steady_clock::time_point t) {
  return std::chrono::duration<double>(std::chrono::steady_clock::now() - t).count();
}

int main(int argc, char** argv) {
  if (argc < 4) {
    fprintf(stderr, "usage: vd_llm_bench model prompt grammar|- [max_tokens] [threads]\n");
    return 2;
  }
  const int max_tokens = argc > 4 ? atoi(argv[4]) : 300;
  const int threads = argc > 5 ? atoi(argv[5]) : 4;
  const std::string prompt = read(argv[2]);
  const std::string grammar = std::string(argv[3]) == "-" ? "" : read(argv[3]);

  auto t = std::chrono::steady_clock::now();
  void* h = vd_llm_load(argv[1], 8192, threads);
  if (!h) {
    fprintf(stderr, "load failed\n");
    return 1;
  }
  printf("load %.1f s\n", since(t));
  t = std::chrono::steady_clock::now();
  const int n = vd_llm_count_tokens(h, prompt.c_str());
  printf("prompt %d tokens (counted in %.2f s)\n", n, since(t));
  t = std::chrono::steady_clock::now();
  char* out = vd_llm_generate(h, prompt.c_str(), grammar.c_str(), max_tokens, 0.1f, 1);
  const double took = since(t);
  if (!out) {
    fprintf(stderr, "generate failed: %s\n", vd_llm_last_error(h));
    return 1;
  }
  const int m = vd_llm_count_tokens(h, out);
  printf("generate %.1f s, about %d tokens out\n---\n%s\n---\n", took, m, out);
  vd_llm_free_string(out);
  vd_llm_close(h);
  return 0;
}
