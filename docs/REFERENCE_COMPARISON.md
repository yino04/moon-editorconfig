# ec4j reference comparison

Verified on 2026-10-25. This report records an external behavioral comparison;
EditorConfig 0.17.2 remains the normative source of behavior.

## Reproducibility record

The comparison used ec4j `1.2.0` at the detached Git commit
`4c1a0b00c4dfb8434cfc64d3f5bb8a6ae5b2db5a`. The checkout was built from
source with Microsoft OpenJDK `21.0.12.1` and the repository's Maven wrapper:

```text
mvnw.cmd -pl core -am clean verify
```

The build completed successfully: 68 Java tests ran, with zero failures, zero
errors, and one skipped test. The built artifact was
`core/target/ec4j-core-1.2.0.jar`. Its recorded SHA-256 is
`a018ae7af5ef5135a2aba72c23de7d7a58485d85f04f2f41fc1d75c0de58d945`.
The CLI reported `EditorConfig Java Version 0.12.0-final`.

Each case was created in a fresh temporary directory and queried with the real
ec4j entry point:

```text
java -cp <ec4j-jar> org.ec4j.core.cli.Cli <target>
```

The executable harness, authored cases, captured stdout/stderr, return codes,
and parsed properties are in `tests/reference/`. Running
`python tests/reference/run_reference.py --ec4j-repo <checkout> --check`
repeats all ec4j queries and compares them with the checked-in observations.

## ec4j result summary

The suite contains 29 independently authored inputs. After projecting only
ec4j CLI presentation choices (`unset` markers and derived indentation
defaults), 24 cases agree with the authored EditorConfig 0.17.2 result. Five
cases expose already documented ec4j compatibility differences:

| Case | EditorConfig 0.17.2 expectation | Observed ec4j 1.2.0 behavior |
| --- | --- | --- |
| `escaped-opening-brace` | `\{` matches a literal opening brace | section does not match |
| `inline-semicolon-is-value-text` | inline semicolon text remains part of the value | legacy inline comment is removed |
| `colon-is-not-a-separator` | only `=` separates a property pair | `:` is also accepted |
| `numeric-range-includes-zero` | `{0..2}` includes `0` | a numeric capture beginning with zero is rejected |
| `signed-numeric-range` | `{-2..2}` includes `-1` | the candidate capture accepts unsigned digits only |

Raw ec4j output is never rewritten in the evidence file. A separate
`comparison_properties` field removes only two differences in how the CLIs
present otherwise identical effective settings:

- ec4j's test CLI enables `keepUnset(true)`, while MoonEditorConfig reports
  active properties after `unset` has removed them;
- ec4j materializes `tab_width=indent_size` and `indent_size=tab`, while
  MoonEditorConfig exposes the same defaults through its typed indentation
  semantics API.

## MoonEditorConfig result

All 29 cases were also run through the real filesystem-backed Moon CLI, using
the wasm backend available on the verification host:

```text
moon run cmd/moonecfg --target wasm --deny-warn -- resolve <target> --json
```

The toolchain reported `moon 0.1.20261023`,
`moonc v0.10.17+d971670cd`, and `moonrun 0.1.20261023`; the application
reported `moonecfg 0.1.0`. The full observations are in
`tests/reference/moon-comparison.json`.

The final classification is:

| Classification | Count |
| --- | ---: |
| Specification agreement between MoonEditorConfig and ec4j | 24 |
| MoonEditorConfig follows 0.17.2; documented ec4j difference | 5 |
| MoonEditorConfig project defect | 0 |
| Unclassified reference difference | 0 |

The colon-separator case correctly exits MoonEditorConfig with code 3 and an
`EC2001` invalid-configuration diagnostic while returning an empty effective
property set in machine-clean JSON. The other 28 cases exit with code 0.

The Python program only orchestrates processes, parses their machine output,
and performs equality/classification. No Python fallback stands in for the
Moon parser, glob matcher, resolver, or host adapter. A second run with the
same Moon command and `--check` reproduced all 29 recorded classifications and
captured outputs.

Temporary-directory and repository roots in captured process output are
replaced with `<case_dir>` and `<repo>` so the evidence is stable and does not
publish workstation paths. Newlines are normalized to LF; return codes,
diagnostics, property values, and all other output remain intact.

## Provenance and license

ec4j is Copyright its contributors and licensed under Apache-2.0. The
comparison executes an independently built upstream artifact and records its
textual CLI output. It does not copy ec4j source code or fixtures. Repository:
<https://github.com/ec4j/ec4j>; license:
<https://github.com/ec4j/ec4j/blob/4c1a0b00c4dfb8434cfc64d3f5bb8a6ae5b2db5a/LICENSE>.
