# Bugfix Report: Sync Heartbeat Context Isolation

**Date:** 2026-08-30
**Status:** Investigation complete; fix pending

## Description of the Issue

The periodic sync heartbeat writes through the caller-provided `ModelContext`, which is the app's shared main context in production. `ModelContext.save()` persists every pending change in that context, so a background heartbeat can commit unrelated work before its owning UI or automation workflow chooses to save it. If the heartbeat save fails, the swallowed error can also leave the heartbeat mutation dirty in the shared context.

**Reproduction steps:**
1. Insert or modify an unrelated model in the context passed to `SyncManager.beat(context:)` without saving it.
2. Run a successful heartbeat, or force a heartbeat save failure and then retry.
3. Observe that a successful beat persists the unrelated model, while a failed save leaves heartbeat state mixed into the caller's pending changes.

**Impact:** Background maintenance can violate transaction ownership for any pending insert, update, or delete on the shared app context. The 60-second timer makes this timing-dependent and can affect UI and automation workflows.

## Investigation Summary

A structured inspection traced the heartbeat from app and Settings call sites through its fetch, mutation, and save behavior.

- **Symptoms examined:** Successful heartbeat saves clear unrelated caller changes; failed heartbeat saves are swallowed after mutating a caller-owned model.
- **Code inspected:** `TransitApp.swift`, `SettingsView.swift`, `Services/SyncManager.swift`, `Models/SyncHeartbeat.swift`, and `TransitTests/SyncManagerTests.swift`.
- **Hypotheses tested:** The singleton fetch guard prevents duplicate insertion and fetch failures, but does not isolate writes. Timer lifecycle and CloudKit launch-mode gating are unrelated to the transaction leak.

### Systematic inspection defects

1. **Data flow — `SyncManager.swift` heartbeat API:** `startHeartbeat(context:)` retains a caller-owned context and supplies it to each maintenance beat.
2. **Database interaction — `SyncManager.swift` beat implementation:** The heartbeat singleton is fetched and mutated in that same caller-owned context.
3. **Transaction handling — `SyncManager.swift` save:** Saving the context commits all registered pending changes, not only `SyncHeartbeat`.
4. **Error handling — `SyncManager.swift` save:** `try?` suppresses write failures without cleaning up the heartbeat mutation from the shared context.
5. **Test expectation — `SyncManagerTests.swift`:** The prior recovery test treated clearing all shared-context changes as normal behavior, encoding the defect rather than transaction isolation.

## Discovered Root Cause

The heartbeat assumes a SwiftData context save is scoped to the heartbeat model. A `ModelContext` is actually a unit of work: its save persists every pending insert, update, and delete registered in that context.

**Defect type:** Data-flow and transaction-isolation error.

**Five Whys:**
1. Why are unrelated changes persisted? Because the heartbeat calls `save()` on the context containing them.
2. Why does the heartbeat receive that context? Because app and Settings integrations pass their shared environment/main context into `startHeartbeat`.
3. Why is that unsafe? Because the heartbeat is background maintenance with independent transaction ownership, while the shared context belongs to interactive and automation workflows.
4. Why can failure contaminate later saves? Because the heartbeat mutates a model before a fallible save and suppresses the error without rollback or disposal.
5. Why did tests allow it? Because the existing recovery assertion described a context-wide save as expected best-effort behavior rather than asserting isolation.

**Contributing factors:** The heartbeat must touch the live container to trigger CloudKit, but that requirement was conflated with using the live container's shared context. SwiftData permits an independent `ModelContext` over the same `ModelContainer`, which separates change tracking while retaining the same store and CloudKit configuration.

## Resolution for the Issue

_To be completed after implementation._

## Regression Test

**Test file:** `Transit/TransitTests/SyncManagerTests.swift`

**Tests:**
- `successfulHeartbeatDoesNotSaveUnrelatedPendingChanges`
- `heartbeatFetchFailureDoesNotInsertOrSaveAndNextBeatRecoversInIsolation`
- `heartbeatSaveFailureDoesNotDirtyCallerContextAndNextBeatRecovers`

**What they verify:** Successful, fetch-failed, and save-failed heartbeat paths leave unrelated caller-context changes pending and unpersisted; heartbeat retries still commit their own isolated record.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/SyncManager.swift` | Investigation-only injectable save seam; isolation fix pending |
| `Transit/TransitTests/SyncManagerTests.swift` | Red regressions for successful and failed heartbeat isolation |
| `specs/bugfixes/sync-heartbeat-context-isolation/report.md` | Root-cause analysis and verification record |

## Verification

**Automated:**
- [ ] Regression tests pass
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Red phase must show the new isolation expectations fail against the shared-context implementation.

## Prevention

**Recommendations to avoid similar bugs:**
- Give background maintenance operations their own `ModelContext` when they do not own pending UI/service changes.
- Do not assume `ModelContext.save()` is model-scoped.
- Exercise both save success and save failure when testing background persistence paths.

## Related

- Transit T-2232
- Prior context-isolation constraint: T-173 applies to services mutating view-provided models; this heartbeat is the opposite case because it owns no view model and requires an isolated maintenance transaction.
