# Implementation Explanation: Pre-cancelled creates can still persist records (T-1765)

Explains the change at three expertise levels, followed by a completeness assessment.

## Beginner Level

### What Changed

When you create a task or milestone in Transit, the app first asks a shared counter for the next human-friendly number (`T-42`, `M-3`), then writes the record to the database. Getting that number can take a moment, because the counter lives in iCloud.

Sometimes the work gets *cancelled* while that's happening — you close the sheet, the app moves to the background, an automation client hangs up. The bug: the cancellation was often ignored, and the record got written anyway.

The fix adds three "are we still wanted?" checkpoints. If the answer is no, the operation stops and reports that it was cancelled, without writing anything.

### Why It Matters

A cancelled create that still writes a record produces a task nobody asked for. Worse, the caller believes nothing happened, so a retry produces a *second* copy. Because Transit syncs through iCloud, both copies land on every device.

### Key Concepts

- **Cancellation in Swift is cooperative.** Cancelling doesn't forcibly stop anything — it sets a flag. Code has to *check* the flag and stop voluntarily. Think of a "please stop" note left on someone's desk: it only works if they read it. The bug was code that never read the note.
- **Display ID.** The `T-42` number shown in the UI, separate from the internal identifier. It comes from a shared counter so no two records get the same one.
- **The allocation gate.** A queue that lets only one create at a time talk to the counter, so two simultaneous creates can't grab the same number.

---

## Intermediate Level

### Changes Overview

| File | Change |
|------|--------|
| `Services/DisplayIDAllocator.swift` | `AllocationGate.run` calls `Task.checkCancellation()` after acquiring the lock, before running the body |
| `Services/TaskService.swift` | `createTask` re-checks cancellation after allocation handling, before constructing and inserting the model |
| `Services/MilestoneService.swift` | `createMilestone` re-checks cancellation after allocation handling, before the uniqueness re-check and insertion |
| `TransitTests/CancelledCreateTests.swift` | Four new pre-cancelled/in-flight regressions, plus deterministic queue-enqueue and queue-removal assertions for the two retained T-1426 cases |

### Implementation Approach

The pre-existing cancellation handling (T-1426) covered exactly one window: a caller *queued* behind another create's gate hold. `AllocationGate.acquire()` wraps its `withCheckedContinuation` in a `withTaskCancellationHandler`, so a cancelled waiter gets pulled out of the queue and resumed with `false`, and `run` throws `CancellationError`.

Two windows were left open:

1. **Uncontended acquisition.** If the gate is free, `acquire()` returns `true` immediately without ever consulting cancellation. An already-cancelled caller sailed straight into the allocation.
2. **Successful non-cooperative allocation.** `CounterStore` is a protocol. Nothing obliges an implementation to throw when its caller is cancelled — a store built on `withCheckedContinuation` or a non-cancellable external API will simply complete. The caller then held a valid ID and proceeded to insert.

The fix places checks at the two boundaries that own those windows: the gate boundary (`run`, post-acquire) and the persistence boundary (each create service, immediately before model construction).

The service-level checks sit *after* the `do`/`catch` that converts allocation failures into a `.provisional` ID. That placement is deliberate — a check inside the `do` block would be skipped whenever the fallback path ran.

### Trade-offs

- **Two layers rather than one.** The gate check alone is insufficient: with iCloud sync disabled, `allocateNextID` throws `.cloudSyncInactive` *before* the gate is ever entered, so no gate check runs at all and the service falls back to a provisional ID. The service checks are the only cancellation guard on that path.
- **Accepting a numbering gap.** If cancellation lands after `saveCounter` commits, the allocated ID is burned. Undoing it would mean a downward compare-and-swap racing every other allocator. A gap is invisible to users; a ghost record is not. This matches how existing save-failure cleanup already behaves.
- **`insertOrDelete` left alone.** Cancellation is now caught *before* insertion, so no new rollback mechanism was needed. A context-wide rollback would have risked the SwiftData resurrection problem documented in T-452 and would discard unrelated edits on the shared context.

---

## Expert Level

### Technical Deep Dive

The load-bearing subtlety is *where* the gate check goes. An earlier revision of this branch checked cancellation both before and after `acquire()`. The pre-acquire check was removed during pre-push review for two reasons:

1. **It is redundant.** Trace both windows. Uncontended: `acquire()` returns `true` synchronously on the actor, and the post-acquire check throws — identical outcome, identical side effects (`body` never runs, so the store is never touched). Contended-and-already-cancelled: the caller enters `withTaskCancellationHandler`, `onCancel` fires, `cancelWaiter` resumes it with `false`, and the `guard acquired` throws. Neither window can reach `body` either way.

2. **It silently disabled the T-1426 regressions.** The contended tests construct `Task { @MainActor in … }` from a `@MainActor` test body and call `.cancel()` before yielding the actor, so the child observes `isCancelled == true` at its first instruction. A pre-acquire check throws there — the contender never enters `waiters`, and `cancelWaiter` plus the `guard acquired else` branch become unreachable. Since `CancelledCreateTests` is the only file in the suite that cancels anything, that path went to zero coverage.

Both claims were verified empirically rather than argued. Replacing `guard acquired else { throw CancellationError() }` with a `fatalError` left all six tests green while the pre-acquire check was present, and crashed the two contended tests once it was removed. Separately, deleting the post-acquire check fails the two pre-cancelled tests. Each of the three checks is now pinned by at least one regression.

The `defer { release() }` placement is correct across every exit. It is registered *after* `guard acquired`, so it arms only when the caller genuinely holds the lock. `cancelWaiter` and `release` are both actor-isolated and both remove the waiter from `waiters` before resuming it, making `acquired == false` ⟺ "never held the lock" an invariant. A waiter handed the lock by `release()` that then throws at the post-acquire check re-enters `release()`, passing the lock to the next queued caller.

There is no ordering hazard in `acquire()` when the caller is already cancelled and the gate is held. `onCancel` spawns `Task { await self.cancelWaiter(id:) }`, which must hop to the `AllocationGate` actor; `acquire()` is already executing on that actor and appends the waiter synchronously inside the `withCheckedContinuation` closure before suspending. Actor isolation therefore guarantees the append happens-before the dequeue — the waiter cannot be stranded.

### Architecture Impact

`AllocationGate.run` has one caller (`allocateNextID`) but five transitive ones. Beyond the two create paths, the new check also affects `DisplayIDAllocator.promoteProvisionalTasks`, `MilestoneService.promoteProvisionalMilestones`, and both `DisplayIDMaintenanceService` reassignment loops. A cancelled pass in those now aborts at the current record rather than continuing to burn CloudKit allocations for every remaining one — a modest throughput improvement, and consistent with loops that already `break` on error and retry next pass.

The change also sharpens an existing contract: `CounterStore` conformances are explicitly *not* required to be cancellation-cooperative. Responsibility for observing cancellation sits with the gate and with whoever owns the irreversible write, not with the dependency.

### Potential Issues

- **`DisplayIDMaintenanceService` error mapping.** It converts any thrown allocation error into `GroupFailure(code: .allocationFailed, message: error.localizedDescription)`. For `CancellationError` that renders as `The operation couldn't be completed. (Swift.CancellationError error 1.)`. Reachable via the MCP `reassign_duplicate_display_ids` tool when a Hummingbird request task is cancelled on client disconnect — at which point nothing reads the envelope. Left for a separate ticket; noted rather than widened into this bugfix.
- **Promotion and maintenance still lack a post-allocation check.** The same non-cooperative-store argument that motivates the service checks applies to those four call sites: a cancelled pass can still commit exactly one record before the *next* iteration trips the gate check. These are idempotent repair writes rather than ghost records, so impact is low, but the invariant is not yet uniform.
- **`issuedIDs` accumulates phantom entries.** IDs allocated to cancelled callers are never pruned from the in-process collision set. Harmless — the guard only excludes numbers — and immaterial at this app's scale.
- **Duplicated allocation policy.** `TaskService.createTask` and `MilestoneService.createMilestone` now hold ~30 character-identical lines of allocate-or-fall-back-to-provisional logic, edited in lockstep three times (T-1395, T-1426, T-1765). Extracting it into `DisplayIDAllocator` would also retire the `type_body_length` suppression this change made necessary. Deliberately deferred rather than folded into a bugfix branch.

---

## Completeness Assessment

**Fully implemented**

- Cancellation before an uncontended gate acquisition aborts before the counter store is touched (`AllocationGate.run`, verified by two regressions asserting `wasNeverAccessed`).
- Cancellation during a successful non-cooperative allocation aborts before insertion (`TaskService.createTask`, `MilestoneService.createMilestone`, verified by two regressions).
- The pre-existing queued-waiter path (T-1426) retains its coverage.
- `insertOrDelete` remains the persistence boundary for both creates; no rollback semantics changed.
- CHANGELOG and bugfix report describe the shipped behaviour, including the cross-cutting effect on promotion and duplicate cleanup.

**Partially implemented**

- The cancellation invariant is enforced at create boundaries only. Promotion (`promoteProvisionalTasks`, `promoteProvisionalMilestones`) and duplicate cleanup (`DisplayIDMaintenanceService`) gain the gate check but have no post-allocation check of their own.
- `saveAttempts == 1` in the two allocation-window tests asserts a call count on the test double rather than the documented gap behaviour. A stronger assertion would run a second, uncancelled create and expect display ID `2`.

**Not implemented (deliberately out of scope)**

- Extraction of the duplicated allocation-policy block shared by the two create services.
- `CancellationError` mapping in `DisplayIDMaintenanceService`'s `GroupFailure` envelope.

**No divergence** between the implementation and the claims in `report.md` or the CHANGELOG entry after this review's corrections.
