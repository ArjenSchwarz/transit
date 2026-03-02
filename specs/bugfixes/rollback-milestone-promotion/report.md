# Bugfix Report: Rollback Milestone Promotion on Save Failure

**Date:** 2026-03-03
**Status:** Fixed
**Ticket:** T-317

## Description of the Issue

`MilestoneService.promoteProvisionalMilestones()` and `DisplayIDAllocator.promoteProvisionalTasks(in:)` set `permanentDisplayId` on the model object before calling `modelContext.save()`. If the save fails, the in-memory value remains set while the change is never persisted. On subsequent promotion attempts, the predicate `$0.permanentDisplayId == nil` no longer matches these objects, so they are silently skipped and stuck in a broken state where they appear promoted in-memory but remain provisional on disk.

**Reproduction steps:**
1. Create a task or milestone with a provisional display ID (e.g., while offline)
2. Trigger promotion (connectivity restore or app foregrounding)
3. Have `modelContext.save()` fail after `permanentDisplayId` is set (e.g., CloudKit conflict)
4. The model retains the in-memory `permanentDisplayId` value
5. A subsequent promotion call skips this model because the predicate no longer matches

**Impact:** Provisional milestones and tasks become permanently stuck — they show a promoted display ID in the current session but revert to provisional after app restart, and future promotion passes never retry them.

## Investigation Summary

- **Symptoms examined:** `promoteProvisionalMilestones` and `promoteProvisionalTasks` lack rollback on save failure
- **Code inspected:** `MilestoneService.swift` (line 168-187), `DisplayIDAllocator.swift` (line 82-102)
- **Hypotheses tested:** Confirmed that all other mutating methods in MilestoneService (`updateMilestone`, `updateStatus`, `deleteMilestone`, `setMilestone`) already use the `do/catch` + `rollback()` pattern. The promotion methods were the only ones missing it.

## Discovered Root Cause

Both promotion methods set `permanentDisplayId` before `modelContext.save()` and lack `modelContext.rollback()` in their catch blocks. When save fails, the dirty in-memory state persists, preventing future promotion retries.

**Defect type:** Missing error handling (inconsistent pattern application)

**Why it occurred:** The promotion methods were implemented with a simpler error handling pattern (`break` only) since they were designed as best-effort background operations. The need for rollback was overlooked because the focus was on stopping the loop, not on resetting the in-memory state.

**Contributing factors:** Same root cause as T-270 — no compile-time enforcement that `save()` calls are paired with `rollback()` on failure.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/MilestoneService.swift:184` — Added `modelContext.rollback()` before `break` in `promoteProvisionalMilestones`
- `Transit/Transit/Services/DisplayIDAllocator.swift:100` — Added `context.rollback()` before `break` in `promoteProvisionalTasks`

**Approach rationale:** Mirrors the existing pattern used consistently across all other mutating methods in MilestoneService and TaskService. The rollback resets the in-memory `permanentDisplayId` back to `nil`, so the predicate matches again on the next promotion pass.

**Alternatives considered:**
- Setting `permanentDisplayId` after save — rejected because save needs the dirty state to persist the change
- Saving the old value and manually restoring on failure — rejected because `rollback()` handles this correctly and is the established pattern

## Regression Test

No new regression tests added. The bug involves `modelContext.save()` failure scenarios that require injecting save failures, which is not straightforward with SwiftData's in-memory test containers (same limitation documented in T-270).

**Existing tests verified:**
- `MilestoneServiceTests.createMilestoneWithProvisionalIDOnAllocatorFailure`
- `DisplayIDAllocatorTests.allocateNextIDRetriesOnConflict`
- `DisplayIDAllocatorTests.promotionSortOrderIsCreationDateAscending`

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/MilestoneService.swift` | Added `modelContext.rollback()` in `promoteProvisionalMilestones` catch block |
| `Transit/Transit/Services/DisplayIDAllocator.swift` | Added `context.rollback()` in `promoteProvisionalTasks` catch block |

## Verification

**Automated:**
- [x] Linters pass (`make lint` — 0 violations)
- [ ] Full test suite passes (`make test-quick` — blocked by Xcode plugin loading issue in environment)

## Prevention

**Recommendations to avoid similar bugs:**
- Audit all `modelContext.save()` call sites to ensure they use the `do/catch` + `rollback()` pattern
- Consider extracting a shared `saveOrRollback()` helper to make this pattern impossible to miss

## Related

- T-317: Rollback milestone promotion on save failure
- T-270: Rollback missing after delete save failures (same class of bug)
