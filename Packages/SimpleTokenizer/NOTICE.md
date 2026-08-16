# SimpleTokenizer attribution

This target contains the no-pinyin tokenizer core adapted from
[`simple` v0.7.1](https://github.com/wangfenjin/simple/tree/v0.7.1), commit
`4ed008934495fc55ff4bf6620bba58311988b23e`, by Wang Fenjin.

iEvelyn's adaptation, dated 2026-08-16, removes the loadable-extension entry
point, pinyin dictionary, pinyin functions, custom query helpers, and custom
highlight helpers. It keeps the upstream UTF-8 token boundaries and ASCII
case-folding behavior, registers only the `simple` FTS5 tokenizer against the
SQLite connection supplied by GRDB, and rejects every configuration except
the explicit no-pinyin argument `0`.

The selected license is MIT; see `LICENSE`.
