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

**Changes made:**
- `Transit/Transit/Services/ProjectNameReconciler.swift` adds a locale-stable name policy and deterministic, data-preserving duplicate repair. The lexicographically smallest UUID keeps the original name; other projects receive UUID-derived suffixes with collision fallback.
- `Transit/Transit/Services/ProjectService.swift` uses the shared normalization for local validation and lookup, and exposes `reconcileDuplicateNames()` for maintenance triggers.
- `Transit/Transit/Views/ScenePhaseModifier.swift` reconciles on launch/foreground and observes a project ID/name fingerprint so delayed CloudKit imports trigger a post-sync pass.
- `Transit/Transit/TransitApp.swift` retries reconciliation when connectivity returns.
- Reconciliation defers whenever the shared context has unsaved changes, preventing it from committing unrelated edits; later lifecycle, connectivity, or query-observer triggers retry it.

**Approach rationale:** Deterministic renaming restores name-based automation without deleting projects or guessing how to merge descriptions, repository metadata, colors, tasks, or milestones. UUID order is stable on every peer and requires no model/schema migration.

**Alternatives considered:**
- **Direct CloudKit reservation keyed by normalized name** — rejected because offline creation cannot synchronously claim a reservation, it would add a second direct-CloudKit subsystem, and existing/offline conflicts would still require reconciliation.
- **Merge and delete duplicate projects** — rejected because project metadata and child relationships cannot be merged without risking data loss.
- **Add a project creation timestamp** — rejected because UUID provides a sufficient deterministic order without a CloudKit schema migration or ambiguous defaults for existing records.
- **Ambiguity reporting only** — already present, but it leaves the invalid state and broken automation unresolved.

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
| `Transit/Transit/Services/ProjectNameReconciler.swift` | Deterministic project-name policy and reconciliation |
| `Transit/Transit/Services/ProjectService.swift` | Shared normalization and maintenance entry point |
| `Transit/Transit/Views/ScenePhaseModifier.swift` | Launch, foreground, and project query-observer triggers |
| `Transit/Transit/TransitApp.swift` | Connectivity-restoration retry and service wiring |
| `Transit/TransitTests/ProjectCrossDeviceUniquenessTests.swift` | Cross-context ambiguity, preservation, collision, idempotence, and retry regressions |
| `docs/agent-notes/project-structure.md` | Document project reconciliation lifecycle |
| `CHANGELOG.md` | Record the T-2080 fix |
| `specs/bugfixes/cross-device-project-name-uniqueness/report.md` | Investigation and resolution record |

## Verification

**Automated:**
- [x] Regression test fails before the fix (`make test-quick`: missing `ProjectService.reconcileDuplicateNames` at four call sites)
- [x] macOS unit suite passes (`make test-quick`)
- [x] Full iOS simulator suite passes (`make test`)
- [x] UI suite passes (`make test-ui`)
- [x] Linters/validators pass (`make lint`)

**Manual verification:**
- Inspected `ScenePhaseModifier` and `TransitApp` wiring to confirm launch, foreground, connectivity restoration, and delayed project ID/name query changes all invoke reconciliation.
- Confirmed maintenance exits without saving when the shared context has pending changes, leaving later triggers available to retry.

## Prevention

- Treat local uniqueness checks over CloudKit data as best-effort guards, not global constraints.
- Pair fail-closed name lookup with deterministic, data-preserving reconciliation for eventually consistent records.
- Keep local validation, lookup, and reconciliation on one locale-stable normalization policy.

## Related

- T-76 — local project duplicate prevention.
- T-1938 — analogous cross-device milestone-name reconciliation.
- `specs/bugfixes/cross-device-milestone-name-uniqueness/report.md`.
