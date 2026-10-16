/// The task AI's answer, as a GBNF grammar: the desktop's JSON schema
/// (`desktop/backend/core/src/llm.rs` `schema()`), turned into a grammar by
/// llama.cpp b11320's own converter, as llama-server does for a request's
/// `response_format` (made with `mobile/native/llm/tools/vd_llm_grammar.cpp`).
///
/// `{summary: string, tasks: [{description, assigned_by|null, due|null, quote|null}]}`
const kTaskGrammar = r'''
char ::= [^"\\\x7F\x00-\x1F] | [\\] (["\\bfnrt] | "u" [0-9a-fA-F]{4})
null ::= "null"
root ::= "{" space summary-kv "," space tasks-kv space "}"
space ::= | " " | "\n"{1,2} [ \t]{0,20}
string ::= "\"" char* "\""
summary-kv ::= "\"summary\"" space ":" space string
tasks ::= "[" space (tasks-item ("," space tasks-item)*)? space "]"
tasks-item ::= "{" space tasks-item-description-kv "," space tasks-item-assigned-by-kv "," space tasks-item-due-kv "," space tasks-item-quote-kv space "}"
tasks-item-assigned-by ::= string | null
tasks-item-assigned-by-kv ::= "\"assigned_by\"" space ":" space tasks-item-assigned-by
tasks-item-description-kv ::= "\"description\"" space ":" space string
tasks-item-due ::= string | null
tasks-item-due-kv ::= "\"due\"" space ":" space tasks-item-due
tasks-item-quote ::= string | null
tasks-item-quote-kv ::= "\"quote\"" space ":" space tasks-item-quote
tasks-kv ::= "\"tasks\"" space ":" space tasks
''';
