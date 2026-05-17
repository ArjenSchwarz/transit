#!/usr/bin/env bash
# Regression test for T-1241: Make build-macos should use workspace-local Xcode caches.
#
# In sandboxed/dev environments, xcodebuild fails when it tries to write to
# user-global caches (~/.cache/clang/ModuleCache, ~/Library/Caches/org.swift.swiftpm).
# The Makefile must redirect every cache path that xcodebuild and its subprocesses
# touch into the workspace.
#
# This test inspects `make -n build-macos` (dry-run) and `make -n clean` output and
# verifies that the required cache-redirection flags and environment variables are
# present. It does not actually build the project.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

pass() {
    echo "PASS: $*"
}

# Use make's dry-run mode so we get the resolved command lines without executing.
build_cmds="$(make -n build-macos 2>/dev/null)"
clean_cmds="$(make -n clean 2>/dev/null)"
test_cmds="$(make -n test-quick 2>/dev/null)"

# 1. SwiftPM clones directory must be workspace-local.
echo "$build_cmds" | grep -q -- '-clonedSourcePackagesDirPath' \
    || fail "build-macos does not pass -clonedSourcePackagesDirPath"
pass "build-macos passes -clonedSourcePackagesDirPath"

# 2. SwiftPM package cache must be workspace-local.
echo "$build_cmds" | grep -q -- '-packageCachePath' \
    || fail "build-macos does not pass -packageCachePath"
pass "build-macos passes -packageCachePath"

# 3. XDG_CACHE_HOME must be redirected so Clang's default module cache
#    (~/.cache/clang/ModuleCache when -fmodules-cache-path is not passed) stays
#    in the workspace.
echo "$build_cmds" | grep -q 'XDG_CACHE_HOME=' \
    || fail "build-macos does not export XDG_CACHE_HOME"
pass "build-macos exports XDG_CACHE_HOME"

# 4. TMPDIR must be redirected so compiler temp diagnostics (*.dia) don't escape
#    the workspace.
echo "$build_cmds" | grep -q 'TMPDIR=' \
    || fail "build-macos does not export TMPDIR"
pass "build-macos exports TMPDIR"

# 5. None of the redirected paths may resolve to a user-global cache location.
#    Workspace-relative absolute paths inside the repo are fine; what we forbid
#    is the well-known global caches (~/.cache, ~/Library/Caches) that triggered
#    the original sandbox failure.
workspace_root="$(pwd)"
for var in XDG_CACHE_HOME TMPDIR; do
    value_line="$(echo "$build_cmds" | grep -oE "${var}=[^ ]+" | head -1 || true)"
    [ -n "$value_line" ] || fail "could not extract $var from build-macos commands"
    value="${value_line#${var}=}"
    case "$value" in
        \$HOME*|\$\{HOME\}*|~*)
            fail "$var resolves to a user-global path: $value"
            ;;
        *.cache|*.cache/*|*Library/Caches|*Library/Caches/*)
            fail "$var resolves to a user-global cache path: $value"
            ;;
    esac
    case "$value" in
        "$workspace_root"/*)
            ;;
        /*)
            fail "$var ($value) is absolute but not inside the workspace ($workspace_root)"
            ;;
    esac
done
pass "build-macos cache paths are workspace-local"

# 6. The clean target must also use the redirected caches so it doesn't fail
#    before the build can run.
echo "$clean_cmds" | grep -q -- '-clonedSourcePackagesDirPath' \
    || fail "clean does not pass -clonedSourcePackagesDirPath"
echo "$clean_cmds" | grep -q -- '-packageCachePath' \
    || fail "clean does not pass -packageCachePath"
echo "$clean_cmds" | grep -q 'XDG_CACHE_HOME=' \
    || fail "clean does not export XDG_CACHE_HOME"
echo "$clean_cmds" | grep -q 'TMPDIR=' \
    || fail "clean does not export TMPDIR"
pass "clean target redirects caches"

# 7. Test targets should also share the redirection so test runs don't regress
#    in sandboxed environments.
echo "$test_cmds" | grep -q -- '-clonedSourcePackagesDirPath' \
    || fail "test-quick does not pass -clonedSourcePackagesDirPath"
echo "$test_cmds" | grep -q 'XDG_CACHE_HOME=' \
    || fail "test-quick does not export XDG_CACHE_HOME"
pass "test-quick redirects caches"

echo
echo "All workspace-local cache redirection checks passed."
