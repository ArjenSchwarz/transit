# T-1734 queued independent verification

Prepared source checkpoint: `b9d65b9e483ea59d65ed458851132184dab1331f`, on `T-1734/typed-task-links`. Containment's `3194e5a64dedb004dbfca3666bf590a552b676ee` is consumed as `e1c1ac4`; fixture lint correction is `d2cc0c6`. The final documentation commit adds no executable source. Record actual HEAD in each run's evidence.

Static evidence: development configuration/ownership/source guards and strict SwiftLint pass, 406 files and zero violations; helper Python AST parse passes. Delivered manifest hashes match except the intentional fixture-only lint correction. MCP/read/write, models and TestModelContainer remain unchanged by containment integration. No compiler probes, app builds, codesign preflight, host launches or tests have run on this combined source.

T-2383 holds the exclusive heavy-test slot. Execute the following only after the parent releases that slot to T-1734. Existing conditional implementation approval remains sufficient; this is scheduling coordination, not a new product approval. Use per-command escalation when required by the execution sandbox; never change global permissions. Stop at any offline, build, signature, host-smoke or preflight failure. Preserve logs and artifacts locally. Do not send routine phone reports.

## Exact future command sequence

Run from this checkout in one shell after slot handoff. Fresh private paths prevent reusing another owner's artifacts. Locked package flags fail if required local package inputs are unavailable; stop and report that blocker rather than resolving new versions. These commands do not modify main, activate clients, initialize a CloudKit schema or mutate live task data.

```sh
set -euo pipefail
cd /Users/arjen/Documents/Codex/2026-10-03/task-6/transit-t1734
test -z "$(git status --porcelain)"
test "$(git branch --show-current)" = T-1734/typed-task-links
T1734_RUN_ROOT=$(mktemp -d /tmp/t1734-independent.XXXXXX)
git rev-parse HEAD > "$T1734_RUN_ROOT/source-head.txt"

# Offline probes: synthetic stores with the owner runner's network/live denial.
make test-development-isolation DERIVED_DATA="$T1734_RUN_ROOT/offline"

# Dedicated signed development host: preflight precedes its one smoke case.
make test-isolated-host-smoke \
  DERIVED_DATA="$T1734_RUN_ROOT/cache" \
  SMOKE_DERIVED_DATA="$T1734_RUN_ROOT/smoke"

# Fresh shared Debug unit-test bundle containing the new migration suite.
T1734_UNIT="$T1734_RUN_ROOT/unit"
make prepare-cache-dirs DERIVED_DATA="$T1734_UNIT"
XDG_CACHE_HOME="$T1734_UNIT/Caches" \
TMPDIR="$T1734_UNIT/tmp" \
SWIFTPM_MODULECACHE_OVERRIDE="$T1734_UNIT/Caches/org.swift.swiftpm" \
xcodebuild build-for-testing \
  -project Transit/Transit.xcodeproj -scheme Transit -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -jobs 2 \
  -parallel-testing-enabled NO -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile -derivedDataPath "$T1734_UNIT" \
  CLANG_MODULE_CACHE_PATH="$T1734_UNIT/ModuleCache.noindex" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=

# Fail-closed signature, identity, entitlements, mode and exact-host checks.
# Produces a new run file with only the verified unit target and suite.
python3 tests/typed-task-links/prepare_unit_run.py "$T1734_UNIT/Build/Products"

# Prospective RED may return nonzero. Capture that status and inspect xcresult.
T1734_TEST_STATUS=0
xcodebuild test-without-building \
  -xctestrun "$T1734_UNIT/Build/Products/T1734Migration.xctestrun" \
  -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
  -only-testing:TransitTests/TaskLinkMigrationTests \
  -resultBundlePath "$T1734_UNIT/Build/Products/T1734Migration.xcresult" \
  || T1734_TEST_STATUS=$?
printf '%s\n' "$T1734_TEST_STATUS" > "$T1734_RUN_ROOT/migration-exit-status.txt"
```

The helper requires `me.nore.ig.Transit.development`, development signing, no iCloud/push/App Group entitlements, `TRANSIT_PERSISTENCE_MODE=unit-test`, and the exact preflighted host. It supplies startup smoke attestation and excludes UI targets. The dedicated smoke must also establish memory-only host persistence, disabled CloudKit counter adapters and private sidecars. `TransitDevelopment` is not the unit-test scheme.

## Expected focused inventory and interpretation

Two source declarations produce **three anticipated expanded cases**:

1. `defaultSchemaRegistersCloudCompatibleLinkEntity(name:)`, parameter `TaskLinkOccurrence`.
2. The same declaration, parameter `TaskLinkRemovalEvidence`.
3. `preFeatureDiskBaselinePreservesRawFieldsAndReceiptBytes`, synthetic six-entity saved-state control.

Inspect the xcresult for actual discovery, executed cases, individual outcomes and any unexpected suite. Two missing-model assertion failures are prospective registration-capability RED; the control is expected to pass, but neither outcome is claimed before execution. Compilation failure, crash or zero tests is not behavioral RED. A failing saved-state control is a prerequisite problem to diagnose before graph work.

The disk control observes a fresh context in a retained container. It does not prove a closed-store schema upgrade. Process-separated seed/upgrade migration, development CloudKit compatibility and remaining approved task1 coverage stay outstanding. Task1 remains incomplete even if this initial run yields its expected outcomes. Migration task2, atomic-save task4, bounded-capture task8 and later graph/write integration retain their approved gates. No production graph models or shared graph/write APIs are introduced by this preparation.

Live Transit mutations, client activation, production schema promotion and deployment remain held. Foundation ownership and canonical main/`.kiro` are unchanged.
