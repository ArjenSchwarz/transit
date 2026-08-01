# Bugfix Report: Pre-cancelled creates can still persist records

**Date:** 2026-08-02
**Status:** Fixed

## Description of the Issue

A task or milestone create can persist a record even though its calling Swift task was already cancelled, or was cancelled while a non-cooperative display-ID allocation completed successfully.

**Reproduction steps:**
1. Start a task or milestone create with an uncontended display-ID allocation gate, but cancel the operation before it enters the service; or cancel it while the counter store is suspended in a successful allocation.
2. Allow the operation and counter store to continue.
3. Observe that the create returns successfully and the task or milestone is inserted and saved.

**Impact:** Cancelled callers can receive or expect cancellation while Transit still creates a durable task or milestone. Retrying can then create duplicate user-visible work, and the successful counter allocation also makes the persisted record look like an intentional create.

## Investigation Summary

The investigation followed the four-phase systematic debugging workflow.

- **Phase 1 — overview:** Expected cancellation to abort before any SwiftData insertion. Actual behavior persists a record when cancellation is not observed by a suspension point.
- **Phase 2 — inspection:** `AllocationGate.acquire()` grants a free lock without checking cancellation; `AllocationGate.run` starts its body after acquisition without checking cancellation; `TaskService.createTask` and `MilestoneService.createMilestone` do not inspect cancellation after `allocateNextID` returns.
- **Phase 3 — root cause:** Cancellation was treated as an outcome emitted by the queued-waiter cancellation handler rather than cooperative state that every successful path must inspect.
- **Phase 4 — proposed solution:** Check cancellation before gate acquisition and again after acquisition before running the body. Check once more in both create services after allocation handling and before model construction/insertion. Preserve `insertOrDelete` so save-failure cleanup remains selective and does not reintroduce SwiftData rollback resurrection bugs.

**Symptoms examined:** Pre-cancelled uncontended operations and cancellation during a non-cooperative but successful counter allocation.

**Code inspected:** `DisplayIDAllocator.AllocationGate`, `TaskService.createTask`, `MilestoneService.createMilestone`, existing T-1426 cancellation regressions, and the prior T-1426 fix.

**Hypotheses tested:** The queued-waiter cancellation path is correct for contended allocation, but does not cover cancellation before an uncontended acquisition or during an already-running allocator body.

## Discovered Root Cause

**Defect type:** Cooperative-cancellation race / missing cancellation validation

**Five Whys:**
1. Why is a cancelled create persisted? Because execution reaches model insertion and save.
2. Why does execution continue? Because successful allocation returns an ID despite the task's cancelled state.
3. Why does allocation run for a pre-cancelled caller? Because the free-gate path immediately returns `true` without checking cancellation.
4. Why is cancellation during allocation missed? Because the counter store is allowed to be non-cooperative and neither the gate boundary nor create service checks cancellation after the await.
5. Why did existing coverage miss this? Because T-1426 only exercised cancellation while queued behind a contended gate, where `cancelWaiter` explicitly resumes with `false`.

**Root cause:** Cancellation awareness was implemented only in the gate's queued-waiter removal path. The successful uncontended and successful in-flight allocation paths had no cooperative `Task.checkCancellation()` boundary before persistence.

**Contributing factors:** Swift cancellation is cooperative; an async counter store is not required to throw when its caller is cancelled. The create services intentionally convert genuine allocation failures to provisional IDs, so cancellation must remain explicitly distinguished from offline failures.

**Assumptions validated:** `ModelContext.insertOrDelete` is the required create rollback mechanism. Replacing it with context-wide rollback would risk retaining or later resurrecting inserted `@Model` instances and discarding unrelated shared-context edits.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/DisplayIDAllocator.swift:285-289` - `AllocationGate.run` checks cancellation before acquisition and again after acquiring the lock but before invoking the body; the existing `defer` releases an acquired lock when the second check throws.
- `Transit/Transit/Services/TaskService.swift:150` - Re-checks cancellation after permanent/provisional allocation handling and immediately before task construction and insertion.
- `Transit/Transit/Services/MilestoneService.swift:82` - Re-checks cancellation after allocation handling and before the synchronous uniqueness re-check and insertion.
- `Transit/TransitTests/CancelledCreateTests.swift` - Adds deterministic pre-cancelled uncontended and cancellation-during-successful-allocation regressions for both entity types while retaining the existing contended-gate cases.

**Approach rationale:** The gate checks prevent cancelled work from entering a newly acquired allocation critical section, while the service checks protect the persistence boundary when a counter store completes successfully without observing cancellation. Together they cover both dependency-level and operation-level responsibility. The existing `modelContext.insertOrDelete` calls remain unchanged, preserving selective cleanup on save failure instead of introducing a context-wide rollback. If cancellation arrives after `saveCounter` succeeds, the allocated display ID is intentionally left unused; the sequence may contain a gap, matching existing save-failure behavior and preferring a skipped number over a ghost record.

**Alternatives considered:**
- Check only inside `AllocationGate` after the body returns - Rejected because create services own the irreversible insertion boundary and should independently reject cancellation after any allocator implementation returns.
- Rely on counter stores to throw cancellation - Rejected because Swift cancellation is cooperative and protocol implementations may legitimately use non-throwing continuations or external APIs that still complete successfully.
- Roll back the context after insertion - Rejected because cancellation can be checked before insertion, and SwiftData rollback is not reliable cleanup for newly inserted models and could discard unrelated shared-context edits.

## Regression Test

**Test file:** `Transit/TransitTests/CancelledCreateTests.swift`

**Test names:**
- `preCancelledUncontendedTaskCreateDoesNotPersistRecord`
- `taskCancelledDuringSuccessfulAllocationDoesNotPersistRecord`
- `preCancelledUncontendedMilestoneCreateDoesNotPersistRecord`
- `milestoneCancelledDuringSuccessfulAllocationDoesNotPersistRecord`

**What they verify:** Already-cancelled operations never enter an uncontended counter store, and operations cancelled during a successful non-cooperative allocation throw `CancellationError` without inserting task or milestone records.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/DisplayIDAllocator.swift` | Cancellation checks before gate acquisition and before allocation body execution |
| `Transit/Transit/Services/TaskService.swift` | Post-allocation cancellation check before insertion |
| `Transit/Transit/Services/MilestoneService.swift` | Post-allocation cancellation check before uniqueness re-check/insertion |
| `Transit/TransitTests/CancelledCreateTests.swift` | Four cancellation regressions and successful-allocation instrumentation |

## Verification

**Automated:**
- [x] Regression tests fail before the fix (four T-1765 cases fail; two existing T-1426 cases pass)
- [x] Regression tests pass after the fix (`make test-quick PIPE_PRETTY=`)
- [ ] Full test suite passes — two `make test PIPE_PRETTY=` runs passed all T-1765 regressions on iOS but failed unrelated UI tests. The first failed `testClearAll`, `testEditViewPreservesTaskMilestone`, and `testDataMaintenanceGoldenPath`; the post-review rerun also failed three settings-navigation cases (`testSettingsHasBackChevron`, `testSettingsWithNoProjectsShowsCreatePrompt`, `testTappingGearPushesSettingsView`), confirming simulator/UI-suite instability outside the changed cancellation paths.
- [x] Linters/validators pass (`make lint`)

**Manual verification:**
- Review the final diff to confirm `insertOrDelete` remains the persistence boundary for both create paths.

## Prevention

**Recommendations to avoid similar bugs:**
- Treat Swift cancellation as cooperative state and check it at boundaries around non-cooperative async dependencies.
- Keep a final cancellation check immediately before irreversible persistence when the preceding await may succeed after cancellation.
- Test both queued cancellation and successful non-cooperative dependency completion.

## Related

- Transit T-1765
- Transit T-1426
- Transit T-1395
