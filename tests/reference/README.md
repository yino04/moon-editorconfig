# External reference harness

This directory contains a reproducible, process-level comparison with ec4j.
It does not reimplement EditorConfig in Python. The Python program creates an
isolated file tree for each case and invokes the real ec4j CLI, and optionally
the real `moonecfg` CLI, as child processes.

## Contents

- `cases.json` contains 29 independently authored EditorConfig 0.17.2 cases.
- `run_reference.py` materializes the cases, runs both CLIs, and classifies the
  semantic results.
- `ec4j-results.json` records the raw stdout, stderr, return code, and parsed
  properties observed from the pinned ec4j build.
- `moon-comparison.json` records the corresponding real `moonecfg` runs and
  the final per-case classification.

No ec4j or editorconfig-core-test source or fixture is copied into this
directory.

## Pinned reference

- Source: <https://github.com/ec4j/ec4j>
- ec4j release: `1.2.0`
- Git commit: `4c1a0b00c4dfb8434cfc64d3f5bb8a6ae5b2db5a`
- License: Apache-2.0; the authoritative license text remains in the upstream
  checkout.

The observed `--version` string is `EditorConfig Java Version 0.12.0-final`.
That is ec4j's advertised EditorConfig compatibility version, not the Maven
artifact version.

## Reproduce the ec4j observations

Checkout the exact source revision, then let the harness run ec4j's Maven unit
tests before querying all fixtures:

```powershell
git clone https://github.com/ec4j/ec4j.git work/ec4j
git -C work/ec4j fetch origin 4c1a0b00c4dfb8434cfc64d3f5bb8a6ae5b2db5a
git -C work/ec4j checkout --detach 4c1a0b00c4dfb8434cfc64d3f5bb8a6ae5b2db5a
$env:JAVA_HOME = 'C:\path\to\jdk-21'
python tests/reference/run_reference.py --ec4j-repo work/ec4j --build-ec4j
python tests/reference/run_reference.py --ec4j-repo work/ec4j --check
```

The harness verifies the checkout's full SHA before running. Its Maven command
is:

```text
mvnw.cmd -pl core -am clean verify
```

Its query command for every case is:

```text
java -cp <ec4j-jar> org.ec4j.core.cli.Cli <target>
```

## Add the Moon CLI comparison

Pass a JSON array containing the actual Moon CLI command. The placeholders
`{repo}`, `{case_dir}`, `{target}`, and `{target_rel}` are expanded separately
for every isolated case. The checked-in comparison used the filesystem-capable
wasm backend and JSON output:

```powershell
$moon = '["C:\\path\\to\\moon.exe","run","cmd/moonecfg","--target","wasm","--deny-warn","--","resolve","{target}","--json"]'
python tests/reference/run_reference.py `
  --ec4j-repo work/ec4j `
  --moon-command-json $moon `
  --moon-output json `
  --write-results tests/reference/moon-comparison.json
python tests/reference/run_reference.py `
  --ec4j-repo work/ec4j `
  --moon-command-json $moon `
  --moon-output json `
  --write-results tests/reference/moon-comparison.json `
  --check
```

The harness accepts a direct map, a `properties`/`effective`/`settings` object,
or an array of `{key,value}` objects.

The recorded outcome is 24 `spec_agreement` cases and five
`known_ec4j_difference` cases, with no `project_defect` or unclassified case.

The final categories are deliberately asymmetric because the specification is
normative and ec4j is only a reference implementation:

- `spec_agreement`: both observable semantic results equal the 0.17.2 result;
- `known_ec4j_difference`: Moon follows 0.17.2 and ec4j has a documented
  compatibility difference;
- `project_defect`: Moon differs from the authored 0.17.2 expectation;
- `unclassified_reference_difference`: ec4j differs without a documented
  reason and the case needs review.

ec4j's core-test CLI keeps `unset` markers and materializes indentation
defaults. MoonEditorConfig exposes active assignments and a typed indentation
helper. The record therefore retains raw properties and also stores a narrowly
defined `comparison_properties` projection: it removes inactive `unset`
markers and those two derived indentation presentation values. No glob,
parser, or precedence output is normalized.

To keep evidence deterministic across machines, temporary-directory and
repository roots in captured stdout/stderr are replaced with `<case_dir>` and
`<repo>`. Newlines are normalized to LF. Return codes, diagnostics, property
values, and all remaining process output are retained.
