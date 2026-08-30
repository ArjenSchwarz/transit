# Bugfix Report: Creation After Project Deletion

**Date:** 2026-08-30
**Status:** Investigating
**Ticket:** T-2103

## Description of the Issue

Task and milestone creation can persist a new record after the selected project is deleted while display-ID allocation is suspended. Task creation leaves an orphan because the task relationship nullifies; milestone creation can still report success despite the project no longer existing.

**Reproduction steps:**
1. Persist a project and begin task or milestone creation for it.
2. Suspend the create inside asynchronous display-ID allocation.
3. Delete and save the project through an independent `ModelContext`, then resume allocation.
4. Observe that the create returns success and can persist a task or milestone after the project has gone.

**Impact:** Automation and UI callers can receive false success and persist records outside the required project aggregate. The create also consumes a display ID before using a project reference whose validity expired during suspension.

## Investigation Summary

The affected services, all creation callers, SwiftData relationship rules, existing stale-model validators, allocation gates, and related race regressions were inspected using the four-phase systematic-debugging workflow.

- **Symptoms examined:** peer-context deletion during allocation, stale registered project objects, orphan task persistence, milestone persistence, error contracts, and pending local project state.
- **Code inspected:** `TaskService.createTask`, `MilestoneService.createMilestone`, `Project`, `TaskCreationMilestoneValidator`, `DisplayIDRecordLookup`, `UsedDisplayIDs`, allocation-gated test support, and task/milestone automation adapters.
- **Hypotheses tested:** boundary adapters already validate the project, but that validation precedes the service's allocation await and cannot protect the persistence boundary; MainActor isolation serializes execution but does not make a method atomic across `await`; a normal live-context fetch can retain a registered snapshot, so committed state needs an independent context.

### Systematic inspection findings

1. **Data-flow defect — `TaskService.swift`:** both task overloads ultimately trust a `Project` model reference across `allocateNextID`. The UUID overload resolves the project before delegating, but there is no post-await existence check.
2. **Data-flow defect — `MilestoneService.swift`:** name uniqueness is rechecked after allocation, but project existence is not. Querying milestones by the deleted project's UUID does not prove that the project itself still exists.
3. **Integration/timing defect:** display-ID allocation is an intentional suspension point. Another MainActor job, context, device, or CloudKit merge can delete the project before execution resumes.
4. **SwiftData state defect:** the shared context can keep the passed project registered after an independent context commits deletion. A fresh transient context is required to observe committed absence, while the live context remains necessary to recognize pending inserts and deletes.
5. **Error-handling defect:** task creation already has `TaskService.Error.projectNotFound`; milestone creation has no equivalent domain error, so a service-level rejection cannot currently map to the established `PROJECT_NOT_FOUND` automation response.

## Discovered Root Cause

Project validation and project use are separated by an asynchronous display-ID allocation. The service assumes a model reference resolved before that suspension remains valid afterward. SwiftData model identity does not provide that guarantee: a peer delete can commit while the caller is suspended, and the receiving context can retain a stale registered object.

**Defect type:** TOCTOU race across `await`, with stale ORM identity/state.

**Five Whys:**
1. Why is a record created without a live project? Because creation inserts using the original `Project` object after allocation resumes.
2. Why is that object no longer valid? Because another context or sync merge deleted its stored row during the await.
3. Why does creation not notice? Because project lookup/validation occurs before the await and is not repeated at the persistence boundary.
4. Why is the existing object insufficient evidence? Because SwiftData contexts cache registered models and can lag peer-committed state.
5. Why can the store not enforce the aggregate automatically? CloudKit-compatible relationships are optional and use nullify/cascade rules; there is no transaction spanning the direct CloudKit counter allocation and SwiftData creation.

**Contributing factors:** MainActor code appears sequential despite yielding at every await; task and milestone creation accumulated targeted post-await cancellation/milestone/name safeguards without a shared project-liveness invariant; existing service tests covered stale selections before entry but not deletion during allocation.

## Resolution for the Issue

Pending implementation after the red regression checkpoint.

## Regression Test

**Test file:** `Transit/TransitTests/CreationProjectDeletionTests.swift`

**Test names:**
- `taskCreationRejectsProjectDeletedDuringAllocation`
- `milestoneCreationRejectsProjectDeletedDuringAllocation`

**What they verify:** A deterministic allocation gate suspends each create, an independent context deletes the persisted project, and resumption must return a project-not-found domain error without leaving a pending or committed task/milestone.

**Red checkpoint:** `run_silent make test-quick` compiled the test target and failed as expected before production changes. The result bundle reported 1,803 tests total: 1,801 passed and both new regressions failed. Task creation returned successfully when `TaskService.Error.projectNotFound` was expected; milestone creation likewise returned successfully instead of producing its project-not-found domain error.

## Affected Files

| File | Change |
|------|--------|
| `Transit/TransitTests/CreationProjectDeletionTests.swift` | Deterministic peer-deletion regressions |
| `specs/bugfixes/creation-after-project-deletion/report.md` | Investigation and verification record |

## Verification

**Automated:**
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:** Not required; the gated two-context test reproduces the precise persistence window.

## Prevention

- Revalidate any model invariant after the last `await` and immediately before constructing/inserting dependent records.
- For SwiftData peer-race checks, combine live pending state with a fresh committed-state probe rather than trusting a registered model alone.
- Keep deterministic allocation gates for service methods whose persistence preconditions can expire while suspended.

## Related

- Transit T-2103
- T-1764 — post-allocation milestone name uniqueness recheck
- T-1765 — post-allocation cancellation recheck
- T-2020 — fresh committed-state probes after allocation
- T-2037 — live plus committed milestone validation before task insertion
