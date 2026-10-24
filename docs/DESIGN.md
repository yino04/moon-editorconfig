# Design overview

The project separates pure, target-independent logic from host I/O.

1. `model` stores ordered documents, source locations, diagnostics, and
   resolution traces.
2. `lexer` performs bounded line scanning without interpreting inline comment
   markers.
3. `parser` builds the document and preserves invalid-but-recoverable input as
   diagnostics.
4. `glob` compiles patterns to explicit tokens/AST and evaluates them with a
   bounded dynamic-programming matcher.
5. `properties` validates known values while retaining unknown pairs.
6. `path` normalizes lexical paths independently of the host filesystem.
7. `resolver` consumes an injectable configuration source and applies ordered
   precedence and `unset` semantics.
8. `report` creates stable JSON and human diagnostics.
9. `io` is the narrow host adapter used by the executable CLI.

Public core APIs accept strings and ordinary value types. Filesystem handles do
not escape the host adapter, making deterministic in-memory tests possible.
