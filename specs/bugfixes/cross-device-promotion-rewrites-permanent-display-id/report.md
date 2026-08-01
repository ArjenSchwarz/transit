# Bugfix Report: Cross-Device Promotion Can Rewrite Permanent Display IDs

**Date:** 2026-08-02
**Status:** Fixed
**Ticket:** T-2020

## Description of the Issue

Two devices can hold the same synced task or milestone with a provisional display ID. Each process has its own single-flight guard, so both can allocate a different permanent ID. More immediately, a peer promotion can merge into the local store while this process is suspended in `allocateNextID`; the current code then assigns its allocated ID unconditionally through a stale registered model and overwrites the peer value.

**Reproduction steps:**
1. Save a task or milestone with `permanentDisplayId == nil` and load it in two model contexts.
2. Start promotion in one context and suspend its counter allocation.
3. Commit a permanent display ID for the same UUID from the peer context.
4. Resume allocation and observe the first context replace the peer's ID.

**Impact:** A human-facing T-/M- identifier can change after it was observed on another device. The losing counter value is consumed without an owner or audit trail.

## Investigation Summary

The investigation followed the four systematic-debugging phases.

### Phase 1: Initial overview

- **Expected:** Promotion assigns an ID only while the committed record is still provisional. A permanent ID imported from a peer must win.
- **Actual:** Promotion checks provisional state only in its initial fetch, before asynchronous allocation.
- **Context:** Process-local single-flight guards prevent overlapping lifecycle triggers on one device but do not coordinate devices or processes.

### Phase 2: Systematic inspection

- **Task timing defect:** `DisplayIDAllocator.promoteProvisionalTasks` fetches nil IDs, awaits allocation, then assigns unconditionally.
- **Milestone timing defect:** `MilestoneService.promoteProvisionalMilestones` has the same fetch-await-assign sequence.
- **Stale registered state:** SwiftData has no public per-object refresh API; a context's registered model can retain its pre-merge value while a transient context sees the committed row.
- **Existing compatible pattern:** `DisplayIDRecordLookup` already uses transient contexts to probe committed display IDs for duplicate-cleanup stale-write protection.
- **Existing counter CAS scope:** `CloudKitCounterStore` atomically advances only the counter record. It does not bind an allocation to a SwiftData model UUID.

### Phase 3: Root cause analysis

**Defect type:** Cross-process race / expired precondition.

**Five Whys:**
1. Why can a peer ID be rewritten? Promotion writes after a peer has committed a permanent ID.
2. Why does promotion still write? Its model reference reflects the original provisional fetch.
3. Why can that fetch become stale? `allocateNextID` suspends while CloudKit counter work runs.
4. Why does the single-flight guard not prevent it? The guard is process-local; each device owns a different allocator/service instance.
5. Why is there no atomic ownership check on assignment? SwiftData exposes neither a conditional field update nor a transaction spanning its CloudKit-managed record and the direct CloudKit counter record.

**Root cause:** The committed `permanentDisplayId == nil` precondition is never revalidated after the final suspension point and immediately before mutation/save.

### Phase 4: Solution and verification plan

1. Re-read each task's committed display ID from a transient context after allocation. Assign/save only when it remains nil.
2. Apply the same post-allocation probe to milestones.
3. If a peer ID exists, preserve it and deliberately consume the allocated counter value; reusing that value would risk a duplicate.
4. Add deterministic two-context tests that park allocation, commit a peer ID, resume, and assert the peer ID remains for both model types.
5. Run the complete macOS unit suite and SwiftLint through the Makefile.

A stronger theoretical design is an owner-reservation CloudKit record keyed by model UUID, atomically saved with the counter update. That would make racing devices receive the same ID. It is not a schema-neutral patch: it introduces a directly managed CloudKit record type/fields that must be deployed, and the reservation still cannot be committed atomically with SwiftData's separately managed model record. The selected fix uses the strongest available SwiftData-side stale-write guard without changing the deployed CloudKit schema. The remaining simultaneous pre-merge race will be documented precisely in the finalized report and project note.

## Discovered Root Cause

The initial provisional-state fetch expires across asynchronous allocation. Both promotion paths then mutate a potentially stale registered object without probing the committed store.

**Defect type:** Race condition / stale write.

**Why it occurred:** T-597 added process-local exclusion but did not add cross-context validation after suspension.

**Contributing factors:** SwiftData CloudKit sync provides merge/conflict behavior but no public compare-and-set for a single model property.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/DisplayIDRecordLookup.swift` — added throwing, fail-closed task and milestone probes that return true only for an existing committed provisional record.
- `Transit/Transit/Services/DisplayIDAllocator.swift` — task promotion now probes after allocation and skips mutation/save when a peer ID exists; save recovery resets only the exact ID this run assigned.
- `Transit/Transit/Services/MilestoneService.swift` — applies the same post-allocation ownership check and selective recovery to milestones.
- `Transit/TransitTests/CrossDevicePromotionTests.swift` — deterministic two-context/allocation regressions for both record types, including unrelated dirty-state preservation and a second lifecycle pass that consumes no further counter value.
- `Transit/TransitTests/PromotionPreconditionTests.swift` — task/milestone regressions for records deleted while allocation is suspended; each path consumes the in-flight value once, performs no stale save, and leaks no value on a later pass.
- `Transit/TransitTests/PromotionRollbackTests.swift` — symmetric selective-recovery tests prove a failed save does not clear a different in-memory ID.
- `Transit/TransitTests/TestModelContainer.swift` — generalized the existing allocation gate as shared test support; duplicate-maintenance tests continue to park their third counter read.

**Approach rationale:** The transient probe is the strongest schema-neutral check SwiftData exposes. It runs after the final suspension point and immediately before the MainActor mutation/save, closes the demonstrated peer-merge window, fails closed on missing/unreadable state, and does not require a CloudKit production-schema deployment.

**Alternatives considered:**
- **Direct CloudKit owner reservation keyed by model type + UUID:** This is the strongest full ownership direction because the reservation and counter advance can be one atomic `CKModifyRecordsOperation`, making every promoter recover the same ID. It was not selected for this patch because it adds a new deployed CloudKit record schema and migration/operational surface. It also cannot share a transaction with SwiftData's separately managed model write, so the reservation must become durable allocation state rather than a short-lived lock.
- **Rely on CloudKit conflict resolution:** Rejected because it allows a visible permanent ID to change after assignment.
- **Process-local locking:** Already present from T-597 and cannot coordinate devices.

**Remaining limitation:** The fix is not an atomic cross-device compare-and-set. If two devices both finish their final transient-context nil probe before either device's assignment has merged into the other's local store, both can still save different IDs and CloudKit can later resolve the conflict. SwiftData provides no conditional field update or transaction spanning its model record and the direct CloudKit counter. The implemented guarantee is specifically: a permanent ID already committed/merged into the local store by the time allocation returns will not be overwritten by that promotion pass.

## Regression Test

**Test files:**
- `Transit/TransitTests/CrossDevicePromotionTests.swift`
- `Transit/TransitTests/PromotionPreconditionTests.swift`
- `Transit/TransitTests/PromotionRollbackTests.swift`

**Focused test names:**
- `taskPeerPromotionDuringAllocationIsPreserved`
- `milestonePeerPromotionDuringAllocationIsPreserved`
- `deletedTaskIsSkippedAfterAllocation`
- `deletedMilestoneIsSkippedAfterAllocation`
- `failedTaskPromotionPreservesDifferentInMemoryID`
- `failedMilestonePromotionPreservesDifferentInMemoryID`

**What they verify:** The gated two-context tests suspend allocation while a second context commits a permanent ID or deletes the same UUID, then prove promotion performs no stale save. The peer-ID cases additionally prove unrelated dirty UI state remains unsaved and a later lifecycle pass consumes no second counter value. The selective-recovery tests exercise the exact-value guard and prove a failed save does not clear a different in-memory ID. These are deterministic local-store simulations of a CloudKit merge; they do not create a cross-device CloudKit transaction or close the documented simultaneous-probe race.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/TransitTests/CrossDevicePromotionTests.swift` | Controlled two-context regressions for tasks and milestones, dirty-state isolation, and later-pass counter stability |
| `Transit/TransitTests/PromotionPreconditionTests.swift` | Controlled deletion-during-allocation regressions for both record types |
| `Transit/TransitTests/PromotionRollbackTests.swift` | Selective save-failure recovery coverage for both record types |
| `Transit/TransitTests/TestModelContainer.swift` | Shared configurable allocation gate |
| `Transit/TransitTests/DisplayIDMaintenanceServiceReassignTests.swift` | Reuse shared gate at the existing third-load suspension point |
| `Transit/Transit/Services/DisplayIDRecordLookup.swift` | Fail-closed committed provisional-state probes |
| `Transit/Transit/Services/DisplayIDAllocator.swift` | Post-allocation task recheck and selective save recovery |
| `Transit/Transit/Services/MilestoneService.swift` | Post-allocation milestone recheck and selective save recovery |
| `docs/agent-notes/technical-constraints.md` | Exact guarantee, residual race, and owner-reservation direction |
| `CHANGELOG.md` | Unreleased T-2020 fix entry |

## Verification

**Automated:**
- [x] Regression tests fail before the fix (`make test-quick`; both named T-2020 cases reported failed in the test output)
- [x] Regression tests pass after the fix (`make test-quick`)
- [x] Full macOS unit suite passes (`make test-quick`: 1,614 passed, 0 failed)
- [x] All unit tests in the iOS combined run pass (`make test`: 1,149 passed overall; the only 3 failures were unrelated UI tests)
- [x] Linters/validators pass (`make lint`, including the SwiftData ownership guard)
- [ ] Full iOS/UI suite passes — blocked by unrelated existing UI failures below

**Validation blockers:**
- `make test`: 1,149 passed, 3 failed. Failures were `TransitUITests.testClearAll`, `TransitUITests.testEditViewPreservesTaskMilestone`, and `DataMaintenanceUITests.testDataMaintenanceGoldenPath`; there were zero non-UI failure markers.
- `make test-ui`: 15 passed, 6 failed. It repeated the three failures above and also failed three Settings navigation cases. The xcresult shows `dashboard.settingsButton` in the toolbar's **More** overflow for `testSettingsHasBackChevron`; the other two Settings cases failed their existing assertions. No changed file implements these UI paths.

**Physical-device verification:** Not run. The controlled tests use independent `ModelContext` instances on one retained local store to deterministically model a peer change that has already reached the receiving device's store. They prove the post-allocation local-store guard, dirty-state behavior, deletion handling, and later-pass counter stability; they do not exercise CloudKit transport timing or the residual simultaneous-probe race.

## Prevention

- Treat mutable state checked before an `await` as expired after suspension.
- Put committed-state probes after the final suspension and adjacent to mutation.
- Do not describe SwiftData stale probes as an atomic cross-device compare-and-set.

## Related

- T-2020 — this bug.
- T-597 — process-local promotion single-flight guards.
- T-2019 — equivalent post-allocation stale-ID protection in duplicate cleanup.
