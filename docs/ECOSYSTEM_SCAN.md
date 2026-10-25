# Ecosystem scan

Verified on 2026-10-24 (Asia/Shanghai).

## Target names

- GitHub: <https://github.com/yino04/moon-editorconfig> is the public repository
  for this project.
- Mooncakes manifest lookup for `yino04/moon-editorconfig` returned HTTP 404.
- Mooncakes searches for `yino04`, `editorconfig`, and `moon-editorconfig` did
  not return this module.

This only establishes that the module was not published at the time of the
scan. It does not reserve the name or prove that a particular logged-in
Mooncakes account controls the `yino04` namespace. Both must be checked again
immediately before publication.

## Highly similar existing implementation

An existing MoonBit project substantially overlaps this project:

- GitHub: <https://github.com/tlhuecdkoyg/MoonEditorConfig>
- Mooncakes: <https://mooncakes.io/docs/tlhuecdkoyg/MoonEditorConfig>
- Observed version: `0.1.0`, published 2026-08-22.
- Observed commit during the scan:
  `ed09e515257f5f3a59a064c9c8884997ae742404`.
- License: Apache-2.0.

Its advertised features include parsing, glob matching, hierarchical
resolution, validation, CLI and JSON output. Consequently, this project does
not claim to be the first MoonBit EditorConfig implementation. MoonEditorConfig
is being implemented independently from the normative specification. No source
from the similar project is incorporated unless a future change explicitly
records the exact file, revision, license, and modification.

## Adjacent packages

- `Lxxbv/glob` 0.2.6 (Apache-2.0): <https://github.com/Lxxbv/glob>
- `justjavac/glob` 0.2.0 (MIT): <https://mooncakes.io/docs/justjavac/glob>
- `moonbit-community/ini` 0.2.3 (Apache-2.0):
  <https://github.com/moonbit-community/ini>

Generic glob and INI packages do not by themselves implement EditorConfig's
section-header grammar, directory discovery, precedence, `root`, or `unset`
semantics. The core implementation in this repository therefore remains
self-contained and specification-driven.

## Queries used

GitHub searches covered repository names, descriptions, README content,
MoonBit language classification, and `.mbt` files containing EditorConfig
terms. Mooncakes searches covered `editorconfig`, `moon-editorconfig`,
`MoonEditorConfig`, `yino04`, `glob`, and INI parser terms, plus direct manifest
lookups for both the target module and the similar published implementation.
