#!/usr/bin/env python3
"""Run reproducible EditorConfig resolution comparisons against ec4j and Moon.

This is an external interoperability harness. It never substitutes Python code
for MoonEditorConfig's parser, matcher, or resolver. Each fixture is materialized
in a fresh temporary directory and queried through the real command-line entry
point of each implementation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any
import xml.etree.ElementTree as ET


PINNED_EC4J_SHA = "4c1a0b00c4dfb8434cfc64d3f5bb8a6ae5b2db5a"
EC4J_MAIN_CLASS = "org.ec4j.core.cli.Cli"


def run(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    timeout: int = 120,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )


def checked_stdout(argv: list[str], *, cwd: Path) -> str:
    result = run(argv, cwd=cwd)
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {argv!r}\n{result.stderr}"
        )
    return result.stdout.strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def surefire_summary(ec4j_repo: Path) -> dict[str, int]:
    summary = {"tests": 0, "failures": 0, "errors": 0, "skipped": 0}
    reports = sorted((ec4j_repo / "core" / "target" / "surefire-reports").glob("TEST-*.xml"))
    for report in reports:
        suite = ET.parse(report).getroot()
        for key in summary:
            summary[key] += int(suite.attrib.get(key, "0"))
    return summary


def write_console(stream: Any, value: str) -> None:
    encoding = getattr(stream, "encoding", None) or "utf-8"
    if hasattr(stream, "buffer"):
        stream.buffer.write(value.encode(encoding, errors="replace"))
        stream.flush()
    else:
        stream.write(value)


def default_repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def default_ec4j_repo(repo_root: Path) -> Path:
    return repo_root.parent.parent / "work" / "ec4j"


def discover_java(repo_root: Path) -> Path:
    java_home = os.environ.get("JAVA_HOME")
    if java_home:
        candidate = Path(java_home) / "bin" / ("java.exe" if os.name == "nt" else "java")
        if candidate.is_file():
            return candidate
    jdk_root = repo_root.parent.parent / "work" / "jdk21"
    executable = "java.exe" if os.name == "nt" else "java"
    candidates = sorted(jdk_root.glob(f"*/bin/{executable}"))
    if candidates:
        return candidates[-1]
    return Path(executable)


def normalize_newlines(value: str) -> str:
    return value.replace("\r\n", "\n").replace("\r", "\n")


def parse_property_lines(stdout: str) -> dict[str, str]:
    properties: dict[str, str] = {}
    for raw_line in normalize_newlines(stdout).split("\n"):
        line = raw_line.strip("\n")
        if not line or line.startswith("[") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().lower()
        if key and not any(ch.isspace() for ch in key):
            properties[key] = value
    return dict(sorted(properties.items()))


def properties_from_json(value: Any) -> dict[str, str]:
    if isinstance(value, dict):
        for key in ("properties", "effective", "settings", "result"):
            if key in value:
                try:
                    return properties_from_json(value[key])
                except ValueError:
                    pass
        if all(isinstance(key, str) for key in value) and all(
            isinstance(item, (str, int, float, bool)) or item is None
            for item in value.values()
        ):
            return dict(
                sorted(
                    (key.lower(), "" if item is None else str(item).lower() if isinstance(item, bool) else str(item))
                    for key, item in value.items()
                )
            )
    if isinstance(value, list):
        result: dict[str, str] = {}
        for item in value:
            if not isinstance(item, dict):
                continue
            key = item.get("key", item.get("name"))
            item_value = item.get("value")
            if isinstance(key, str) and item_value is not None:
                result[key.lower()] = str(item_value)
        if result or not value:
            return dict(sorted(result.items()))
    raise ValueError("could not locate a property map in Moon JSON output")


def parse_moon_output(stdout: str, output_format: str) -> dict[str, str]:
    if output_format == "properties":
        return parse_property_lines(stdout)
    try:
        return properties_from_json(json.loads(stdout))
    except (json.JSONDecodeError, ValueError) as error:
        raise ValueError(f"invalid Moon JSON output: {error}") from error


def comparison_projection(
    properties: dict[str, str] | None, expected: dict[str, str]
) -> dict[str, str] | None:
    """Remove CLI presentation choices that do not change resolved semantics.

    ec4j's core-test CLI deliberately keeps `unset` markers and materializes
    the EditorConfig indentation defaults. MoonEditorConfig's resolver exposes
    active assignments and provides indentation defaults through a typed helper.
    We retain raw output in the record, but compare the common semantic view.
    """
    if properties is None:
        return None
    projected = {
        key: value for key, value in properties.items() if value.lower() != "unset"
    }
    if "tab_width" not in expected and "tab_width" in projected:
        indent_size = projected.get("indent_size")
        if indent_size is not None and projected["tab_width"] == indent_size:
            projected.pop("tab_width")
    if (
        "indent_size" not in expected
        and projected.get("indent_size") == "tab"
        and projected.get("indent_style") == "tab"
    ):
        projected.pop("indent_size")
    return dict(sorted(projected.items()))


def portable_process_result(
    result: subprocess.CompletedProcess[str],
    properties: dict[str, str] | None,
    comparison_properties: dict[str, str] | None,
    redactions: list[tuple[Path, str]],
) -> dict[str, Any]:
    def portable_text(value: str) -> str:
        value = normalize_newlines(value)
        for path, replacement in redactions:
            variants = {
                str(path.resolve()),
                path.resolve().as_posix(),
                str(path.resolve()).replace("\\", "/"),
            }
            for variant in sorted(variants, key=len, reverse=True):
                value = value.replace(variant, replacement)
        return value

    record: dict[str, Any] = {
        "return_code": result.returncode,
        "stdout": portable_text(result.stdout),
        "stderr": portable_text(result.stderr),
    }
    if properties is not None:
        record["properties"] = properties
    if comparison_properties is not None:
        record["comparison_properties"] = comparison_properties
    return record


def safe_materialize(case: dict[str, Any], case_dir: Path) -> Path:
    root = case_dir.resolve()
    for relative, content in case["files"].items():
        destination = (root / Path(relative)).resolve()
        if not destination.is_relative_to(root):
            raise ValueError(f"fixture path escapes case directory: {relative!r}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content.encode("utf-8"))
    target = (root / Path(case["target"])).resolve()
    if not target.is_relative_to(root):
        raise ValueError(f"target path escapes case directory: {case['target']!r}")
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        target.write_bytes(b"")
    return target


def format_moon_command(
    template: list[str], *, repo_root: Path, case_dir: Path, target: Path, target_rel: str
) -> list[str]:
    values = {
        "repo": str(repo_root),
        "case_dir": str(case_dir),
        "target": str(target),
        "target_rel": target_rel,
    }
    return [part.format(**values) for part in template]


def portable_moon_template(template: list[str] | None, repo_root: Path) -> list[str] | None:
    if template is None:
        return None
    result: list[str] = []
    for index, part in enumerate(template):
        portable = part.replace(str(repo_root), "{repo}")
        if index == 0 and Path(part).name.lower() in ("moon", "moon.exe"):
            portable = "moon"
        result.append(portable)
    return result


def moon_metadata(template: list[str] | None, repo_root: Path) -> dict[str, Any] | None:
    if template is None:
        return None
    executable = Path(template[0])
    toolchain_result: subprocess.CompletedProcess[str] | None = None
    if executable.name.lower() in ("moon", "moon.exe"):
        toolchain_result = run([template[0], "version", "--all"], cwd=repo_root)
    if "--" in template:
        separator = template.index("--")
        cli_version_command = template[: separator + 1] + ["--version"]
    else:
        cli_version_command = [template[0], "--version"]
    cli_version = run(cli_version_command, cwd=repo_root)

    def clean(value: str) -> str:
        value = normalize_newlines(value)
        value = value.replace("~\\.moon", "<moon-home>")
        value = value.replace("~/.moon", "<moon-home>")
        if executable.is_absolute():
            moon_home = executable.parent.parent
            for path in (str(moon_home), moon_home.as_posix()):
                value = value.replace("\\\\?\\" + path, "<moon-home>")
                value = value.replace(path, "<moon-home>")
        return value.strip()

    metadata: dict[str, Any] = {
        "command_template": portable_moon_template(template, repo_root),
        "cli_version_stdout": clean(cli_version.stdout),
        "cli_version_stderr": clean(cli_version.stderr),
        "cli_version_return_code": cli_version.returncode,
    }
    if toolchain_result is not None:
        metadata["toolchain_version_stdout"] = clean(toolchain_result.stdout)
        metadata["toolchain_version_stderr"] = clean(toolchain_result.stderr)
        metadata["toolchain_version_return_code"] = toolchain_result.returncode
    return metadata


def relation(actual: dict[str, str] | None, expected: dict[str, str]) -> str:
    if actual is None:
        return "unavailable"
    return "agreement" if actual == expected else "difference"


def classify(
    case: dict[str, Any], ec4j_properties: dict[str, str] | None, moon_properties: dict[str, str] | None
) -> str:
    expected = dict(sorted(case["spec_properties"].items()))
    if moon_properties is None:
        return "pending_moon_cli"
    if moon_properties != expected:
        return "project_defect"
    if ec4j_properties == expected:
        return "spec_agreement"
    if case.get("known_ec4j_difference"):
        return "known_ec4j_difference"
    return "unclassified_reference_difference"


def classify_ec4j(
    case: dict[str, Any], ec4j_properties: dict[str, str] | None
) -> str:
    expected = dict(sorted(case["spec_properties"].items()))
    if ec4j_properties == expected:
        return "spec_agreement"
    if case.get("known_ec4j_difference"):
        return "known_ec4j_difference"
    return "unclassified_reference_difference"


def parse_args() -> argparse.Namespace:
    repo_root = default_repo_root()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cases", type=Path, default=Path(__file__).with_name("cases.json")
    )
    parser.add_argument("--ec4j-repo", type=Path, default=default_ec4j_repo(repo_root))
    parser.add_argument("--java", type=Path, default=discover_java(repo_root))
    parser.add_argument(
        "--build-ec4j",
        action="store_true",
        help="run the pinned ec4j Maven unit-test build before comparisons",
    )
    parser.add_argument(
        "--moon-command-json",
        help=(
            "JSON array command template for the real Moon CLI; placeholders are "
            "{repo}, {case_dir}, {target}, and {target_rel}"
        ),
    )
    parser.add_argument(
        "--moon-output", choices=("properties", "json"), default="properties"
    )
    parser.add_argument(
        "--write-results",
        type=Path,
        default=Path(__file__).with_name("ec4j-results.json"),
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="compare fresh ec4j observations with the existing results file",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = default_repo_root()
    ec4j_repo = args.ec4j_repo.resolve()
    java = args.java.resolve() if args.java.exists() else args.java
    cases_document = json.loads(args.cases.read_text(encoding="utf-8"))
    cases = cases_document["cases"]
    ids = [case["id"] for case in cases]
    if len(ids) < 20 or len(ids) != len(set(ids)):
        raise ValueError("reference suite needs at least 20 uniquely named cases")

    actual_sha = checked_stdout(
        ["git", "rev-parse", "HEAD"], cwd=ec4j_repo
    )
    if actual_sha != PINNED_EC4J_SHA:
        raise RuntimeError(
            f"ec4j checkout is {actual_sha}; expected {PINNED_EC4J_SHA}"
        )

    wrapper = ec4j_repo / ("mvnw.cmd" if os.name == "nt" else "mvnw")
    if args.build_ec4j:
        build_env = os.environ.copy()
        build_env["JAVA_HOME"] = str(java.parent.parent)
        build = run(
            [str(wrapper), "-pl", "core", "-am", "clean", "verify"],
            cwd=ec4j_repo,
            env=build_env,
            timeout=600,
        )
        write_console(sys.stdout, build.stdout)
        write_console(sys.stderr, build.stderr)
        if build.returncode != 0:
            return build.returncode

    jar = ec4j_repo / "core" / "target" / "ec4j-core-1.2.0.jar"
    if not jar.is_file():
        raise FileNotFoundError(
            f"missing {jar}; rerun with --build-ec4j to build the pinned source"
        )
    license_file = ec4j_repo / "LICENSE"
    if not license_file.is_file():
        raise FileNotFoundError(f"missing ec4j license file: {license_file}")

    moon_template: list[str] | None = None
    if args.moon_command_json:
        parsed = json.loads(args.moon_command_json)
        if not isinstance(parsed, list) or not all(isinstance(item, str) for item in parsed):
            raise ValueError("--moon-command-json must decode to an array of strings")
        moon_template = parsed

    ec4j_version = run(
        [str(java), "-cp", str(jar), EC4J_MAIN_CLASS, "--version"],
        cwd=ec4j_repo,
    )
    java_version = run([str(java), "-version"], cwd=ec4j_repo)
    observations: list[dict[str, Any]] = []
    counts: dict[str, int] = {}
    ec4j_counts: dict[str, int] = {}

    for case in cases:
        expected = dict(sorted(case["spec_properties"].items()))
        with tempfile.TemporaryDirectory(prefix=f"moonecfg-ref-{case['id']}-") as temp:
            case_dir = Path(temp)
            target = safe_materialize(case, case_dir)
            ec4j_process = run(
                [str(java), "-cp", str(jar), EC4J_MAIN_CLASS, case["target"]],
                cwd=case_dir,
            )
            ec4j_properties = (
                parse_property_lines(ec4j_process.stdout)
                if ec4j_process.returncode == 0
                else None
            )
            ec4j_comparison = comparison_projection(ec4j_properties, expected)

            moon_process: subprocess.CompletedProcess[str] | None = None
            moon_properties: dict[str, str] | None = None
            moon_comparison: dict[str, str] | None = None
            moon_parse_error: str | None = None
            if moon_template is not None:
                command = format_moon_command(
                    moon_template,
                    repo_root=repo_root,
                    case_dir=case_dir,
                    target=target,
                    target_rel=case["target"],
                )
                moon_process = run(command, cwd=repo_root)
                try:
                    moon_properties = parse_moon_output(
                        moon_process.stdout, args.moon_output
                    )
                    moon_comparison = comparison_projection(moon_properties, expected)
                except ValueError as error:
                    moon_parse_error = str(error)

            category = classify(case, ec4j_comparison, moon_comparison)
            counts[category] = counts.get(category, 0) + 1
            ec4j_category = classify_ec4j(case, ec4j_comparison)
            ec4j_counts[ec4j_category] = ec4j_counts.get(ec4j_category, 0) + 1
            observation: dict[str, Any] = {
                "id": case["id"],
                "topic": case["topic"],
                "spec_properties": expected,
                "ec4j_vs_spec": relation(ec4j_comparison, expected),
                "ec4j_classification": ec4j_category,
                "classification": category,
                "ec4j": portable_process_result(
                    ec4j_process,
                    ec4j_properties,
                    ec4j_comparison,
                    [(case_dir, "<case_dir>"), (repo_root, "<repo>")],
                ),
            }
            if case.get("known_ec4j_difference"):
                observation["known_ec4j_difference"] = case[
                    "known_ec4j_difference"
                ]
            if moon_process is not None:
                observation["moon"] = portable_process_result(
                    moon_process,
                    moon_properties,
                    moon_comparison,
                    [(case_dir, "<case_dir>"), (repo_root, "<repo>")],
                )
                if moon_parse_error:
                    observation["moon"]["parse_error"] = moon_parse_error
            observations.append(observation)

    document = {
        "schema_version": 1,
        "specification": cases_document["specification"],
        "reference": {
            "name": "ec4j",
            "source": "https://github.com/ec4j/ec4j",
            "source_sha": actual_sha,
            "artifact": "core/target/ec4j-core-1.2.0.jar",
            "artifact_sha256": sha256_file(jar),
            "reported_version_stdout": normalize_newlines(ec4j_version.stdout).strip(),
            "reported_version_stderr": normalize_newlines(ec4j_version.stderr).strip(),
            "java_version": normalize_newlines(
                java_version.stderr or java_version.stdout
            ).strip(),
            "build_command": "mvnw.cmd -pl core -am clean verify",
            "unit_test_summary": surefire_summary(ec4j_repo),
            "query_command": "java -cp <ec4j-jar> org.ec4j.core.cli.Cli <target>",
            "license": "Apache-2.0; see the upstream LICENSE file",
        },
        "moon": moon_metadata(moon_template, repo_root),
        "counts": dict(sorted(counts.items())),
        "ec4j_counts": dict(sorted(ec4j_counts.items())),
        "cases": observations,
    }

    if args.check:
        recorded = json.loads(args.write_results.read_text(encoding="utf-8"))
        if moon_template is None:
            recorded_cases = {
                item["id"]: item["ec4j"] for item in recorded["cases"]
            }
            fresh_cases = {item["id"]: item["ec4j"] for item in observations}
        else:
            recorded_cases = {
                item["id"]: {
                    "ec4j": item["ec4j"],
                    "moon": item.get("moon"),
                    "classification": item["classification"],
                }
                for item in recorded["cases"]
            }
            fresh_cases = {
                item["id"]: {
                    "ec4j": item["ec4j"],
                    "moon": item.get("moon"),
                    "classification": item["classification"],
                }
                for item in observations
            }
        if recorded_cases != fresh_cases:
            print("recorded observations differ from a fresh run", file=sys.stderr)
            return 1
        engines = "ec4j and Moon" if moon_template is not None else "ec4j"
        print(f"verified {len(observations)} recorded {engines} observations")
    else:
        args.write_results.write_text(
            json.dumps(document, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {len(observations)} observations to {args.write_results}")

    bad_categories = {
        "project_defect",
        "unclassified_reference_difference",
    }
    return 1 if any(counts.get(name, 0) for name in bad_categories) else 0


if __name__ == "__main__":
    raise SystemExit(main())
