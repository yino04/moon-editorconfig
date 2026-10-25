# Upstream references

Verified on 2026-10-24.

## ec4j

- Repository: <https://github.com/ec4j/ec4j>
- Pinned default-branch commit: `64a1f1a0ef1ac78d4f849de34a1c596e3fc87f91`
- Pinned revision reports itself as `1.2.1-SNAPSHOT`.
- Latest stable tag at verification time: `1.2.0`, peeled commit
  `4c1a0b00c4dfb8434cfc64d3f5bb8a6ae5b2db5a`.
- License: Apache-2.0
- Intended use: behavioral comparison and architectural study only.
- Copied source at bootstrap: none.

If a later change ports or adapts a specific upstream fragment, that change
must identify its upstream path and commit in this file and retain applicable
copyright notices.

## EditorConfig core tests

- Repository: <https://github.com/editorconfig/editorconfig-core-test>
- Pinned default-branch commit: `895b3a65d0d823dbd0acf2bc402376381995d1b1`
- License: BSD-2-Clause (copyright EditorConfig Team, 2011-2018)
- Intended use: test-vector comparison. Imported fixtures must preserve their
  license and attribution.

## Normative specification

- EditorConfig specification 0.17.2: <https://spec.editorconfig.org/>
- Live specification source snapshot used by this implementation:
  `f58051318a657b52b73ff2d7774a66fa6c296bd8`.
- Historical `v0.17.2` tag commit:
  `329077a5649b013903c2aeaa5617afb70fcc9eaf`.
- The specification is normative; ec4j differences are compatibility data,
  not permission to override the selected standard behavior.

The live 0.17.2 source contains clarifications added after the historical tag,
including empty values, nested alternatives, integer-range ordering, leading
slashes, and same-file precedence. Documentation therefore cites both the live
snapshot and the historical tag rather than silently treating them as equal.

## Known ec4j compatibility differences

At the pinned ec4j revision, its parser accepts `:` separators and legacy
inline comments, its standard-property list does not include
`spelling_language`, and its glob implementation has different numeric-range
behavior. The `standard` compatibility profile follows specification 0.17.2;
ec4j comparisons are reported separately and are never treated as normative.
