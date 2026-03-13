# Bugfix Report: Avoid Main-Context Rollback During ID Promotion

**Date:** 2026-03-13
**Status:** Fixed
**Ticket:** T-449

## Description of the Issue

Connectivity-triggered provisional ID promotion reused the app's shared
`container.mainContext`. Earlier fixes for T-281/T-317 added
`ModelContext.rollback()` when a promotion save failed so the in-memory
`permanentDisplayId` would return to `nil`. That avoided stuck provisional IDs,
but it also made promotion able to wipe out unrelated unsaved edits if network
connectivity returned while the user was mid-edit.

**Reproduction steps:**
1. Create a task or milestone offline so it keeps a provisional display ID.
2. Make an unrelated unsaved edit in the UI (for example, editing another task
   name or project description).
3. Regain connectivity or foreground the app so promotion runs on the shared
   main model context.
4. Let the promotion path fail after assigning `permanentDisplayId` in memory.
5. Observe that `rollback()` reverts not only the provisional ID change, but
   also the unrelated edit that the user has not saved yet.

**Impact:** High. A background promotion retry can silently discard in-progress
user edits that share the same `ModelContext`.

## Investigation Summary

Reviewed the promotion flow end to end, including the original rollback fix and
the app wiring that invokes promotion on connectivity restore and foregrounding.

- **Symptoms examined:** Unrelated unsaved edits disappearing when promotion
  retries overlap with UI editing.
- **Code inspected:** `Transit/Transit/Services/DisplayIDAllocator.swift`,
  `Transit/Transit/Services/MilestoneService.swift`,
  `Transit/Transit/TransitApp.swift`, and
  `Transit/Transit/Services/ConnectivityMonitor.swift`
- **Hypotheses tested:** Confirmed promotion runs against the shared
  `container.mainContext`; confirmed that using `rollback()` on that context is
  broad enough to revert unrelated edits; added focused tests that simulate a
  save failure after assigning a permanent ID.

## Discovered Root Cause

The T-281/T-317 fix applied the normal "save or rollback" pattern to code that
does not represent a user-initiated atomic edit. `promoteProvisionalTasks(in:)`
and `promoteProvisionalMilestones()` run opportunistically on the app's shared
main context, so `rollback()` reverted every unsaved mutation in that context
instead of only reverting the failed promotion assignment.

**Defect type:** Over-broad rollback on a shared mutable context

**Why it occurred:** The earlier fix correctly restored `permanentDisplayId` to
its persisted value, but reused the same rollback strategy as user-driven edit
flows without accounting for promotion being triggered asynchronously on the UI
context.

**Contributing factors:**
- Connectivity restore and scene activation both invoke promotion in the
  background while the UI may still contain unsaved edits.
- Promotion only needs to undo one field (`permanentDisplayId`), but rollback
  operates on the entire context.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/DisplayIDAllocator.swift:84` - Added an injectable
  `save` closure for tests and changed failed task promotion recovery to reset
  only `task.permanentDisplayId` to `nil`.
- `Transit/Transit/Services/MilestoneService.swift:175` - Added the same test
  seam for milestone promotion and changed failed milestone recovery to reset
  only `milestone.permanentDisplayId`.
- `Transit/TransitTests/PromotionRollbackTests.swift:20` - Added regression
  tests proving failed promotion preserves unrelated unsaved task/project edits
  while still reverting the promoted model to provisional.

**Approach rationale:** The failure path only needs to undo the provisional ID
promotion that was never persisted. Restoring that single field keeps the model
eligible for a future promotion retry without discarding unrelated unsaved work
on the shared context.

**Alternatives considered:**
- Running promotion in a dedicated background `ModelContext` - viable, but a
  larger refactor touching app wiring and service ownership. Resetting only the
  failed field resolves the bug with a smaller, lower-risk change.

## Regression Test

**Test file:** `Transit/TransitTests/PromotionRollbackTests.swift`
**Test names:**
- `promoteProvisionalTasksFailedSavePreservesUnrelatedUnsavedEdits`
- `promoteProvisionalMilestonesFailedSavePreservesUnrelatedUnsavedEdits`
- `promoteProvisionalTasksStopsOnAllocatorFailure`
- `promoteProvisionalMilestonesStopsOnAllocatorFailure`

**What it verifies:** A promotion save failure reverts only the promoted
model's `permanentDisplayId`, preserves unrelated unsaved edits on the same
context, and still stops promotion cleanly after the first failure.

**Run command:** `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -configuration Debug -derivedDataPath ./DerivedData -only-testing:TransitTests/PromotionRollbackTests`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/DisplayIDAllocator.swift` | Replaced context-wide rollback with targeted task ID reset and added a test seam for save failures |
| `Transit/Transit/Services/MilestoneService.swift` | Replaced context-wide rollback with targeted milestone ID reset and added a test seam for save failures |
| `Transit/TransitTests/PromotionRollbackTests.swift` | Added save-failure regression coverage for shared-context edit preservation |

## Verification

**Automated:**
- [x] Regression test passes (`PromotionRollbackTests`)
- [x] iOS test suite passes (`make test`)
- [ ] Full macOS unit suite passes (`make test-quick`) — blocked by pre-existing
  `TaskEditSaveErrorTests` failures already present before this change
- [ ] UI tests pass (`make test-ui`) — one observed failure in
  `TransitUITests.testClearAll`; a focused rerun of that single test passed
- [ ] Linters/validators pass (`make lint`) — blocked by pre-existing
  `TaskEditSaveErrorTests.swift` type-body-length violation

**Manual verification:**
- Reviewed `TransitApp` and `ConnectivityMonitor` wiring to confirm promotion
  still triggers from connectivity restore and scene activation without any API
  changes at the call sites.

## Prevention

**Recommendations to avoid similar bugs:**
- Prefer targeted state restoration over `ModelContext.rollback()` when a
  background/maintenance task runs on a shared context and only one field needs
  to be reverted.
- Keep save-failure seams available for background maintenance flows so tests
  can exercise post-mutation save failures directly.

## Related

- T-449: Avoid main-context rollback during ID promotion
- T-281: Rollback provisional ID promotion on save failure
- T-317: Rollback milestone promotion on save failure
