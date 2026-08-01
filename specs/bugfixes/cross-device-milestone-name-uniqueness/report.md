# Bugfix Report: Cross-Device Milestone Name Uniqueness

**Date:** 2026-08-01
**Status:** Investigating
**Ticket:** T-1938

## Description of the Issue

Milestone names are intended to be case-insensitively unique within a project. Local creation checks enforce that rule, including a post-allocation recheck for re-entrant creates in one process, but disconnected CloudKit devices can each create a UUID-distinct milestone with the same name. CloudKit preserves both records when they sync because SwiftData's CloudKit integration cannot express a unique constraint. Name lookup then returns the first fetched record, so assignment and mutation can target an arbitrary milestone.

**Reproduction steps:**
1. On device A, while disconnected from device B's changes, create milestone `Beta` in project P.
2. On device B, create milestone `beta` in the same project before device A's record arrives.
3. Allow both UUID-backed records to sync and perform a name-addressed operation for `BETA`.
4. Observe that one arbitrary matching milestone is selected and no duplicate state is reported or repaired.

**Impact:** High. Name-addressed MCP and App Intent operations may mutate or assign the wrong milestone. The duplicate state persists indefinitely and violates milestone requirement 1.4.

## Investigation Summary

The investigation followed the systematic-debugging workflow:

- **Symptoms examined:** UUID-distinct, case-insensitively equal names in one project after cross-device sync; arbitrary `findByName` resolution; no post-sync repair.
- **Code inspected:** `MilestoneService.createMilestone`, `findByName`, and promotion hooks; all direct `findByName` callers in MCP/App Intents; `ScenePhaseModifier`; milestone requirements/design; T-1764's local race fix; CloudKit and SwiftData constraints.
- **Hypotheses tested:**
  - The local post-allocation check could prevent the state. Ruled out: it only sees records already present in that device's local store.
  - CloudKit would reject one record. Ruled out: milestone UUID is the record identity, so the two writes do not conflict.
  - A SwiftData unique attribute could provide strict prevention. Ruled out: CloudKit-backed SwiftData does not support `@Attribute(.unique)`.
  - Existing display-ID coordination could reserve names. Ruled out: it coordinates one counter record only and has no `(projectID, normalizedName)` identity protocol.

## Discovered Root Cause

The service-layer uniqueness invariant is local, while the data is multi-writer and eventually consistent. Two disconnected stores can each truthfully observe that a name is available, create different UUID records, and later merge both records without a CloudKit conflict. The lookup layer incorrectly assumes the invariant can never be violated and collapses multiple matches with `.first`.

**Defect type:** Distributed race / missing ambiguity handling and reconciliation.

**Five Whys:**
1. Why can a name operation target the wrong milestone? Because `findByName` returns the first matching record.
2. Why can several records match? Because separate devices can create the same normalized name before syncing.
3. Why does CloudKit retain both? Because each milestone uses a different UUID record identifier.
4. Why is there no storage constraint? Because CloudKit-backed SwiftData forbids unique attributes.
5. Why does the bad state persist? Because Transit has neither ambiguity reporting nor post-sync duplicate-name reconciliation.

**Contributing factors:** MainActor serialization and T-1764 protect only one process; eventual consistency creates a separate cross-device race. Strict prevention would require direct CloudKit reservation records and would still need an offline conflict policy.

## Resolution for the Issue

Pending implementation.

The proposed repository-appropriate scope is to:
- make project-scoped name lookup fail closed when more than one match exists and propagate a distinct ambiguity report through every caller;
- deterministically keep one original name and rename other synced records with UUID-derived suffixes, preserving records, descriptions, statuses, and task assignments;
- run reconciliation from existing post-sync lifecycle hooks;
- document why direct CloudKit reservation is not introduced for this single-user app and why reconciliation remains required even if reservation is added later.

## Regression Test

**Test file:** `Transit/TransitTests/MilestoneCrossDeviceUniquenessTests.swift`

**Test names:**
- `nameLookupDoesNotChooseAnArbitrarySyncedDuplicate`
- `postSyncMaintenanceReconcilesNamesWithoutDeletingRecords`
- `mcpCreateTaskReportsAmbiguousMilestoneName`

**What it verifies:** Independent contexts can simulate a CloudKit-imported duplicate state; lookup does not select arbitrarily; lifecycle maintenance restores unique names without deleting records; MCP rejects ambiguous name assignment without creating a task.

**Run command:** `make test-quick`

## Affected Files

Pending implementation.

## Verification

**Automated:**
- [x] Regression tests fail before the fix (`xcodebuild ... -only-testing:TransitTests/MilestoneCrossDeviceUniquenessTests`; all three tests failed as expected)
- [ ] Regression test passes after the fix
- [ ] Full test suite passes
- [ ] Linters/validators pass

## Prevention

- Treat service-layer uniqueness in an eventually consistent store as a best-effort creation guard, not proof that duplicate states are impossible.
- Any name-based lookup over CloudKit data must distinguish zero, one, and multiple matches.
- Reconciliation must preserve user data and choose winners deterministically so every device converges on the same result.

## Related

- T-1764 — closes only the re-entrant single-process create window.
- `specs/milestones/requirements.md` requirement 1.4.
- `specs/bugfixes/concurrent-milestone-name-uniqueness/report.md`.
