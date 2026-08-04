# Bugfix Report: Test-Quick Workspace-Local Cache Regression

**Date:** 2026-08-04
**Status:** Fixed
**Transit ticket:** T-1628

## Description of the Issue

`make test-quick` could fail before compiling tests in restricted-home agent
sessions. SwiftPM manifest compilation attempted to write diagnostics below
`~/Library/Caches/org.swift.swiftpm`, and Clang module loading could write below
`~/.cache/clang/ModuleCache`.

The accompanying shell guard was also stale: it required
`-clonedSourcePackagesDirPath` and `-packageCachePath`, although the Makefile
correctly documented that those subdirectory arguments disable Xcode's ordinary
package-resolution path.

**Reproduction steps:**
1. Run `bash tests/makefile/test_workspace_local_caches.sh`.
2. Observe the stale requirement for `-clonedSourcePackagesDirPath` fail despite
   the documented intentional omission.
3. Run `make test-quick` in an environment that disallows user-global cache
   writes.
4. Observe SwiftPM manifest diagnostics or Clang module-cache permission errors
   before test execution.

**Impact:** Sandbox and agent invocations could not reliably resolve packages
or begin the fast macOS test suite. The stale guard both failed locally and
would have encouraged restoring package-resolution-breaking flags.

## Investigation Summary

- **Symptoms examined:** T-1628's reported failures at
  `~/.cache/clang/ModuleCache/Swift-*.swiftmodule` and
  `~/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading/*.dia`; the
  current guard's failure for the intentionally omitted package flags.
- **Code inspected:** `Makefile`,
  `tests/makefile/test_workspace_local_caches.sh`, the T-1241 history, and
  `docs/agent-notes/project-structure.md`.
- **Hypotheses tested:** `xcodebuild -showBuildSettings` showed that exporting
  `CLANG_MODULE_CACHE_PATH` does not change Xcode's
  `CLANG_MODULE_CACHE_PATH` build setting. Passing it as a command-line build
  setting does. The installed `swift-package` binary contains
  `SWIFTPM_MODULECACHE_OVERRIDE`, confirming that SwiftPM supports the manifest
  module-cache override.

## Discovered Root Cause

T-1241 exported `CLANG_MODULE_CACHE_PATH` as a process environment variable,
but Xcode consumes it as a build setting and therefore retained its default
user-global module cache. It also did not set SwiftPM's
`SWIFTPM_MODULECACHE_OVERRIDE`, leaving manifest compiler modules and `.dia`
diagnostics under the user cache. The regression shell script had not been
updated when the deliberately harmful package-cache flags were removed.

**Defect type:** Misconfigured tool integration and stale regression coverage.

**Why it occurred:** The first cache redirection treated all cache controls as
environment variables or xcodebuild flags without distinguishing Xcode build
settings from SwiftPM environment overrides. A later package-resolution repair
changed the Makefile but not the guard or project note.

**Contributing factors:** A restricted synthetic `HOME` cannot fully reproduce
the harness's Xcode sandbox policy, so the structural guard must assert the
actual supported controls as well as runtime package resolution.

## Resolution for the Issue

**Changes made:**
- `Makefile` - passes `CLANG_MODULE_CACHE_PATH` as an xcodebuild build-setting
  argument; exports `SWIFTPM_MODULECACHE_OVERRIDE` to a workspace-local
  directory; retains `XDG_CACHE_HOME`, `TMPDIR`, and `-derivedDataPath`; removes
  unused package-cache directory setup.
- `tests/makefile/test_workspace_local_caches.sh` - replaces obsolete package
  flag requirements with assertions for the supported controls, their exact
  workspace-local paths, the intentional package-flag omission, all relevant
  source-building targets, preparation, and cleanup.
- `docs/agent-notes/project-structure.md` - documents the build-setting versus
  environment-variable distinction and why package flags remain absent.

**Approach rationale:** `-derivedDataPath` lets Xcode own package checkouts and
repository state below the workspace without disrupting resolution.
`CLANG_MODULE_CACHE_PATH=<path>` is the supported xcodebuild build-setting that
produces Clang's `-fmodules-cache-path`; `SWIFTPM_MODULECACHE_OVERRIDE` handles
SwiftPM manifest compilation and diagnostics before an Xcode target builds.

**Alternatives considered:**
- Re-add `-clonedSourcePackagesDirPath` and `-packageCachePath` - rejected:
  their subdirectory paths prevent normal Xcode package resolution.
- Keep `CLANG_MODULE_CACHE_PATH` as an environment variable - rejected:
  `xcodebuild -showBuildSettings` proved it leaves Xcode's module-cache setting
  at its user-global default.
- Redirect the full `HOME` - rejected: this is broader than cache isolation and
  would change credentials, tool configuration, and other unrelated behavior.

## Regression Test

**Test file:** `tests/makefile/test_workspace_local_caches.sh`

**What it verifies:** Every relevant Makefile target uses workspace-local
`XDG_CACHE_HOME`, `TMPDIR`, `SWIFTPM_MODULECACHE_OVERRIDE`, and
`CLANG_MODULE_CACHE_PATH`; the latter appears as an xcodebuild build-setting;
`-derivedDataPath` is retained; package-resolution-breaking flags are absent;
and preparation plus cleanup cover the local directories.

**Run command:** `bash tests/makefile/test_workspace_local_caches.sh`

## Affected Files

| File | Change |
|---|---|
| `Makefile` | Correct cache controls and local directories. |
| `tests/makefile/test_workspace_local_caches.sh` | Supported-control regression coverage. |
| `docs/agent-notes/project-structure.md` | Updated cache configuration guidance. |
| `CHANGELOG.md` | Unreleased T-1628 fix entry. |
| `specs/bugfixes/test-quick-workspace-local-cache-regression/report.md` | Investigation and resolution record. |

## Verification

**Automated:**
- [x] The rewritten guard failed before the Makefile fix with
  `build-ios does not set SWIFTPM_MODULECACHE_OVERRIDE`.
- [x] `bash tests/makefile/test_workspace_local_caches.sh` passes after the
  fix.
- [x] `make lint` passes.
- [x] A clean restricted-HOME unsigned `make build` passes for iOS Simulator
  and macOS, including package resolution.
- [x] A restricted-HOME `make clean` succeeds and removes `DerivedData`.
- [ ] `make test-quick` cannot complete on this machine: its unsigned macOS
  test runner aborts before bootstrapping. With Xcode signing disabled for
  validation, compilation and package resolution complete and Clang receives
  the workspace-local `-fmodules-cache-path`.

**Manual verification:**
- [x] `xcodebuild -showBuildSettings` resolves the explicit
  `CLANG_MODULE_CACHE_PATH` to the workspace path rather than its default
  user-global path.
- [x] The restricted-HOME build log shows package checkout and Clang commands
  writing under `DerivedData`, with no user-cache permission errors.

## Prevention

- Treat Xcode build settings and SwiftPM environment overrides as separate
  interfaces; do not assume an environment variable configures both tools.
- Keep dry-run Makefile guards focused on documented, supported controls and
  assert intentional omissions as well as required options.
- Run the cache guard whenever adding a source-building xcodebuild target.

## Related

- Transit ticket T-1628
- T-1241, the original workspace-cache redirection change
