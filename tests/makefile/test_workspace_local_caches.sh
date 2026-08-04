#!/usr/bin/env bash
# Regression test for T-1628: every source-building xcodebuild target must
# keep Clang modules and SwiftPM manifest diagnostics/cache writes workspace-local.
#
# `-clonedSourcePackagesDirPath` and `-packageCachePath` are deliberately absent:
# their subdirectory values prevent normal xcodebuild package resolution. Xcode
# owns SourcePackages below -derivedDataPath. This guard checks the supported
# controls instead, without invoking xcodebuild.

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

workspace_root="$(pwd)"
workspace_cache="$workspace_root/DerivedData/Caches"
workspace_tmp="$workspace_root/DerivedData/tmp"
manifest_module_cache="$workspace_cache/org.swift.swiftpm"
clang_module_cache="$workspace_root/DerivedData/ModuleCache.noindex"

assert_workspace_path() {
    local target="$1"
    local variable="$2"
    local expected="$3"
    local commands="$4"
    local value_line

    value_line="$(printf '%s\n' "$commands" | grep -oE "${variable}=[^[:space:]]+" | head -1 || true)"
    [ -n "$value_line" ] || fail "$target does not set $variable"
    [ "$value_line" = "${variable}=${expected}" ] \
        || fail "$target sets $variable to ${value_line#${variable}=}, not $expected"
    pass "$target sets $variable inside the workspace"
}

assert_xcodebuild_setting() {
    local target="$1"
    local setting="$2"
    local commands="$3"
    local xcodebuild_arguments

    xcodebuild_arguments="${commands#*xcodebuild }"
    [ "$xcodebuild_arguments" != "$commands" ] \
        || fail "$target does not invoke xcodebuild"
    printf '%s\n' "$xcodebuild_arguments" | grep -Fq -- "$setting" \
        || fail "$target does not pass $setting as an xcodebuild build setting"
    pass "$target passes $setting as an xcodebuild build setting"
}

assert_cache_controls() {
    local target="$1"
    local commands="$2"

    printf '%s\n' "$commands" | grep -Fq -- 'set -o pipefail;' \
        || fail "$target does not enable pipefail before its xcodebuild pipeline"
    printf '%s\n' "$commands" | grep -Fq -- '-derivedDataPath ./DerivedData' \
        || fail "$target does not pass -derivedDataPath ./DerivedData"
    assert_xcodebuild_setting "$target" "CLANG_MODULE_CACHE_PATH=$clang_module_cache" "$commands"
    assert_workspace_path "$target" XDG_CACHE_HOME "$workspace_cache" "$commands"
    assert_workspace_path "$target" TMPDIR "$workspace_tmp" "$commands"
    assert_workspace_path "$target" SWIFTPM_MODULECACHE_OVERRIDE "$manifest_module_cache" "$commands"

    printf '%s\n' "$commands" | grep -Fq -- '-clonedSourcePackagesDirPath' \
        && fail "$target must omit -clonedSourcePackagesDirPath so xcodebuild can resolve packages"
    printf '%s\n' "$commands" | grep -Fq -- '-packageCachePath' \
        && fail "$target must omit -packageCachePath so xcodebuild can resolve packages"
    pass "$target uses supported cache controls and preserves package resolution"
}

make_dry_run() {
    local target="$1"

    # DEVICE_ID is a recursively-expanded $(shell ...) value. Override it for
    # install so make -n only prints the recipe and never enumerates devices.
    if [ "$target" = "install" ]; then
        make -n "$target" DEVICE_ID=cache-guard-device-id 2>/dev/null
    else
        make -n "$target" 2>/dev/null
    fi
}

# Use make's dry-run mode so we get resolved command lines without executing.
for target in build-ios build-macos test-quick test test-ui install archive clean; do
    commands="$(make_dry_run "$target")"
    assert_cache_controls "$target" "$commands"
done

prepare_cmds="$(make -n prepare-cache-dirs 2>/dev/null)"
for path in \
    ./DerivedData/Caches \
    ./DerivedData/tmp \
    ./DerivedData/Caches/org.swift.swiftpm \
    ./DerivedData/ModuleCache.noindex; do
    printf '%s\n' "$prepare_cmds" | grep -Fq -- "$path" \
        || fail "prepare-cache-dirs does not create $path"
done
pass "prepare-cache-dirs creates every workspace-local cache directory"

clean_cmds="$(make -n clean 2>/dev/null)"
printf '%s\n' "$clean_cmds" | grep -Fq -- 'rm -rf ./DerivedData build' \
    || fail "clean does not remove workspace-local cache artifacts"
pass "clean removes workspace-local cache artifacts"

echo
echo "All workspace-local cache redirection checks passed."
