#!/usr/bin/env python3
"""Reject SwiftData test-container construction that bypasses the owning fixture."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TEST_ROOT = REPOSITORY_ROOT / "Transit" / "TransitTests"
DEFAULT_SUPPORT_FILE = (DEFAULT_TEST_ROOT / "TestModelContainer.swift").resolve()
SOURCE_SUFFIXES = (".swift", ".swift.fixture")


def mask_comments_and_strings(source: str) -> str:
    """Preserve code positions while masking Swift comments and string contents.

    String interpolation is code, so it remains visible to the ownership checks.
    Raw strings use the same number of ``#`` characters for their closing and
    interpolation delimiters.
    """
    result = list(source)

    def mask(start: int, end: int) -> None:
        for offset in range(start, min(end, len(source))):
            if source[offset] != "\n":
                result[offset] = " "

    def string_opener(index: int) -> tuple[int, int, int] | None:
        cursor = index
        while cursor < len(source) and source[cursor] == "#":
            cursor += 1
        hash_count = cursor - index
        if source.startswith('"""', cursor):
            return hash_count, 3, cursor + 3
        if cursor < len(source) and source[cursor] == '"':
            return hash_count, 1, cursor + 1
        return None

    def scan_block_comment(index: int) -> int:
        depth = 1
        cursor = index + 2
        mask(index, cursor)
        while cursor < len(source) and depth:
            if source.startswith("/*", cursor):
                mask(cursor, cursor + 2)
                depth += 1
                cursor += 2
            elif source.startswith("*/", cursor):
                mask(cursor, cursor + 2)
                depth -= 1
                cursor += 2
            else:
                mask(cursor, cursor + 1)
                cursor += 1
        return cursor

    def scan_string(index: int, hash_count: int, quote_count: int, content_start: int) -> int:
        closing = '"' * quote_count + "#" * hash_count
        interpolation = "\\" + "#" * hash_count + "("
        mask(index, content_start)
        cursor = content_start

        while cursor < len(source):
            if source.startswith(closing, cursor):
                mask(cursor, cursor + len(closing))
                return cursor + len(closing)
            if source.startswith(interpolation, cursor):
                # Mask the interpolation escape but preserve its parentheses and
                # recursively scanned code, including nested strings/comments.
                mask(cursor, cursor + len(interpolation) - 1)
                cursor = scan_code(cursor + len(interpolation), stop_at_closing_paren=True)
                continue
            if hash_count == 0 and source[cursor] == "\\":
                # A non-raw string escape cannot begin an interpolation here,
                # because that case was handled immediately above.
                mask(cursor, cursor + 2)
                cursor += 2
                continue
            mask(cursor, cursor + 1)
            cursor += 1

        return cursor

    def scan_code(index: int, *, stop_at_closing_paren: bool = False) -> int:
        cursor = index
        nested_parens = 0
        while cursor < len(source):
            if source.startswith("//", cursor):
                line_end = source.find("\n", cursor)
                if line_end == -1:
                    line_end = len(source)
                mask(cursor, line_end)
                cursor = line_end
                continue
            if source.startswith("/*", cursor):
                cursor = scan_block_comment(cursor)
                continue

            opener = string_opener(cursor)
            if opener is not None:
                hash_count, quote_count, content_start = opener
                cursor = scan_string(cursor, hash_count, quote_count, content_start)
                continue

            if stop_at_closing_paren:
                if source[cursor] == "(":
                    nested_parens += 1
                elif source[cursor] == ")":
                    if nested_parens == 0:
                        return cursor + 1
                    nested_parens -= 1
            cursor += 1
        return cursor

    scan_code(0)
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


def matching_brace(masked: str, opening_offset: int) -> int | None:
    depth = 0
    for offset in range(opening_offset, len(masked)):
        if masked[offset] == "{":
            depth += 1
        elif masked[offset] == "}":
            depth -= 1
            if depth == 0:
                return offset
    return None


def initializer_ranges(masked: str) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int]] = []
    initializer = re.compile(r"(?<!\.)\binit\s*[!?]?\s*\(")
    for match in initializer.finditer(masked):
        opening_brace = masked.find("{", match.end())
        if opening_brace == -1:
            continue
        closing_brace = matching_brace(masked, opening_brace)
        if closing_brace is not None:
            ranges.append((opening_brace, closing_brace))
    return ranges


def is_top_level_in_body(masked: str, offset: int, body: tuple[int, int]) -> bool:
    opening_brace, closing_brace = body
    if not opening_brace < offset < closing_brace:
        return False
    depth = 0
    for character in masked[opening_brace + 1:offset]:
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
    return depth == 0


def validate_support_file(
    path: Path,
    source: str,
    masked: str,
    raw_constructor_matches: list[re.Match[str]]
) -> list[str]:
    errors: list[str] = []
    unique_raw_matches = {match.start(): match for match in raw_constructor_matches}
    if len(unique_raw_matches) != 1:
        errors.append(
            f"{path}: expected exactly one centralized ModelContainer construction, "
            f"found {len(unique_raw_matches)}"
        )
        return errors

    raw_match = next(iter(unique_raw_matches.values()))
    containing_initializers = [
        body for body in initializer_ranges(masked)
        if body[0] < raw_match.start() < body[1]
    ]
    if len(containing_initializers) != 1 or not is_top_level_in_body(
        masked, raw_match.start(), containing_initializers[0]
    ):
        errors.append(
            f"{path}:{line_number(source, raw_match.start())}: centralized ModelContainer "
            "construction must occur directly in a TestModelContainer initializer"
        )
        return errors

    body = containing_initializers[0]
    if not re.search(
        r"private\s+static\s+var\s+retainedContainers\s*:\s*\[ModelContainer\]",
        masked
    ):
        errors.append(f"{path}: TestModelContainer must privately retain created containers")

    retained_references = list(re.finditer(r"\bretainedContainers\b", masked))
    if len(retained_references) != 2:
        errors.append(
            f"{path}: retainedContainers must only be declared and appended to; "
            f"found {len(retained_references)} references"
        )

    required_steps = [
        (re.compile(r"\bself\s*\.\s*container\s*=\s*container\b"), "assign self.container"),
        (
            re.compile(r"\bself\s*\.\s*context\s*=\s*ModelContext\s*\(\s*container\s*\)"),
            "derive self.context from the retained container"
        ),
        (
            re.compile(r"\bSelf\s*\.\s*retainedContainers\s*\.\s*append\s*\(\s*container\s*\)"),
            "register every created container unconditionally"
        )
    ]

    previous_offset = raw_match.start()
    for pattern, description in required_steps:
        matches = [
            match for match in pattern.finditer(masked)
            if is_top_level_in_body(masked, match.start(), body)
        ]
        if len(matches) != 1 or matches[0].start() <= previous_offset:
            errors.append(f"{path}: TestModelContainer initializer must {description}")
            continue
        previous_offset = matches[0].start()

    raw_return = re.compile(r"\bfunc\b[^\{;]*->[^\{;]*\bModel(?:Context|Container)\b", re.DOTALL)
    for match in raw_return.finditer(masked):
        errors.append(
            f"{path}:{line_number(source, match.start())}: fixture support must not expose a raw "
            "ModelContext/ModelContainer factory"
        )

    return errors


def validate_file(path: Path, support_file: Path = DEFAULT_SUPPORT_FILE) -> list[str]:
    source = path.read_text(encoding="utf-8")
    masked = mask_comments_and_strings(source)
    errors: list[str] = []

    checks = [
        (
            re.compile(
                r"\bfunc\b[^\{;]*->\s*(?:\w+\s*\.\s*)*"
                r"Model(?:Context|Container)\s*[?!]?\s*(?:where\b[^\{;]*)?\{",
                re.DOTALL
            ),
            "raw ModelContext/ModelContainer factory must return an owning fixture instead"
        ),
        (
            re.compile(r"\bTestModelContainer\s*\.\s*(?:newContext|newContainer)\s*\("),
            "removed raw TestModelContainer factory; construct and retain TestModelContainer instead"
        ),
        (
            re.compile(r"\bModelContainer\s*\.\s*init\b"),
            "direct ModelContainer.init construction bypasses TestModelContainer ownership"
        ),
        (
            re.compile(r"\bModelContainer\s*\("),
            "direct ModelContainer construction bypasses TestModelContainer ownership"
        ),
        (
            re.compile(r":\s*(?:\w+\s*\.\s*)*ModelContainer\s*=\s*\.\s*init\s*\("),
            "inferred ModelContainer.init construction bypasses TestModelContainer ownership"
        ),
        (
            re.compile(r"\btypealias\s+\w+\s*=\s*(?:\w+\s*\.\s*)*ModelContainer\b"),
            "ModelContainer aliases bypass direct-construction ownership validation"
        )
    ]

    is_support_file = path.resolve() == support_file.resolve()
    raw_constructor_matches: list[re.Match[str]] = []
    for pattern, message in checks:
        for match in pattern.finditer(masked):
            if is_support_file and (
                message.startswith("direct ModelContainer")
                or message.startswith("inferred ModelContainer")
            ):
                raw_constructor_matches.append(match)
                continue
            errors.append(f"{path}:{line_number(source, match.start())}: {message}")

    if is_support_file:
        errors.extend(validate_support_file(path, source, masked, raw_constructor_matches))

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--support-file",
        type=Path,
        default=DEFAULT_SUPPORT_FILE,
        help="override the centralized fixture path (used by validator self-tests)"
    )
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

    support_file = args.support_file.resolve()
    errors = [error for path in files for error in validate_file(path, support_file)]
    if errors:
        print("SwiftData test ownership validation failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1

    print(f"SwiftData test ownership validation passed ({len(files)} files).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
