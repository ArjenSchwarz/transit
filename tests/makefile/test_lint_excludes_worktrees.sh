#!/usr/bin/env bash
# Regression test for T-1347: `make lint` must not scan Claude worktrees or
# generated build artifacts.
#
# `run_silent make lint` from the repository root scanned the untracked
# `.claude/worktrees/<name>` checkouts and their nested DerivedData/SwiftPM
# package checkouts. The root `.swiftlint.yml` only excluded `.codex-cache`,
# `DerivedData`, and `specs`, so paths like `.claude/worktrees/.../DerivedData/...`
# were linted — in one run producing 41,466 violations across 3,239 files of
# mostly generated/third-party code.
#
# This test creates a throwaway Swift file with guaranteed violations inside a
# fake `.claude/worktrees/.../DerivedData` tree, runs SwiftLint with the repo's
# config, and verifies that SwiftLint does NOT report any violations from that
# path. It also asserts the same for `.build` and `build` artifact trees.
#
# The test does not depend on the (separately tracked) state of the real
# project source: it only asserts that excluded paths are never linted.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "SKIP: swiftlint not installed"
    exit 0
fi

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

pass() {
    echo "PASS: $*"
}

# Bad.swift triggers opening_brace and other style rules deterministically.
BAD_SWIFT_CONTENT=$'class  Bad{\nvar x=1\nfunc y( ){return}\n}\n'

# Track artifacts we create so we can clean them up even on failure.
created_paths=()
cleanup() {
    for p in "${created_paths[@]:-}"; do
        [ -n "$p" ] && rm -rf "$p"
    done
}
trap cleanup EXIT

# Create a guaranteed-bad Swift file at $1 (registering its top dir $2 for cleanup).
plant() {
    local file="$1" top="$2"
    [ -e "$top" ] || created_paths+=("$top")
    mkdir -p "$(dirname "$file")"
    printf '%s' "$BAD_SWIFT_CONTENT" > "$file"
}

CACHE="$(mktemp -d)"
created_paths+=("$CACHE")

# 1. Claude worktree with nested DerivedData/SwiftPM checkout — the exact shape
#    described in T-1347.
plant ".claude/worktrees/regression-wt/DerivedData/SourcePackages/checkouts/Dep/Bad.swift" ".claude"

# 2. SwiftPM build output in the current checkout.
plant ".build/checkouts/Dep/Bad.swift" ".build"

# 3. Xcode build output in the current checkout.
plant "build/Bad.swift" "build"

# Run SwiftLint exactly as `make lint` does (same flags), capturing output.
# Use a private cache so we don't pollute the workspace cache.
lint_out="$(swiftlint lint --strict --cache-path "$CACHE" 2>&1 || true)"

for excluded in ".claude/worktrees" ".build/" "build/Bad.swift"; do
    if echo "$lint_out" | grep -q "$excluded"; then
        echo "$lint_out" | grep "$excluded" | head -3 >&2
        fail "SwiftLint reported violations under an excluded path: $excluded"
    fi
done
pass "SwiftLint does not lint .claude worktrees or build-artifact trees"

# Sanity check: the planted file really does contain lint violations, so the
# assertion above is meaningful (it excludes a path with real violations, not an
# empty/clean file). Copy it outside the repo so no config exclusion applies and
# lint it with the default (no-config) ruleset.
sanity_dir="$(mktemp -d)"
created_paths+=("$sanity_dir")
printf '%s' "$BAD_SWIFT_CONTENT" > "$sanity_dir/Bad.swift"
sanity_out="$( cd "$sanity_dir" && swiftlint lint --no-cache 2>&1 || true )"
echo "$sanity_out" | grep -q "Bad.swift" \
    || fail "sanity: planted file did not produce violations — test would be vacuous"
pass "sanity: planted files genuinely contain violations"

echo
echo "All lint-exclusion checks passed."
