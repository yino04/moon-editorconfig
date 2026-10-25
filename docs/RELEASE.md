# Release process

## Current status

MoonEditorConfig 0.1.0 is **not published** as of 2026-10-25. There is no
claimed Mooncakes package page, Git tag, GitHub Release, or successful release
workflow. The CI workflow performs checks only and has no write permissions or
publishing step.

The planned module identity is `yino04/moon-editorconfig`, subject to a fresh
Mooncakes namespace and ownership check immediately before publication. A
previous search result or an HTTP 404 does not reserve that name.

## Authorization boundary

Preparation, local packaging, read-only account checks, and dry-run validation
may happen during development. The following external mutations require an
explicit instruction from the repository owner after the candidate passes all
gates:

- `moon publish` to Mooncakes;
- pushing the `v0.1.0` tag;
- creating a GitHub Release.

Credentials and tokens must come from the user's existing authenticated tools.
They must never be copied into source files, logs, issues, or workflow YAML.

## v0.1.0 release gate

1. Confirm `main` is clean and record `git rev-parse HEAD`.
2. Confirm `moon.mod` names version `0.1.0`, repository, Apache-2.0 license,
   description, and `yino04/moon-editorconfig` module identity.
3. Verify `LICENSE`, `NOTICE`, and the pinned upstream/test provenance records.
4. Run every core and CLI command in `docs/TEST_REPORT.md` at the candidate
   commit; replace all `pending` audit fields with real results.
5. Confirm at least 120 distinct asserted scenarios and at least 20 preserved
   ec4j comparison records.
6. Run `scripts/count_effective_loc.py`, then manually review the reported
   production `.mbt` files. The script is only an approximate nonblank,
   non-comment counter.
7. Run `python scripts/verify_release.py` and resolve every reported gate.
8. Run `moon package` and inspect the package contents for secrets, build
   output, fixtures with unclear licensing, and accidental generated files.
9. Push the candidate commit and require a real green GitHub Actions run for
   that exact SHA.
10. Recheck Mooncakes login, namespace ownership, and package-name availability
    without printing credentials.
11. Ask the owner for explicit publication and tag authorization. Stop here if
    it is not granted.
12. After authorization, run `moon publish`, verify the public package page,
    then create and push `v0.1.0` at the tested SHA and create the GitHub
    Release.
13. Record the real package URL, release URL, timestamps, tag SHA, CI run, and
    any publication warnings below.

Do not move a failed gate into a “known limitation” merely to publish. Fix it,
or leave the version explicitly unpublished.

## Exit-code contract for v0.1

The release CLI documentation and E2E checks use these stable categories:

| Code | Meaning |
|---:|---|
| 0 | Command completed successfully; a glob non-match is a valid result. |
| 2 | CLI usage error, including an unknown command or wrong argument count. |
| 3 | The parsed or validated EditorConfig input is invalid. |
| 4 | Host I/O failure. |
| 5 | A configured resource/safety budget was exhausted. |

If the implementation adopts a different code before v0.1.0, update the CLI,
CI assertions, API documentation, and this table together.

## Publication record

- Version: `0.1.0` (planned)
- Tested commit: `pending`
- Git tag: `not created`
- GitHub Actions run: `pending`
- Mooncakes URL: `not published`
- GitHub Release URL: `not created`
- Published at: `not published`
- Authorized by owner: `not yet`
- Rollback/deprecation action, if needed: `not applicable`

After publication, replace these placeholders only with links and identifiers
that have been independently opened or queried successfully.
