# Compatibility contract

MoonEditorConfig v0.1 targets EditorConfig specification 0.17.2.

## Planned v0.1 surface

- UTF-8 input, optional UTF-8 BOM, LF and CRLF line endings.
- Blank lines, full-line `#` and `;` comments, preamble pairs, sections, and
  first-`=` key/value separation with no inline comments.
- Ordered pairs and sections, recoverable diagnostics, and source spans.
- `*`, `**`, `?`, character classes, negated classes, escapes, alternatives,
  and ascending signed integer ranges.
- Directory discovery, `root = true`, later-rule precedence, closer-file
  precedence, and `unset`.
- All standard 0.17.2 properties plus preservation of unknown properties.

## Resource limits

The implementation must accept specification-required keys through 1024 code
units, values through 4096 code units, and globs through 1024 code units. v0.1
will define higher hard limits and explicit budgets for nesting, alternatives,
range cardinality, and matcher operations. Inputs beyond those limits produce
diagnostics rather than unbounded work.

## Explicit non-goals

- Rewriting or formatting target files.
- An IDE plugin or language server.
- Claiming byte-for-byte ec4j compatibility where ec4j differs from 0.17.2.
- Following symbolic links or promising platform-independent filesystem case
  folding in v0.1.
