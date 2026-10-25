#!/usr/bin/env python3
"""Fail fast on auditable v0.1 release prerequisites."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from count_effective_loc import collect


REQUIRED_FILES = (
    "LICENSE",
    "NOTICE",
    "README.md",
    "CHANGELOG.md",
    "moon.mod",
    ".github/workflows/ci.yml",
    "docs/API.md",
    "docs/COMPATIBILITY.md",
    "docs/DESIGN.md",
    "docs/ECOSYSTEM_SCAN.md",
    "docs/RELEASE.md",
    "docs/TEST_REPORT.md",
    "docs/UPSTREAM.md",
)


def git(root: Path, *arguments: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(root), *arguments],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    return completed.stdout.strip()


def check(condition: bool, message: str, failures: list[str]) -> None:
    label = "PASS" if condition else "FAIL"
    print(f"[{label}] {message}")
    if not condition:
        failures.append(message)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", default=".", help="module root")
    parser.add_argument("--minimum-loc", type=int, default=4000)
    parser.add_argument("--minimum-commits", type=int, default=8)
    parser.add_argument(
        "--allow-dirty", action="store_true", help="do not fail on changes"
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    failures: list[str] = []
    check((root / "moon.mod").is_file(), "module root contains moon.mod", failures)
    for relative in REQUIRED_FILES:
        check((root / relative).is_file(), f"required file: {relative}", failures)

    legacy_manifests = list(root.rglob("moon.mod.json")) + list(
        root.rglob("moon.pkg.json")
    )
    check(not legacy_manifests, "no legacy JSON MoonBit manifests", failures)

    counts = collect(root)
    effective = sum(item.nonblank_noncomment for item in counts)
    check(
        effective >= args.minimum_loc,
        f"effective production LOC {effective} >= {args.minimum_loc}",
        failures,
    )

    try:
        commit_count = int(git(root, "rev-list", "--count", "HEAD"))
        check(
            commit_count >= args.minimum_commits,
            f"real commit count {commit_count} >= {args.minimum_commits}",
            failures,
        )
        origin = git(root, "remote", "get-url", "origin")
        check(
            origin.rstrip("/").removesuffix(".git")
            == "https://github.com/yino04/moon-editorconfig",
            "origin is yino04/moon-editorconfig",
            failures,
        )
        dirty = bool(git(root, "status", "--porcelain"))
        check(args.allow_dirty or not dirty, "working tree is clean", failures)
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        failures.append(f"git audit failed: {error}")
        print(f"[FAIL] git audit failed: {error}")

    if failures:
        print(f"\nRelease audit failed with {len(failures)} issue(s).")
        return 1
    print("\nRelease audit passed. Build/test/CI and publication evidence remain separate gates.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
