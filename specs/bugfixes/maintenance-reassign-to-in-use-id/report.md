# Bugfix Report: Display ID Maintenance Can Reassign To An In-Use ID

**Date:** 2026-07-25
**Status:** Fixed

## Description of the Issue

Duplicate display ID cleanup (`DisplayIDMaintenanceService.reassignDuplicates`) assigns a fresh
display ID to every "loser" in a duplicate group. It obtained that ID by calling
`DisplayIDAllocator.allocateNextID()` with **no** `excluding:` closure, so the allocator's
collision guard ran against an empty used-ID set. Whatever the CloudKit counter handed back was
written onto the loser unchecked.

Every other allocation path in the app - `TaskService.createTask`, `MilestoneService.createMilestone`,
`MilestoneService` promotion, and `DisplayIDAllocator.promoteProvisionalTasks` - passes the set of
display IDs already committed locally, which is exactly the protection T-1395 added so a stale or
eventually-consistent counter read cannot reissue an ID that is already in use. Duplicate cleanup was
the one path that opted out.

**Reproduction steps:**

1. Have tasks T-5 (winner), T-5 (duplicate loser) and T-9 in the store.
2. Run duplicate maintenance. The counter fence advances the CloudKit counter to 10.
3. Serve a stale replica read for the subsequent allocation, so the allocator reads the pre-advance
   value 5 (a normal CloudKit eventual-consistency outcome; also reproducible with a counter whose
   writes are not yet visible).
4. The loser is assigned 5 again - the duplicate the run was meant to repair survives. With a
   different stale value the loser lands on 9 instead, converting one collision into a new one.

**Impact:** Medium severity, high user-visible confusion. The failure happens precisely when the user
is trying to repair display ID corruption, and cleanup reports success while either leaving the
original duplicate in place or creating a fresh collision on an unrelated record. Both tasks and
milestones were affected.

## Investigation Summary

- **Symptoms examined:** `reassignTaskLoser` and the milestone loop both call `allocateNextID()`
  bare. Compared against every other call site of `allocateNextID` in the codebase.
- **Code inspected:**
  - `Transit/Transit/Services/DisplayIDMaintenanceService.swift` (the two maintenance allocations)
  - `Transit/Transit/Services/DisplayIDAllocator.swift` (`allocateLocked`, the `usedIDs` contract)
  - `Transit/Transit/Services/TaskService.swift:99`, `Transit/Transit/Services/MilestoneService.swift:72,228`,
    `DisplayIDAllocator.swift:207` - the four call sites that do pass `excluding:`
- **Hypotheses tested and ruled out:**
  - *The counter-advance fence already makes this safe.* It does not. The fence advances to
    `sampledMax + 1` at the start of the run, but the allocation that follows performs its own
    `loadCounter()`. If that read is stale - the fence's write not yet visible on the replica - the
    candidate can fall back inside the occupied range. The fence narrows the window; it does not
    close it.
  - *The allocator's in-process `issuedIDs` set covers it.* It only tracks IDs this process handed
    out during this launch. It knows nothing about the IDs already sitting on records in the store,
    which is what the `usedIDs` closure is for.

## Discovered Root Cause

`DisplayIDMaintenanceService` never passed a used-ID snapshot to the allocator, so
`allocateNextID`'s duplicate guard (`if used.contains(candidate)`) evaluated against the empty
default `{ [] }` and never fired.

**Defect type:** Missing argument / omitted invariant - an optional safety parameter with a
permissive default was left off one call path.

**Why it occurred:** `allocateNextID(excluding:)` defaults `usedIDs` to `{ [] }`. The default keeps
call sites terse but makes "no collision protection" the silent fallback, so a new call path is
unprotected unless its author knows to opt in. `DisplayIDMaintenanceService` was written against the
counter-advance fence as its collision story, and the fence looks sufficient until you notice the
allocation re-reads the counter.

**Contributing factors:** The maintenance service is the only allocation caller that is not a
create/promote path, so it did not follow the established `excluding: { self.usedDisplayIDs() }`
pattern by copy.

## Resolution for the Issue

**Changes made:**

- `Transit/Transit/Services/DisplayIDRecordLookup.swift` (new) - extracted the service's store reads
  (record fetch by UUID, committed-display-ID probe via a transient context) and added
  `usedTaskDisplayIDs()` / `usedMilestoneDisplayIDs()`, which return every permanent display ID
  committed to the local store.
- `Transit/Transit/Services/DisplayIDMaintenanceService.swift` - both maintenance allocations now
  pass the matching used-ID closure:
  `taskAllocator.allocateNextID(excluding: { self.lookup.usedTaskDisplayIDs() })` and
  `milestoneAllocator.allocateNextID(excluding: { self.lookup.usedMilestoneDisplayIDs() })`.
  The private lookup helpers moved to `DisplayIDRecordLookup` and their call sites now go through
  `lookup`.

**Approach rationale:** The closure is evaluated inside the allocator's allocation gate on every
retry, so it always reflects the latest committed state - including IDs written by losers reassigned
earlier in the same run. Using a per-type closure rather than a set captured up front is what the
other four call sites do, and it avoids having to thread mutable state through the group loops.

The extraction into `DisplayIDRecordLookup` was needed because `DisplayIDMaintenanceService.swift`
was at 395 lines against SwiftLint's 400-line limit (`make lint` runs `--strict`, so the warning is
an error). Grouping the store reads into one small `@MainActor` value type keeps them private,
mirrors the `CloudKitCounterStore` extraction precedent, and leaves the service focused on the
scan/reassign flow.

**Alternatives considered:**

- **Call `TaskService.usedDisplayIDs()` / `MilestoneService.usedDisplayIDs()`.** Both are `private`
  and those files are owned by other in-flight work. Duplicating the two-line fetch in the
  maintenance service's own lookup type is cheaper than widening another service's API.
- **Maintain a mutable used-ID set built once from the scan and updated as losers are reassigned.**
  Fewer fetches, but it goes stale against concurrent writers and duplicates the "recompute inside
  the gate" contract the allocator already documents. Rejected as more state for no correctness gain.
- **Change `allocateNextID`'s `excluding:` default from `{ [] }` to a required parameter.** Would
  prevent the whole class of bug, but it touches five call sites across three files owned by other
  streams. Worth doing separately.
- **`// swiftlint:disable file_length`.** Rejected - suppressing the limit rather than addressing it.

## Regression Test

**Test file:** `Transit/TransitTests/DisplayIDMaintenanceStaleCounterTests.swift`

**Test names:**

- `taskLoserNeverGetsAnInUseIdWhenCounterReadIsStale`
- `milestoneLoserNeverGetsAnInUseIdWhenCounterReadIsStale`
- `taskLoserIsNotReassignedWhenStuckCounterOnlyOffersUsedIds`
- `milestoneLoserIsNotReassignedWhenStuckCounterOnlyOffersUsedIds`

**What they verify:** A new `StaleReadCounterStore` test double serves a stale counter value for a
configurable number of reads (or forever, for a permanently stuck counter) while accepting writes
with a current change tag - i.e. the read is wrong, not the compare-and-swap.

- The stale-read tests assert the reassigned loser gets neither the duplicate ID it started with nor
  the unrelated bystander's ID, and that every record ends the run with a distinct display ID.
  Before the fix the loser was handed the duplicate ID straight back.
- The stuck-counter tests assert that when the counter can only ever offer an in-use ID the group
  fails with `.allocationFailed` and the loser keeps its original ID, rather than a colliding ID
  being written. Failing loudly is the correct outcome; before the fix cleanup silently "succeeded"
  while changing nothing.

**Run command:**

```bash
make test-quick
# or, focused:
xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit \
  -destination 'platform=macOS' \
  -only-testing:TransitTests/DisplayIDMaintenanceStaleCounterTests test
```

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/DisplayIDMaintenanceService.swift` | Pass per-type used-ID closures to both maintenance allocations; route store reads through `lookup` |
| `Transit/Transit/Services/DisplayIDRecordLookup.swift` | New - record lookups, committed-ID probes, and the used display ID sets |
| `Transit/TransitTests/DisplayIDMaintenanceStaleCounterTests.swift` | New - `StaleReadCounterStore` double and four regression tests |

## Verification

**Automated:**

- [x] Regression tests fail before the fix, pass after
- [x] Full macOS unit suite passes (`make test-quick`)
- [x] `make lint` (SwiftLint `--strict`) passes

**Manual verification:** None - the failure mode needs a stale CloudKit replica read, which is not
reproducible by hand. The test double models it directly.

## Prevention

- Treat "optional safety parameter with a permissive default" as a smell. `allocateNextID`'s
  `excluding:` default of `{ [] }` means every new call site is unprotected until someone remembers
  to opt in. Making it required would turn this bug class into a compile error; that change is
  deliberately out of scope here (it touches files owned by other in-flight work) but is worth
  scheduling.
- Advancing a counter and allocating from it are two separate reads. A fence at the start of a run
  is not a substitute for a per-allocation collision check whenever the backing store is eventually
  consistent.
- When adding a call site for a shared allocator/ID service, grep the existing call sites first and
  match their argument shape.

## Related

- T-1766 - this bug.
- T-1395 - added the `excluding:` collision guard and the in-process `issuedIDs` set that this fix
  extends to the maintenance path.
- T-1061 - the stale-scan guard in the same two loops (`storedTaskDisplayId` / `storedMilestoneDisplayId`),
  now living in `DisplayIDRecordLookup`.
- T-1621 (open) - `usedDisplayIDs()` swallows fetch failures and degrades to an empty set. The new
  `DisplayIDRecordLookup` helpers deliberately copy that existing behaviour so the fix stays
  consistent with the other call sites; on a fetch failure the maintenance path degrades to the
  pre-fix behaviour for that attempt. Fixing the swallowed error is T-1621's job and should cover all
  the helpers at once.
- T-1797 - iCloud-sync-off handling in the same maintenance flow.
