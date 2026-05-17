#!/usr/bin/env bash
# Regression test for T-951: Make SwiftLint use a workspace-local cache.
#
# Verifies that the Makefile's `lint` and `lint-fix` targets pass a
# workspace-local --cache-path to swiftlint, and that the cache directory is
# excluded from version control via .gitignore.
#
# Run from the repository root: bash specs/bugfixes/swiftlint-workspace-local-cache/test_lint_cache_path.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

pass() {
    echo "PASS: $1"
}

# Expected workspace-local cache directory (relative path).
EXPECTED_CACHE_DIR=".swiftlint-cache"

# Use `make -n` to capture the command line as Make would actually invoke it,
# with variable expansion applied. This makes the assertion robust to whether
# the recipe inlines the path or sources it from a variable.
lint_cmd="$(make -n lint 2>/dev/null)"
if ! grep -q -- "swiftlint lint" <<<"$lint_cmd"; then
    fail "`make -n lint` did not show a swiftlint invocation. Output:
$lint_cmd"
fi
if ! grep -q -- "--cache-path[[:space:]]\+$EXPECTED_CACHE_DIR" <<<"$lint_cmd"; then
    fail "`make -n lint` does not pass --cache-path $EXPECTED_CACHE_DIR to swiftlint. Output:
$lint_cmd"
fi
pass "make lint passes --cache-path $EXPECTED_CACHE_DIR"

lint_fix_cmd="$(make -n lint-fix 2>/dev/null)"
if ! grep -q -- "swiftlint lint" <<<"$lint_fix_cmd"; then
    fail "`make -n lint-fix` did not show a swiftlint invocation. Output:
$lint_fix_cmd"
fi
if ! grep -q -- "--cache-path[[:space:]]\+$EXPECTED_CACHE_DIR" <<<"$lint_fix_cmd"; then
    fail "`make -n lint-fix` does not pass --cache-path $EXPECTED_CACHE_DIR to swiftlint. Output:
$lint_fix_cmd"
fi
pass "make lint-fix passes --cache-path $EXPECTED_CACHE_DIR"

# 3. The cache directory must be in .gitignore so it is not committed.
# Match any line that mentions the cache directory; what matters is that the
# path is excluded, not the exact gitignore syntax used.
if ! grep -q '\.swiftlint-cache' .gitignore; then
    fail ".gitignore does not exclude .swiftlint-cache/"
fi
pass ".gitignore excludes .swiftlint-cache/"

echo "All regression checks passed."
