# Test report

This file separates reproducible procedures from observations that have
actually been recorded. A command listed in the checklist is not evidence that
it passed. The release audit must replace every `pending` entry with a dated
result and a link or captured log before v0.1.0 is described as released.

## Recorded observations

Recorded locally on 2026-10-25 (Asia/Shanghai):

| Check | Result | Evidence summary |
|---|---|---|
| `moon version --all` | pass | `moon 0.1.20261023`, `moonc v0.10.17+d971670cd`, `moonrun 0.1.20261023` |
| Final whole-module JS check/test | pass | Strict check passed; 237/237 tests passed. |
| Final whole-module wasm-gc check/test | pass | Strict check passed; the same 237/237 portable-core tests passed. |
| Host I/O tests on WASI | pass | 7/7 temporary-disk tests passed. |
| CLI E2E on WASI | pass | Real-disk parse/resolve/explain were byte-stable, 9/9 tabulated glob cases passed, and invalid validation exited 3. |
| Native CLI E2E | pending CI | Windows lacks the required MSVC/Windows SDK; the Ubuntu native workflow must provide the public evidence. |
| 29-case ec4j comparison | pass | 29/29 stored observations reverified: 24 specification agreements, 5 documented ec4j differences, 0 project defects. |
| EditorConfig core-test import | not claimed | No upstream core-test cases are counted; the reference corpus is independently authored and compared against pinned ec4j. |

No GitHub Actions run URL is claimed here yet. A workflow file in the
repository is not proof of a successful run.

## Reproduce the core suite

The CI baseline pins compiler/core release `0.10.17+d971670cd`; its installed
`moon` command reports build `0.1.20261023`. From the repository root, run:

```sh
moon version --all
moon update
moon check --target js --deny-warn
moon test --target js --deny-warn
moon check --target wasm-gc --deny-warn
moon test --target wasm-gc --deny-warn
moon fmt --check
moon info --target all
git diff --exit-code
test -z "$(git status --porcelain --untracked-files=all)"
```

The MoonBit commands are identical in PowerShell. Replace the final shell
cleanliness assertion with:

```powershell
git diff --exit-code
if ($LASTEXITCODE -ne 0) { throw "tracked generated files changed" }
$dirty = git status --porcelain --untracked-files=all
if ($dirty) { throw "uncommitted or untracked generated files remain: $dirty" }
```

In this toolchain, `moon install` installs a binary package globally; it is not
the dependency-restoration command used by older workflow sketches. A fresh CI
runner must use `moon update` to populate its registry index before `moon
check` resolves the pinned `moonbitlang/async` dependency. Do not add `moon
install` to CI as a no-argument substitute for dependency resolution.

To inspect the number of executable MoonBit tests without inflating the count
with files or snapshots, run:

```sh
moon test --target js --outline
moon test --target wasm-gc --outline
```

The acceptance count is based on distinct asserted scenarios. Generated
interfaces, fixtures, documentation, and copied upstream data are not
production lines of code.

## Reproduce the native CLI checks

The following commands read real files from disk. The GitHub workflow first
copies the fixtures to a temporary directory so directory discovery cannot
accidentally rely on the checkout layout.

```sh
moon build --target native --deny-warn cmd/moonecfg
moon run --target native --deny-warn cmd/moonecfg -- parse examples/basic/.editorconfig --json
moon run --target native --deny-warn cmd/moonecfg -- resolve examples/basic/src/main.mbt --json
moon run --target native --deny-warn cmd/moonecfg -- explain examples/nested/src/deep/main.mbt --json
moon run --target native --deny-warn cmd/moonecfg -- validate examples/basic/invalid.editorconfig --strict --json
```

The three query commands must exit 0. CI executes `parse`, `resolve`, and
`explain` twice and byte-compares each pair. Strict validation of the
intentionally malformed file must exit 3, place parse diagnostics in a valid
JSON report on stdout, and avoid debug text in that stream. Human diagnostics
belong on stderr when JSON mode is not requested.

PowerShell preserves the validation status in `$LASTEXITCODE`:

```powershell
moon run --target native --deny-warn cmd/moonecfg -- validate examples/basic/invalid.editorconfig --strict --json
if ($LASTEXITCODE -ne 3) { throw "expected exit code 3, got $LASTEXITCODE" }
```

## Required end-to-end coverage

The committed fixtures and the test suite together must demonstrate:

1. `examples/basic/src/main.mbt` resolves the root `indent_size=2`.
2. The closer `examples/nested/src/.editorconfig` changes that value to 4 and
   is identified as the source by `explain`.
3. The child `end_of_line=unset` removes the inherited `lf` value while its
   trace remains observable.
4. Brace alternatives and integer ranges match only the allowed values in
   `examples/glob-cases.tsv`.
5. `src/*.mbt` rejects a deeper path while `src/**/*.mbt` accepts the recorded
   deep case.
6. `custom_key=value` survives resolution.
7. Invalid syntax produces a nonempty diagnostic with line and column data and
   a nonzero process status.
8. Adversarial nested glob input terminates within the documented compile and
   operation budgets and reports the exhausted budget.
9. Host I/O tests use a temporary disk tree rather than only the in-memory
   resolver.
10. Repeated `parse`, `resolve`, and `explain` JSON invocations are byte-stable
    for identical input.

## Reference comparison record

The repository includes 29 recorded comparison rows. Each
row needs an input identifier, the pinned ec4j output, MoonEditorConfig output,
the difference category (`same`, `spec-divergence`, `bug`, or
`unsupported`), and its resolution. The committed inputs and raw observations
live under `tests/reference/`; the analysis is in
`docs/REFERENCE_COMPARISON.md`. A fresh `--check` run on 2026-10-25 verified
all 29 rows.

## Release audit fields

Fill these only from actual command output:

- Tested commit: final CI commit `pending`; local code baseline `21dbb30`
- Distinct executable MoonBit test blocks: 237 portable-core plus 7 host-I/O
  blocks (the same core tests on two backends are not double-counted)
- Effective production MoonBit lines: 4,212 (nonempty, non-comment
  approximation from `scripts/count_effective_loc.py`, followed by a
  module-by-module review; tests and generated interfaces excluded)
- JS result: 237/237 pass with `--deny-warn`
- wasm-gc result: 237/237 pass with `--deny-warn`
- Host-I/O WASI result: 7/7 pass with `--deny-warn`
- Local CLI result: pass on WASI; native result pending public Ubuntu CI
- Reference comparisons: 29/29 reverified (24 same, 5 documented differences,
  0 project defects)
- GitHub Actions run: `pending`
- Known failing cases: none in the recorded MoonBit suites
- Known exclusions: EditorConfig core-test is not imported or counted; the
  pinned ec4j Maven build reports one upstream skipped test; native compilation
  is delegated to Ubuntu CI because this Windows host has no MSVC toolchain
