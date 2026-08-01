# Bugfix Report: Duplicate Cleanup Stale-ID Check Expires During Allocation

**Date:** 2026-08-01
**Status:** Investigating

## Description of the Issue

Duplicate display-ID cleanup verifies that a scanned loser still has the duplicate ID, then awaits asynchronous ID allocation. A peer context or device can commit a different ID while allocation is suspended. When cleanup resumes, it writes the allocated ID through its stale registered object and overwrites the peer change. The task path then adds an audit comment that falsely claims cleanup changed the task from the scanned duplicate ID.

**Reproduction steps:**
1. Scan a task or milestone duplicate group whose loser has committed display ID 5 or 7.
2. Let cleanup pass its committed-store stale-ID probe, then suspend inside `allocateNextID`.
3. Commit display ID 20 or 30 for that loser from a peer context.
4. Resume allocation and observe cleanup overwrite the peer ID; for tasks, observe a false maintenance audit comment.

**Impact:** A maintenance operation intended to repair duplicate IDs can overwrite a newer peer repair on both tasks and milestones. Task history can additionally claim a transition that cleanup did not validly perform.

## Investigation Summary

The investigation followed the four systematic-debugging phases.

### Phase 1: Initial overview

- **Expected:** The committed loser ID is still the scanned duplicate immediately before cleanup mutates and saves it. If it changed, return `stale-id`, preserve the peer value, and create no audit comment.
- **Actual:** The check is valid only before `allocateNextID`; allocation suspends and leaves a check-to-write race.
- **Context:** The race requires a peer/local-store update to land during the allocation await.

### Phase 2: Systematic inspection

- **Data-flow/timing defect:** `DisplayIDMaintenanceService.reassignTaskLoser` probes `storedTaskDisplayId`, awaits `taskAllocator.allocateNextID`, then mutates `loserTask` without a second probe.
- **Matching milestone defect:** `reassignMilestoneGroup` has the same probe-await-mutate sequence using `storedMilestoneDisplayId`.
- **Secondary task defect:** `appendAuditComment` runs after the stale write succeeds, so the race produces a false audit record based on the scan-time ID.
- **Existing safeguards inspected:** T-1061's transient-context probe correctly bypasses the main context cache, but only at the point where it is called. T-1766's used-ID closure prevents allocating an occupied ID; it does not validate ownership of the loser being mutated.

### Phase 3: Root cause analysis

**Defect type:** Async check-to-use race / stale validation.

**Five Whys:**
1. Why is the peer ID overwritten? Cleanup mutates the registered loser after the peer commits a newer value.
2. Why does cleanup permit that mutation? Its stale-ID guard passed before the peer update.
3. Why can the peer update land after the guard? `allocateNextID` is asynchronous and suspends between validation and mutation.
4. Why is the earlier guard treated as sufficient? T-1061 fixed the committed-store read mechanism but did not account for validation expiring across a later await.
5. Why is the audit false? Comment creation is conditioned only on cleanup's save succeeding, not on a committed-state validation immediately before that save.

**Root cause:** The committed loser ID is not re-probed after the final suspension point and immediately before mutation/save.

**Assumption validated:** A transient `ModelContext` is the established way to observe committed store state without the main context's registered-object cache; Decision 12 and the T-1061 regression define this contract.

### Phase 4: Solution and verification plan

- Re-probe `storedTaskDisplayId` immediately after allocation returns and directly before assigning `loserTask.permanentDisplayId`.
- Re-probe `storedMilestoneDisplayId` at the equivalent point.
- On a missing or mismatched committed value, return/report `.staleId` without mutation, save, reassignment entry, or task audit comment. The allocated counter value is intentionally skipped.
- Add deterministic task and milestone tests using a gated counter store that parks the allocation after the maintenance counter fence. Commit a peer ID while parked, then assert `staleId`, no reassignment, preserved peer ID, and no task audit comment.

## Discovered Root Cause

The initial stale-ID check occurs before an asynchronous allocation await. Its result is therefore stale by the time cleanup performs the write. Both record types share this structure, and only the task path compounds it by writing an audit comment after the invalid overwrite.

**Defect type:** Race condition / expired precondition.

**Why it occurred:** The T-1061 fix corrected where committed state was read but did not repeat that read after the subsequent suspension point.

**Contributing factors:** SwiftData's main context keeps the scan-time registered object, while the peer update is visible in the committed store through a transient context.

## Resolution for the Issue


## Regression Test

**Test file:** `Transit/TransitTests/DisplayIDMaintenanceServiceReassignTests.swift`

**Test names:**
- `taskPeerUpdateDuringAllocationIsPreservedWithoutAuditComment`
- `milestonePeerUpdateDuringAllocationIsPreserved`

**What they verify:** A peer update committed while allocation is deterministically suspended causes cleanup to return `staleId`, make no reassignment, preserve the peer ID, and, for tasks, emit no audit comment.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/TransitTests/DisplayIDMaintenanceServiceReassignTests.swift` | Gated task and milestone race regressions |
| `Transit/Transit/Services/DisplayIDMaintenanceService.swift` | Pending post-allocation committed-ID probes |
| `specs/bugfixes/duplicate-cleanup-stale-id-check-expires-during-allocation/report.md` | Investigation, resolution, and verification record |

## Verification

**Automated:**
- [x] Regression tests fail before the fix (`make test-quick`; both gated cases recorded as failed in the xcresult)
- [ ] Regression tests pass after the fix
- [ ] Full macOS unit suite passes
- [ ] SwiftLint and repository validation guards pass

**Manual verification:** Not applicable; the deterministic gated tests model the required interleaving directly.

## Prevention

- Treat validation before an `await` as expired when the validated state can change externally.
- Put the final committed-state probe after the last suspension point and adjacent to mutation.
- Pin concurrency regressions with explicit gates rather than scheduler timing.

## Related

- T-2019 — this bug.
- T-1061 — introduced the transient committed-store stale-ID probe.
- T-1766 — prevents maintenance allocation from returning an already-used display ID.
