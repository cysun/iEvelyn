#include "SimpleTokenizer.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <new>
#include <string>

namespace {

enum class TokenCategory {
  space,
  asciiAlphabetic,
  digit,
  other,
};

struct SimpleTokenizer {};

TokenCategory category(char character) {
  const auto byte = static_cast<unsigned char>(character);
  if (byte > 127) {
    return TokenCategory::other;
  }
  if (std::isdigit(byte)) {
    return TokenCategory::digit;
  }
  if (std::isspace(byte) || std::iscntrl(byte)) {
    return TokenCategory::space;
  }
  if (std::isalpha(byte)) {
    return TokenCategory::asciiAlphabetic;
  }
  return TokenCategory::other;
}

int utf8Length(unsigned char firstByte) {
  if (firstByte >= 0xF0) {
    return 4;
  }
  if (firstByte >= 0xE0) {
    return 3;
  }
  if (firstByte >= 0xC0) {
    return 2;
  }
  return 1;
}

int createTokenizer(
    void *,
    const char **arguments,
    int argumentCount,
    Fts5Tokenizer **output) {
  if (argumentCount != 1 || std::strcmp(arguments[0], "0") != 0) {
    return SQLITE_MISUSE;
  }

  auto *tokenizer = new (std::nothrow) SimpleTokenizer();
  if (tokenizer == nullptr) {
    return SQLITE_NOMEM;
  }
  *output = reinterpret_cast<Fts5Tokenizer *>(tokenizer);
  return SQLITE_OK;
}

void deleteTokenizer(Fts5Tokenizer *tokenizer) {
  delete reinterpret_cast<SimpleTokenizer *>(tokenizer);
}

int tokenize(
    Fts5Tokenizer *,
    void *context,
    int,
    const char *text,
    int textLength,
    int (*emitToken)(void *, int, const char *, int, int, int)) {
  int start = 0;
  int index = 0;
  std::string token;

  while (index < textLength) {
    const TokenCategory tokenCategory = category(text[index]);
    switch (tokenCategory) {
      case TokenCategory::other:
        index = std::min(
            textLength,
            index + utf8Length(static_cast<unsigned char>(text[index])));
        break;
      default:
        while (++index < textLength && category(text[index]) == tokenCategory) {
        }
        break;
    }

    if (tokenCategory != TokenCategory::space) {
      token.assign(text + start, text + index);
      if (tokenCategory == TokenCategory::asciiAlphabetic) {
        std::transform(
            token.begin(),
            token.end(),
            token.begin(),
            [](unsigned char character) { return std::tolower(character); });
      }

      const int result = emitToken(
          context,
          0,
          token.c_str(),
          static_cast<int>(token.length()),
          start,
          index);
      if (result != SQLITE_OK) {
        return result;
      }
    }
    start = index;
  }

  return SQLITE_OK;
}

int fts5API(sqlite3 *database, fts5_api **api) {
  sqlite3_stmt *statement = nullptr;
  *api = nullptr;
  int result = sqlite3_prepare_v2(
      database,
      "SELECT fts5(?1)",
      -1,
      &statement,
      nullptr);
  if (result == SQLITE_OK) {
    result = sqlite3_bind_pointer(statement, 1, api, "fts5_api_ptr", nullptr);
  }
  if (result == SQLITE_OK) {
    (void)sqlite3_step(statement);
  }
  const int finalizeResult = sqlite3_finalize(statement);
  return result == SQLITE_OK ? finalizeResult : result;
}

}  // namespace

int ievelyn_register_simple_tokenizer(sqlite3 *database) {
  fts5_api *api = nullptr;
  int result = fts5API(database, &api);
  if (result != SQLITE_OK) {
    return result;
  }
  if (api == nullptr || api->iVersion < 2) {
    return SQLITE_ERROR;
  }

  fts5_tokenizer tokenizer = {
      createTokenizer,
      deleteTokenizer,
      tokenize,
  };
  return api->xCreateTokenizer(api, "simple", nullptr, &tokenizer, nullptr);
}
