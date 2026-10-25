# Reproducible examples

These fixtures exercise MoonEditorConfig against real files on disk. They are
small enough to copy into a temporary directory in CI, so configuration
discovery never depends on the repository checkout path.

## Basic inheritance root

`basic/.editorconfig` is a search root. Resolving `basic/src/main.mbt` must
produce `indent_style=space`, `indent_size=2`, and the unknown property
`custom_key=value`. Keeping the custom key demonstrates that the engine does
not reject extensions to the standard property set.

```sh
moon run --target native cmd/moonecfg -- resolve examples/basic/src/main.mbt --json
```

`basic/invalid.editorconfig` deliberately has an unterminated section header.
Strict validation must emit a located diagnostic and exit with status 3.

```sh
moon run --target native cmd/moonecfg -- validate examples/basic/invalid.editorconfig --strict --json
```

## Nested override and unset

The root configuration under `nested/` supplies `indent_size=2` and
`end_of_line=lf`. The closer configuration under `nested/src/` overrides the
indent size with 4 and unsets `end_of_line`. Resolving
`nested/src/deep/main.mbt` must therefore contain `indent_size=4`, omit
`end_of_line` from the effective settings, and retain the unset operation in
the explanation trace.

```sh
moon run --target native cmd/moonecfg -- explain examples/nested/src/deep/main.mbt --json
```

## Windows lexical paths

`windows-paths/cases.tsv` records drive-letter, backslash, and case-sensitivity
expectations without assuming that CI itself runs on Windows. The files under
`windows-paths/project/` are the equivalent disk tree used by manual Windows
tests. Path normalization is lexical; v0.1 does not resolve junctions or
symbolic links.

On a Windows runner, the fixture can be copied to a real temporary path before
querying it:

```powershell
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("moonecfg-" + [guid]::NewGuid())
Copy-Item -Recurse -Force examples/windows-paths/project $fixture
moon run --target native cmd/moonecfg -- resolve "$fixture\src\deep\main.mbt" --json
Write-Host "Temporary fixture: $fixture"
```

## Glob cases

`glob-cases.tsv` is a compact, data-oriented record of the required brace,
range, and directory-depth examples. It complements the richer MoonBit unit
tests and is not counted as production code or as an upstream test-suite run.
