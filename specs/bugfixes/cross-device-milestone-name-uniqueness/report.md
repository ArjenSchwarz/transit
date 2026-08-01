# Bugfix Report: Cross-Device Milestone Name Uniqueness

**Date:** 2026-08-01
**Status:** Fixed
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

**Changes made:**
- `MilestoneService.findByName` now fetches all normalized project-scoped matches and throws `.ambiguousName` instead of selecting `.first` when several exist.
- All direct MCP and App Intent callers catch ambiguity. App Intents return the distinct `AMBIGUOUS_MILESTONE` code; MCP tools return an explicit multiple-match error and do not mutate data.
- `MilestoneNameReconciler` uses locale-stable normalization, keeps the oldest milestone's original name (UUID tie-break), and renames every loser with a deterministic full-UUID suffix. It preserves descriptions, status, display IDs, records, and task assignments, avoids generated-name collisions, and is idempotent.
- Reconciliation runs through existing launch/foreground/connectivity maintenance and through `ScenePhaseModifier` milestone-name observation, covering CloudKit imports that complete after lifecycle hooks. It defers while the shared context has unrelated unsaved changes.
- Milestone requirements/design/implementation, Decision 10, README, CLAUDE.md, and agent notes document the behavior and new error contract.

**Approach rationale:** Fail-closed lookup removes the immediate wrong-record risk. Deterministic renaming restores the uniqueness invariant without guessing how to merge or delete user data, and every device can independently converge on the same result.

**Alternatives considered:**
- **CloudKit `(projectID, normalizedName)` reservation records** — not chosen because offline creation cannot synchronously reserve a name, this would add a second direct-CloudKit subsystem, and reconciliation would still be required for offline conflicts and existing data.
- **Merge and delete duplicates** — rejected because milestone descriptions, statuses, completion state, and task assignments cannot be merged without potentially losing user intent.
- **Ambiguity reporting only** — rejected because it prevents wrong writes but leaves the invalid state unresolved.

## Regression Test

**Test file:** `Transit/TransitTests/MilestoneCrossDeviceUniquenessTests.swift`

**Test names:**
- `nameLookupDoesNotChooseAnArbitrarySyncedDuplicate`
- `postSyncMaintenanceReconcilesNamesWithoutDeletingRecords`
- `mcpCreateTaskReportsAmbiguousMilestoneName`

**What it verifies:** Independent contexts can simulate a CloudKit-imported duplicate state; lookup does not select arbitrarily; lifecycle maintenance restores unique names without deleting records; MCP rejects ambiguous name assignment without creating a task.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/MilestoneService.swift` | Throw on ambiguous name lookup and invoke reconciliation from lifecycle maintenance |
| `Transit/Transit/Services/MilestoneNameReconciler.swift` | Add deterministic, data-preserving duplicate-name repair and shared normalization |
| `Transit/Transit/Views/ScenePhaseModifier.swift` | Observe imported milestone-name changes and trigger post-sync reconciliation |
| `Transit/Transit/Intents/IntentError.swift` | Add `AMBIGUOUS_MILESTONE` |
| `Transit/Transit/Intents/IntentHelpers.swift` | Propagate ambiguity through shared resolution/assignment callers |
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Reject ambiguous milestone assignment during task creation |
| `Transit/Transit/Intents/TaskUpdateValidator.swift` | Reject ambiguous milestone assignment during task updates |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Reject ambiguity in create/query task name paths |
| `Transit/TransitTests/MilestoneCrossDeviceUniquenessTests.swift` | Add cross-context CloudKit simulation, preservation, idempotence, and MCP regressions |
| `Transit/TransitTests/MilestoneServiceLookupTests.swift` | Adopt the throwing lookup contract |
| `Transit/TransitTests/IntentErrorTests.swift` | Cover the new intent error code |
| `specs/milestones/*`, `README.md`, `CLAUDE.md`, `docs/agent-notes/milestones.md` | Document the behavior, tradeoff, lifecycle, and error contract |

## Verification

**Automated:**
- [x] Regression tests failed before the fix (`xcodebuild ... -only-testing:TransitTests/MilestoneCrossDeviceUniquenessTests`; all three tests failed as expected)
- [x] Targeted regression suite passes after the fix (3/3 tests)
- [x] macOS unit suite passes (`make test-quick`)
- [x] Full iOS simulator suite passes (`make test`)
- [x] UI suite passes (`make test-ui`)
- [x] SwiftLint passes (`make lint`)

## Prevention

- Treat service-layer uniqueness in an eventually consistent store as a best-effort creation guard, not proof that duplicate states are impossible.
- Any name-based lookup over CloudKit data must distinguish zero, one, and multiple matches.
- Reconciliation must preserve user data and choose winners deterministically so every device converges on the same result.

## Related

- T-1764 — closes only the re-entrant single-process create window.
- `specs/milestones/requirements.md` requirement 1.4.
- `specs/bugfixes/concurrent-milestone-name-uniqueness/report.md`.
