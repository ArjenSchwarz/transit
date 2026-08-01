#!/usr/bin/env python3
"""Reject SwiftData test-container construction that bypasses the owning fixture."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TEST_ROOT = REPOSITORY_ROOT / "Transit" / "TransitTests"
SUPPORT_FILE = (DEFAULT_TEST_ROOT / "TestModelContainer.swift").resolve()
SOURCE_SUFFIXES = (".swift", ".swift.fixture")


def mask_comments_and_strings(source: str) -> str:
    """Preserve positions/newlines while masking Swift comments and strings."""
    result = list(source)
    index = 0
    block_depth = 0
    state = "code"
    string_delimiter = ""

    while index < len(source):
        if state == "line_comment":
            if source[index] == "\n":
                state = "code"
            else:
                result[index] = " "
            index += 1
            continue

        if state == "block_comment":
            if source.startswith("/*", index):
                result[index:index + 2] = "  "
                block_depth += 1
                index += 2
            elif source.startswith("*/", index):
                result[index:index + 2] = "  "
                block_depth -= 1
                index += 2
                if block_depth == 0:
                    state = "code"
            else:
                if source[index] != "\n":
                    result[index] = " "
                index += 1
            continue

        if state == "string":
            if source.startswith(string_delimiter, index):
                result[index:index + len(string_delimiter)] = " " * len(string_delimiter)
                index += len(string_delimiter)
                state = "code"
            elif source[index] == "\\" and string_delimiter == '"':
                result[index] = " "
                if index + 1 < len(source):
                    result[index + 1] = " "
                index += 2
            else:
                if source[index] != "\n":
                    result[index] = " "
                index += 1
            continue

        if source.startswith("//", index):
            result[index:index + 2] = "  "
            index += 2
            state = "line_comment"
        elif source.startswith("/*", index):
            result[index:index + 2] = "  "
            index += 2
            block_depth = 1
            state = "block_comment"
        elif source.startswith('"""', index):
            result[index:index + 3] = "   "
            index += 3
            string_delimiter = '"""'
            state = "string"
        elif source[index] == '"':
            result[index] = " "
            index += 1
            string_delimiter = '"'
            state = "string"
        else:
            index += 1

    return "".join(result)


def source_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_dir():
            files.extend(
                candidate for candidate in path.rglob("*")
                if candidate.is_file() and candidate.name.endswith(SOURCE_SUFFIXES)
            )
        elif path.is_file() and path.name.endswith(SOURCE_SUFFIXES):
            files.append(path)
        else:
            raise ValueError(f"not a Swift source file or directory: {path}")
    return sorted(set(files))


def line_number(source: str, offset: int) -> int:
    return source.count("\n", 0, offset) + 1


def validate_file(path: Path) -> list[str]:
    source = path.read_text(encoding="utf-8")
    masked = mask_comments_and_strings(source)
    errors: list[str] = []

    checks = [
        (
            re.compile(r"\bTestModelContainer\s*\.\s*(?:newContext|newContainer)\s*\("),
            "removed raw TestModelContainer factory; construct and retain TestModelContainer instead"
        ),
        (
            re.compile(r"\bModelContainer\s*\.\s*init\s*\("),
            "direct ModelContainer.init construction bypasses TestModelContainer ownership"
        ),
        (
            re.compile(r"\bModelContainer\s*\("),
            "direct ModelContainer construction bypasses TestModelContainer ownership"
        ),
        (
            re.compile(r":\s*ModelContainer\s*=\s*\.\s*init\s*\("),
            "inferred ModelContainer.init construction bypasses TestModelContainer ownership"
        )
    ]

    is_support_file = path.resolve() == SUPPORT_FILE
    raw_constructor_matches: list[re.Match[str]] = []
    for pattern, message in checks:
        for match in pattern.finditer(masked):
            if is_support_file and message.startswith("direct ModelContainer"):
                raw_constructor_matches.append(match)
                continue
            errors.append(f"{path}:{line_number(source, match.start())}: {message}")

    if is_support_file:
        # The fixture implementation is the sole construction boundary. It may
        # construct exactly one raw container, only from an initializer, and it
        # must retain every resulting container for the test-process lifetime.
        unique_raw_offsets = {match.start() for match in raw_constructor_matches}
        if len(unique_raw_offsets) != 1:
            errors.append(
                f"{path}: expected exactly one centralized ModelContainer construction, "
                f"found {len(unique_raw_offsets)}"
            )
        if not re.search(r"private\s+static\s+var\s+retainedContainers\s*:\s*\[ModelContainer\]", masked):
            errors.append(f"{path}: TestModelContainer must privately retain created containers")
        if not re.search(r"Self\s*\.\s*retainedContainers\s*\.\s*append\s*\(\s*container\s*\)", masked):
            errors.append(f"{path}: TestModelContainer initializer must register every created container")
        raw_return = re.compile(r"\bfunc\b[^\{;]*->[^\{;]*\bModel(?:Context|Container)\b", re.DOTALL)
        for match in raw_return.finditer(masked):
            errors.append(
                f"{path}:{line_number(source, match.start())}: fixture support must not expose a raw "
                "ModelContext/ModelContainer factory"
            )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        default=[DEFAULT_TEST_ROOT],
        help="Swift files or directories to validate (default: Transit/TransitTests)"
    )
    args = parser.parse_args()

    try:
        files = source_files(args.paths)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    errors = [error for path in files for error in validate_file(path)]
    if errors:
        print("SwiftData test ownership validation failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1

    print(f"SwiftData test ownership validation passed ({len(files)} files).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
