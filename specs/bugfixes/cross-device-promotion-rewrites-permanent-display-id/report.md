# Bugfix Report: Cross-Device Promotion Can Rewrite Permanent Display IDs

**Date:** 2026-08-02
**Status:** Investigating
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

Pending implementation.

## Regression Test

**Test file:** `Transit/TransitTests/ConcurrentPromotionTests.swift`

**Test names:**
- `taskPeerPromotionDuringAllocationIsPreserved`
- `milestonePeerPromotionDuringAllocationIsPreserved`

**What they verify:** A controlled counter gate suspends allocation while a second context commits a permanent ID for the same UUID. Promotion must preserve the peer value after resuming.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/TransitTests/ConcurrentPromotionTests.swift` | Failing two-context regressions |
| `Transit/TransitTests/TestModelContainer.swift` | Shared configurable allocation gate |
| `Transit/TransitTests/DisplayIDMaintenanceServiceReassignTests.swift` | Reuse shared gate |
| `Transit/Transit/Services/DisplayIDAllocator.swift` | Planned task committed-state recheck |
| `Transit/Transit/Services/MilestoneService.swift` | Planned milestone committed-state recheck |

## Verification

**Automated:**
- [x] Regression tests fail before the fix (`make test-quick`; both named T-2020 cases reported failed in the test output)
- [ ] Regression tests pass after the fix
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:** Not applicable; deterministic context/allocation tests pin the required interleaving.

## Prevention

- Treat mutable state checked before an `await` as expired after suspension.
- Put committed-state probes after the final suspension and adjacent to mutation.
- Do not describe SwiftData stale probes as an atomic cross-device compare-and-set.

## Related

- T-2020 — this bug.
- T-597 — process-local promotion single-flight guards.
- T-2019 — equivalent post-allocation stale-ID protection in duplicate cleanup.
