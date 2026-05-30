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

# This test relies on `.claude/` being a tracked directory in the checkout so
# that plant() registers only the throwaway `.claude/worktrees` subtree for
# cleanup, never the tracked prefix. Assert the assumption explicitly so a
# fresh checkout that lacks `.claude/` fails loudly instead of silently
# rm -rf'ing a directory the test created at the tracked prefix.
[ -d .claude ] || fail "expected tracked '.claude/' directory in checkout root"

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

# Create a guaranteed-bad Swift file at $1, registering the highest directory we
# actually create for cleanup. We walk up from the file's directory to the first
# ancestor that does NOT already exist in the repo, so a tracked prefix (e.g.
# `.claude/`) is left untouched while the throwaway subtree is removed on exit.
plant() {
    local file="$1"
    local dir
    dir="$(dirname "$file")"

    # Find the topmost not-yet-existing ancestor of the target directory.
    local newest="$dir"
    local parent
    while parent="$(dirname "$newest")"; [ "$parent" != "$newest" ] && [ ! -e "$parent" ]; do
        newest="$parent"
    done
    [ -e "$newest" ] || created_paths+=("$newest")

    mkdir -p "$dir"
    printf '%s' "$BAD_SWIFT_CONTENT" > "$file"
}

CACHE="$(mktemp -d)"
created_paths+=("$CACHE")

# 1. Claude worktree with nested DerivedData/SwiftPM checkout — the exact shape
#    described in T-1347. `.claude` itself is tracked, so plant() only registers
#    the throwaway `.claude/worktrees` subtree for cleanup.
plant ".claude/worktrees/regression-wt/DerivedData/SourcePackages/checkouts/Dep/Bad.swift"

# 2. SwiftPM build output in the current checkout.
plant ".build/checkouts/Dep/Bad.swift"

# 3. Xcode build output in the current checkout.
plant "build/Bad.swift"

# Run SwiftLint exactly as `make lint` does (same flags), capturing output.
# Use a private cache so we don't pollute the workspace cache.
lint_out="$(swiftlint lint --strict --config "$ROOT/.swiftlint.yml" --cache-path "$CACHE" 2>&1 || true)"

for excluded in "\.claude/worktrees/" "/\.build/" "/build/Bad\.swift"; do
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
