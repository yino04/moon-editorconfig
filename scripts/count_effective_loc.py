#!/usr/bin/env python3
"""Approximate effective MoonBit production lines without inflating metrics.

The counter includes tracked or working-tree ``.mbt`` production files and
excludes tests, generated interfaces, build output, examples, vendored code,
and reference fixtures. It removes blank lines and lines containing only line
or block comments. This is a transparent approximation, not a substitute for
manual review of whether each line implements meaningful behavior.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path


EXCLUDED_DIRS = {
    ".git",
    ".mooncakes",
    "_build",
    "examples",
    "fixtures",
    "reference",
    "target",
    "vendor",
}


@dataclass(frozen=True)
class FileCount:
    path: str
    physical: int
    nonblank_noncomment: int


def is_production_file(path: Path, root: Path) -> bool:
    relative = path.relative_to(root)
    if path.suffix != ".mbt":
        return False
    if any(part in EXCLUDED_DIRS for part in relative.parts):
        return False
    name = path.name
    return not (
        name.endswith("_test.mbt")
        or name.endswith("_wbtest.mbt")
        or name.endswith(".generated.mbt")
    )


def count_source(text: str) -> tuple[int, int]:
    lines = text.splitlines()
    effective = 0
    block_depth = 0
    for line in lines:
        index = 0
        has_code = False
        while index < len(line):
            if block_depth:
                if line.startswith("/*", index):
                    block_depth += 1
                    index += 2
                elif line.startswith("*/", index):
                    block_depth -= 1
                    index += 2
                else:
                    index += 1
                continue
            if line.startswith("//", index):
                break
            if line.startswith("/*", index):
                block_depth += 1
                index += 2
                continue
            if not line[index].isspace():
                has_code = True
            index += 1
        if has_code:
            effective += 1
    return len(lines), effective


def collect(root: Path) -> list[FileCount]:
    result: list[FileCount] = []
    for path in sorted(root.rglob("*.mbt")):
        if not is_production_file(path, root):
            continue
        physical, effective = count_source(path.read_text(encoding="utf-8"))
        result.append(
            FileCount(
                path=path.relative_to(root).as_posix(),
                physical=physical,
                nonblank_noncomment=effective,
            )
        )
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", default=".", help="module root")
    parser.add_argument("--json", action="store_true", help="emit JSON")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    files = collect(root)
    physical = sum(item.physical for item in files)
    effective = sum(item.nonblank_noncomment for item in files)
    payload = {
        "root": str(root),
        "method": "nonblank, non-comment .mbt production lines (approximation)",
        "physical": physical,
        "nonblank_noncomment": effective,
        "files": [asdict(item) for item in files],
    }
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        for item in files:
            print(f"{item.nonblank_noncomment:6d}  {item.path}")
        print(f"{effective:6d}  TOTAL effective approximation")
        print(f"{physical:6d}  TOTAL physical")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
