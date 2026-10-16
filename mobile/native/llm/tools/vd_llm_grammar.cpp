// Prints the GBNF grammar llama.cpp makes from a JSON schema (the file given),
// as llama-server does for a request's response_format. Used once, by hand, to
// make the grammar in mobile/backend/lib/engine/tasks/task_grammar.dart.
#include <fstream>
#include <iostream>
#include <sstream>

#include "json-schema-to-grammar.h"

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: vd_llm_grammar schema.json\n";
    return 2;
  }
  std::ifstream in(argv[1]);
  std::stringstream text;
  text << in.rdbuf();
  std::cout << json_schema_to_grammar(common_json::parse(text.str()));
  return 0;
}
