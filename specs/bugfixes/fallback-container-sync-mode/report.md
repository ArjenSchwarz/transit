# Bugfix Report: Fallback Container Sync Mode

**Date:** 2026-08-05
**Status:** Implemented — full unit-test execution blocked by unrelated concurrent changes

## Description of the Issue

`TransitApp` recorded the requested CloudKit mode before `ContainerFactory` attempted to open the primary SwiftData store. If the primary store failed, `ContainerFactory` switched to an in-memory `cloudKitDatabase: .none` container, but the precomputed mode stayed active. Task and milestone allocators could therefore access the real private CloudKit display-ID counters for records that would disappear at restart.

**Reproduction steps:**
1. Launch Transit with iCloud Sync enabled while forcing primary `ModelContainer` construction to fail.
2. Continue in the interactive temporary-storage UI.
3. Create a task or milestone, or trigger lifecycle/connectivity promotion.
4. Observe the fallback record can consume a permanent CloudKit display ID despite being ephemeral.

**Impact:** Temporary interactive data can advance durable shared counters and produce permanent IDs for data that cannot persist. Automation mutations remain independently rejected by existing fallback-storage guards.

## Investigation Summary

- **Symptoms examined:** Container fallback changes the actual persistence mode after `SyncManager` had already supplied `cloudSyncActive` to both allocators and connectivity wiring.
- **Code inspected:** `TransitApp`, `ContainerFactory`, `SyncManager`, `DisplayIDAllocator`, `MilestoneService`, scene promotion, and existing fallback/disabled-sync tests.
- **Hypotheses tested:** The allocation and promotion layers already fail closed when constructed inactive. The missing behavior is deriving that inactive mode from the factory outcome and recording it back to `SyncManager`.

## Discovered Root Cause

The bootstrap sequence captured `syncManager.isCloudSyncActive` before `ContainerFactory.makeContainer(...)` returned. A failed outcome means the live container is in-memory and CloudKit-free, but no subsequent derivation reset the active mode.

**Defect type:** Bootstrap state-ordering logic error.

**Why it occurred:** Configuration preference and live container outcome were treated as equivalent even though the fallback path can replace the requested configuration.

**Contributing factors:** Existing T-1797 guards covered preference-disabled launches, while T-1818/T-1836 covered automation writes in fallback storage; neither connected a real fallback outcome to allocator construction.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/CloudSyncBootstrap.swift` - Added a testable derivation: CloudKit is effective only when it was requested and `ContainerFactory` did not fall back.
- `Transit/Transit/TransitApp.swift` - Derives this effective mode after container creation, records it in `SyncManager`, and supplies it to both display-ID allocators and connectivity promotion wiring.
- `Transit/TransitTests/SyncDisabledGatingTests.swift` - Adds a real injected-fallback regression covering task/milestone interactive writes, lifecycle promotion, and both untouched counter stores; adds healthy active/inactive derivation coverage.

**Approach rationale:** Existing allocators and promotion routines already fail closed before counter access when `isCloudSyncActive` is false. Correcting the one bootstrap value makes every existing creation, scene, connectivity, and maintenance guard observe the actual live container mode without changing interactive fallback writes or the separate automation availability gate.

**Alternatives considered:**
- Add a second fallback flag to every allocator and promotion caller - rejected because it duplicates the established active-mode invariant and risks divergent gating.
- Block interactive fallback writes - rejected because the app deliberately keeps warned interactive temporary storage usable; only automation writes are prohibited.

## Regression Test

**Test file:** `Transit/TransitTests/SyncDisabledGatingTests.swift`
**Test name:** `fallbackOutcomeDisablesCounterUseWhileInteractiveWritesRemainAvailable`

**What it verifies:** A real injected `ContainerFactory` fallback forces the effective active mode off; task and milestone interactive writes remain allowed but provisional, and allocation/promotion never touches either counter store. A companion test preserves active and preference-disabled modes after a healthy factory outcome.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/TransitApp.swift` | Derive and record the effective active sync mode after container creation. |
| `Transit/Transit/Services/CloudSyncBootstrap.swift` | Testable derivation of the active CloudKit mode from the factory outcome. |
| `Transit/TransitTests/SyncDisabledGatingTests.swift` | Real-fallback allocator and lifecycle gating regression tests. |

## Verification

**Automated:**
- [x] `make build-macos` passes.
- [x] `make lint` passes.
- [ ] `make test-quick` is blocked before test execution by concurrently edited, untracked `Transit/TransitTests/AddTaskSaveLifecycleTests.swift`: Swift Testing rejects mutating `beginSave`, `cancelForDisappearance`, and `completeSave` calls inside `#expect` autoclosures. The T-1936 test source compiles without diagnostics before this unrelated failure stops the target.

**Manual verification:**
- The regression builds a real injected `ContainerFactory` fallback, derives inactive mode, creates interactive task/milestone records, invokes both promotion APIs, and asserts both records remain provisional with zero counter-store access. Runtime execution remains blocked by the unrelated test-host compilation failure above.

## Prevention

- Treat a requested persistence configuration and the mode of the container actually in use as separate bootstrap values.
- Derive CloudKit-dependent service wiring only after the `ContainerFactory` outcome is known.

## Related

- T-1936
- T-1797, T-1818, T-1836
