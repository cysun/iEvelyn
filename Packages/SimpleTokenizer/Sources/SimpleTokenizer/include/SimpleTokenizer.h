#ifndef IEVELYN_SIMPLE_TOKENIZER_H
#define IEVELYN_SIMPLE_TOKENIZER_H

#include <sqlite3.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Registers the no-pinyin `simple` FTS5 tokenizer on one SQLite connection.
/// Returns a SQLite result code.
int ievelyn_register_simple_tokenizer(sqlite3 *database);

#ifdef __cplusplus
}
#endif

#endif
