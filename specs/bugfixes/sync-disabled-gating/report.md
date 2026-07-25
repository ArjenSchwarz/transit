# Bugfix Report: Sync-Disabled Gating

**Date:** 2026-07-25
**Status:** Fixed
**Tickets:** T-1797, T-1857

## Description of the Issue

Two halves of the same defect: `SyncManager` conflated the user's sync *preference* with
the CloudKit mode the live `ModelContainer` was actually built with. Nothing in the
codebase tracked the latter, so both directions of the mismatch went unhandled.

### T-1797 — sync-disabled launches still access CloudKit display ID counters

With iCloud Sync off, `TransitApp.init` correctly built the container with
`cloudKitDatabase: .none`, but still constructed CloudKit-backed `DisplayIDAllocator`
instances and wired connectivity/scene promotion unconditionally.

**Reproduction steps:**
1. Turn iCloud Sync off in Settings, quit and reopen Transit.
2. While online, create a task (UI, MCP, or App Intent).
3. The private CloudKit counter record is read and written, and the task is assigned a
   permanent display ID — despite the local store being CloudKit-free.
4. Same via scene activation, connectivity restore, and Data Maintenance's
   counter-advance fence.

**Impact:** High. A user who turned sync off still had Transit reaching into their private
CloudKit database and mutating a shared counter. It also contradicted
`specs/transit-v1/implementation.md`, which stated provisional IDs accumulate while sync
is disabled, and burned counter values against a store that would never sync them.

### T-1857 — iCloud Sync toggle leaves live CloudKit sync active

**Reproduction steps:**
1. Launch Transit with iCloud Sync enabled.
2. Turn iCloud Sync off in Settings.
3. Create or edit a task before relaunching.
4. The live container is still CloudKit-backed and uploads the change.

**Impact:** High. A privacy/data-control toggle silently did not take effect, with nothing
in the UI saying so.

## Investigation Summary

- **Symptoms examined:** CloudKit counter access with a `.none` container; sync continuing
  after the toggle flipped.
- **Code inspected:** `SyncManager.swift`, `TransitApp.swift` (container + allocator +
  connectivity wiring), `DisplayIDAllocator.swift`, `TaskService.swift` /
  `MilestoneService.swift` creation and promotion paths,
  `DisplayIDMaintenanceService.swift`, `ScenePhaseModifier.swift`,
  `Views/Settings/SettingsView.swift`, `specs/transit-v1/{requirements,design,implementation}.md`.
- **Hypotheses tested and ruled out:**
  - *The container config is wrong when sync is off* — ruled out;
    `makeModelConfiguration` already returned `.none` correctly.
  - *Gating on the live `isSyncEnabled` preference is sufficient* — ruled out. It gives the
    wrong answer in both toggle directions: after turning sync off mid-launch the
    container is still syncing, so allocation should keep issuing permanent IDs; after
    turning it on mid-launch the store is still local-only, so allocation must not burn
    counter values. Only the launch-time active mode is coherent.
  - *Guard each promotion call site* — ruled out in favour of a single chokepoint inside
    `DisplayIDAllocator`, which covers every caller including future ones.

## Discovered Root Cause

`SyncManager` exposed exactly one boolean, `isSyncEnabled`, and it meant two different
things depending on when you asked. The CloudKit mode of a SwiftData `ModelContainer` is
fixed at creation, so from the moment the toggle moves the preference no longer describes
what the container does — but no other value described it either.

**Defect type:** Missing state distinction (one variable serving two lifetimes), leading to
a missing guard.

**Why it occurred:** Decision 19 planned a runtime sync pause via
`NSPersistentStoreDescription.cloudKitContainerOptions = nil`. It was never implemented.
What shipped selected the mode once at launch, which made the preference and the active
mode diverge — but the design documents still described immediate runtime disable, so
neither the missing counter gate (T-1797) nor the missing UI disclosure (T-1857) looked
like a gap against the spec.

**Contributing factors:** The display ID counter is deliberately stored in SwiftData's own
CloudKit zone (Decision 13), so it is reached through the raw CloudKit API rather than
through the container — meaning the container's `.none` setting could not gate it
implicitly.

## Resolution for the Issue

Approved design decision on T-1857 (Decision 21, superseding Decision 19): do **not**
recreate or reinject the `ModelContainer` at runtime. Keep the mode launch-scoped, gate
CloudKit access on it, and disclose the restart requirement in the UI.

**Changes made:**

- `Services/SyncManager.swift` — added `isCloudSyncActive` (the mode the live container was
  built with, fixed for the process) alongside `isSyncEnabled` (the preference), plus
  `syncChangeRequiresRestart` and `recordActiveCloudSync(_:)`. `makeModelConfiguration`
  records the mode it selects. `setSyncEnabled` deliberately leaves the active mode alone.
  `initializeCloudKitSchemaIfNeeded` now gates on the active mode.
- `Services/DisplayIDAllocator.swift` — new `isCloudSyncActive` stored property and
  `Error.cloudSyncInactive`. `allocateNextID` throws before the allocation gate and before
  any store access; `promoteProvisionalTasks` returns before its fetch.
- `Services/CloudKitCounterStore.swift` — extracted from `DisplayIDAllocator.swift`
  unchanged (file-length limit).
- `Services/MilestoneService.swift` — `promoteProvisionalMilestones` returns early when the
  allocator is not CloudKit-backed.
- `Services/DisplayIDMaintenanceService.swift` — the counter-advance fence takes the
  allocator instead of the raw store and reports a clear `counterAdvanceFailed` warning
  instead of touching CloudKit.
- `TransitApp.swift` — records the active mode (including `false` for test/UI-test hosts,
  which bypass `makeModelConfiguration`), passes it to both allocators, and only wires
  `connectivityMonitor.onRestore` when the container is CloudKit-backed.
- `Views/Settings/SettingsView.swift` — caption under the iCloud Sync toggle on both
  platforms: always states the change takes effect after quitting and reopening Transit,
  escalating to a pending-restart notice while preference and active mode disagree.

**Approach rationale:** Gating inside `DisplayIDAllocator` is one chokepoint that every
caller — `TaskService`, `MilestoneService`, `DisplayIDMaintenanceService`, scene and
connectivity promotion — passes through, so no call site can forget it. Both creation
paths already fall back to a provisional ID on any allocation error, so the new error case
needed no changes there. Gating on the launch-time active mode rather than the live
preference is what keeps both toggle directions coherent.

**Alternatives considered:**
- **Recreate the `ModelContainer` on toggle** — rejected per the approved decision; the
  blast radius covers all views, the MCP server, and in-flight automation writes.
- **Pause sync via `cloudKitContainerOptions = nil`** (the original Decision 19 plan) —
  rejected; reaches through SwiftData to unsupported Core Data-level API, and was never
  implemented.
- **Gate on the live `isSyncEnabled` preference** — rejected; wrong in both directions (see
  Investigation Summary).
- **Guard at each promotion call site** — rejected; more places to forget, and it would not
  have covered the maintenance counter-advance fence.

## Regression Test

**Test file:** `Transit/TransitTests/SyncDisabledGatingTests.swift` (11 tests)

The core assertion is that the counter store is *untouched*, not merely unsuccessful.
`InMemoryCounterStore` gained `loadAttemptCount` and `wasNeverAccessed` so the tests can
assert on zero access rather than on an error being thrown.

| Test | Verifies |
|------|----------|
| `allocateNextID_withCloudSyncInactive_throwsWithoutTouchingCounterStore` | Allocation throws `.cloudSyncInactive` with zero store access |
| `allocateNextID_withCloudSyncActive_stillAllocates` | Control: the gate does not break normal allocation |
| `promoteProvisionalTasks_withCloudSyncInactive_leavesTasksProvisional` | Scene/connectivity task promotion is inert |
| `promoteProvisionalMilestones_withCloudSyncInactive_leavesMilestonesProvisional` | Milestone promotion is inert |
| `createTask_withCloudSyncInactive_assignsProvisionalID` | Task creation stays provisional, counter untouched |
| `createMilestone_withCloudSyncInactive_assignsProvisionalID` | Milestone creation stays provisional, counter untouched |
| `reassignDuplicates_withCloudSyncInactive_neverTouchesCounterStore` | Maintenance counter-advance fence reports instead of reaching CloudKit |
| `makeModelConfiguration_recordsTheModeTheContainerWasBuiltWith` | Active mode is recorded from the config actually built |
| `setSyncEnabled_doesNotChangeTheActiveMode_andFlagsRestartRequired` | Preference flips, active mode does not, restart notice raised |
| `settingsFootnote_alwaysStatesRestartScope_andEscalatesWhenPending` | The toggle copy never implies immediate effect |
| `recordActiveCloudSync_overridesTheInferredMode` | Test/UI-test hosts can record a CloudKit-free container |

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/SyncManager.swift` | Split preference from active mode; added `syncChangeRequiresRestart`, `recordActiveCloudSync` |
| `Transit/Transit/Services/DisplayIDAllocator.swift` | `isCloudSyncActive` gate on allocation and promotion; `Error.cloudSyncInactive` |
| `Transit/Transit/Services/CloudKitCounterStore.swift` | New file — extracted verbatim from `DisplayIDAllocator.swift` |
| `Transit/Transit/Services/MilestoneService.swift` | Early return in `promoteProvisionalMilestones` |
| `Transit/Transit/Services/DisplayIDMaintenanceService.swift` | Counter-advance fence gated, reports a warning |
| `Transit/Transit/TransitApp.swift` | Records active mode, passes it to allocators, gates `onRestore` wiring |
| `Transit/Transit/Views/Settings/SettingsView.swift` | Restart-scope disclosure under the sync toggle (iOS + macOS) |
| `Transit/TransitTests/SyncDisabledGatingTests.swift` | New — 11 regression tests |
| `Transit/TransitTests/TestModelContainer.swift` | `InMemoryCounterStore` tracks loads; `wasNeverAccessed` |
| `specs/transit-v1/requirements.md` | 12.7 / 12.9 / 15.4 restated as restart-scoped; new 15.7 |
| `specs/transit-v1/design.md` | Sync toggle section rewritten; provisional-ID error case updated |
| `specs/transit-v1/implementation.md` | Architecture impact, potential issues, known limitations updated |
| `specs/transit-v1/decision_log.md` | Decision 19 superseded; Decision 21 added |

## Verification

**Automated:**
- [x] Regression tests pass (11/11)
- [x] Full macOS unit suite passes — 1278 passed, 0 failed, 166 suites (`make test-quick`)
- [x] SwiftLint clean — 0 violations in 283 files (`make lint`)

**Not run:** `make test` / `make test-ui` (iOS Simulator suites) were skipped for this run by
explicit decision. No UI test references the sync toggle or Settings general section.

**Red state confirmed before the fix:** the new tests failed to compile against the
pre-fix API (`isCloudSyncActive`, `Error.cloudSyncInactive`, `recordActiveCloudSync` all
absent), which is precisely the missing gate.

## Prevention

- **When a value's meaning depends on when you read it, make it two values.** One boolean
  covering both "what the user wants" and "what the process is doing" is the whole root
  cause here.
- **Gate at the chokepoint, not the call sites.** The allocator is the only door to the
  counter; guarding there covers callers that do not exist yet.
- **Assert on absence of access, not on error results.** `wasNeverAccessed` is what makes
  these tests actually prove the T-1797 claim — a test that only checks for a thrown error
  would pass against an implementation that called CloudKit and failed.
- **A design document describing unimplemented behaviour hides bugs.** Decision 19 had
  described a runtime sync pause since 2026-02; because the docs asserted it, neither
  missing piece read as a gap. Superseded decisions should be marked as soon as the
  implementation diverges.

## Related

- Transit tickets T-1797, T-1857
- `specs/transit-v1/decision_log.md` — Decision 21 (supersedes Decision 19)
- `specs/transit-v1/requirements.md` — 12.7, 12.9, 15.4, 15.7
- Prior art for the launch-scoped shared-flag pattern: `Services/PersistenceAvailability.swift` (T-1818, T-1836)
