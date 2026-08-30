# Bugfix Report: Cross-Device Project Name Uniqueness

**Date:** 2026-08-30
**Status:** Investigating
**Ticket:** T-2080

## Description of the Issue

Project names are intended to be case-insensitively unique. Local creation and rename checks enforce that rule only against records already present in one device's store. Two disconnected devices can therefore create UUID-distinct projects with the same name, and CloudKit later preserves both records. Name-addressed App Intent and MCP operations then fail with `AMBIGUOUS_PROJECT`, and the duplicate remains visible indefinitely.

**Reproduction steps:**
1. Create project `Transit` on device A while device B is disconnected from that change.
2. Create project `transit` on device B.
3. Allow both UUID-backed records to sync.
4. Observe that both projects remain and name-based automation cannot resolve `Transit`.

**Impact:** Cross-device project creation or rename can permanently break every automation path that addresses a project by name.

## Investigation Summary

The investigation followed the systematic-debugging workflow.

- **Symptoms examined:** UUID-distinct, case-insensitively equal project names after sync; fail-closed ambiguous lookup; no later repair.
- **Code inspected:** `ProjectService` creation, update, lookup, and uniqueness checks; `Project`; `MilestoneNameReconciler`; `MilestoneService` maintenance; `ScenePhaseModifier`; connectivity restoration wiring in `TransitApp`; T-1938 tests and decision record.
- **Hypotheses tested:**
  - Local pre-save checks could prevent the state. Ruled out because disconnected stores cannot see each other's records.
  - CloudKit would reject one write. Ruled out because records have distinct UUID identities and SwiftData cannot use a CloudKit-backed unique attribute.
  - Existing lifecycle maintenance would repair projects. Ruled out because it invokes milestone reconciliation only.

## Discovered Root Cause

The project-name invariant is enforced as a local service-layer precondition even though the store is multi-writer and eventually consistent. Unlike milestones, projects have no deterministic post-sync reconciliation or project query observation.

**Defect type:** Distributed race / missing post-sync reconciliation.

**Five Whys:**
1. Why does project lookup become ambiguous? Because several projects have the same normalized name.
2. Why can several projects pass creation validation? Because disconnected devices each inspect only their local store.
3. Why does CloudKit retain both? Because each project has a different UUID record identity.
4. Why is there no database constraint? Because CloudKit-backed SwiftData does not support `@Attribute(.unique)`.
5. Why does the invalid state persist? Because project lifecycle and query-observer reconciliation was never added when the milestone equivalent was implemented.

**Contributing factors:** `Project` has no creation timestamp, so deterministic winner selection must use UUID ordering rather than the milestone policy's creation-date ordering. Existing lookup already fails closed, preventing wrong-record mutation but not restoring usability.

## Resolution for the Issue

Pending implementation after the regression tests demonstrate the defect.

## Regression Test

**Test file:** `Transit/TransitTests/ProjectCrossDeviceUniquenessTests.swift`

**Test names:**
- `nameLookupDoesNotChooseAnArbitrarySyncedDuplicate`
- `postSyncMaintenanceReconcilesNamesWithoutDeletingProjectsOrTasks`
- `reconciliationDefersForUnsavedChangesAndCanRetry`

**What it verifies:** Cross-context duplicate imports remain ambiguous before repair; reconciliation preserves every project and task relationship, chooses a UUID-deterministic winner, avoids generated-name collisions, is idempotent, and defers rather than saving unrelated changes.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/TransitTests/ProjectCrossDeviceUniquenessTests.swift` | Cross-device regression coverage |
| `specs/bugfixes/cross-device-project-name-uniqueness/report.md` | Investigation and resolution record |

## Verification

**Automated:**
- [x] Regression test fails before the fix (`make test-quick`: missing `ProjectService.reconcileDuplicateNames` at four call sites)
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Inspect lifecycle and query-observer wiring to confirm launch, foreground, connectivity restoration, and delayed CloudKit imports all trigger or retry reconciliation.

## Prevention

- Treat local uniqueness checks over CloudKit data as best-effort guards, not global constraints.
- Pair fail-closed name lookup with deterministic, data-preserving reconciliation for eventually consistent records.

## Related

- T-76 — local project duplicate prevention.
- T-1938 — analogous cross-device milestone-name reconciliation.
- `specs/bugfixes/cross-device-milestone-name-uniqueness/report.md`.
