# Bugfix Report: Update Status Intent Not-Found Display-ID Hint

**Date:** 2026-08-02
**Status:** Fixed
**Ticket:** T-1803

## Description of the Issue

`UpdateStatusIntent` returns `TASK_NOT_FOUND` for a valid but nonexistent `displayId`, but its hint says only `Provide either displayId (integer) or taskId (UUID)`. Requirement 17.5 requires the hint to echo the supplied display ID so callers can identify the missing task immediately.

**Reproduction steps:**
1. Call `UpdateStatusIntent` with `{"displayId":999,"status":"planning"}` when no task has display ID 999.
2. Parse the JSON error response.
3. Observe `TASK_NOT_FOUND` with a generic identifier hint that does not contain `999`.

**Impact:** Low. The operation does not mutate task state, but automation callers receive an incomplete diagnostic for a valid missing display ID.

## Investigation Summary

- **Symptoms examined:** A missing display-ID lookup returns `TASK_NOT_FOUND`, but the response hint omits the requested ID; UUID misses use the existing generic hint.
- **Code inspected:** `UpdateStatusIntent.swift`, `IntentHelpers.resolveTask`, `TaskService.resolveTask(from:)`, `UpdateTaskIntent.swift`, related identifier-validation tests, and MCP task-resolution wording.
- **Hypotheses tested:** The service correctly distinguishes malformed identifiers from lookup misses. The defect is in App Intent error-hint mapping, not in lookup, status validation, or mutation handling.

## Discovered Root Cause

`IntentHelpers.resolveTask` maps every non-validation lookup failure to the same generic `TASK_NOT_FOUND` hint. Because `TaskService.resolveTask(from:)` does not include which dictionary key was used in its `.taskNotFound` error, the shared mapper currently loses the supplied `displayId`.

**Defect type:** Error-message mapping logic error.

**Why it occurred:** The generic fallback was originally sufficient for both identifier forms, but requirement 17.5 made the display-ID miss response actionable by requiring the requested ID in the hint.

**Contributing factors:** The resolver is shared by `UpdateStatusIntent` and `UpdateTaskIntent`, while malformed identifier and duplicate-ID cases have separate mappings that must remain unchanged.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Intents/IntentHelpers.swift` — Added an explicit `TaskService.Error.taskNotFound` mapping. Genuine misses with a valid `displayId` now return `No task with displayId N`; UUID misses retain `Provide either displayId (integer) or taskId (UUID)`. Malformed identifiers and duplicate display IDs continue through their existing `INVALID_INPUT` and `INTERNAL_ERROR` mappings, and unexpected lookup failures retain the prior generic not-found mapping.
- `Transit/TransitTests/UpdateStatusIntentTests.swift` — Extended the display-ID not-found regression with an exact hint assertion and pinned the existing UUID not-found hint.
- `CHANGELOG.md` — Added the T-1803 entry under Unreleased/Fixed.

**Approach rationale:** Handle the dedicated not-found error in the shared resolver rather than changing `TaskService` or duplicating lookup logic in `UpdateStatusIntent`. The resolver already receives the original JSON, so it can echo only a successfully parsed display ID while preserving malformed-input validation, duplicate-ID classification, status validation, and mutation ordering.

**Alternatives considered:**
- Change `TaskService.Error.taskNotFound` to carry an identifier — rejected because the service is also used by non-JSON callers and the existing error contract does not need a presentation hint.
- Reintroduce an inline resolver branch in `UpdateStatusIntent` — rejected because T-1837 centralized this mapping specifically to prevent App Intent lookup behavior from drifting.
- Echo the raw `displayId` for every failure — rejected because malformed values must remain `INVALID_INPUT`, and storage/unknown failures must not be relabeled as a confirmed missing ID.

## Regression Test

**Test file:** `Transit/TransitTests/UpdateStatusIntentTests.swift`
**Test names:** `unknownDisplayIdReturnsTaskNotFound`, `unknownTaskIdReturnsTaskNotFound`

**What it verifies:** A missing display-ID lookup returns exactly `TASK_NOT_FOUND` with `No task with displayId 999`, while a missing UUID lookup retains the existing generic UUID-capable hint. Existing malformed-identifier, duplicate-ID, status, and atomic mutation tests remain unchanged.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/IntentHelpers.swift` | Map display-ID misses to a hint containing the supplied ID while preserving UUID and other error mappings |
| `Transit/TransitTests/UpdateStatusIntentTests.swift` | Pin exact display-ID and UUID not-found hints |
| `CHANGELOG.md` | Document the T-1803 fix |
| `specs/bugfixes/update-status-intent-not-found-hint-omits-requested-display-id/report.md` | Record investigation, resolution, and verification |

## Verification

**Automated:**
- [x] Red-phase regression test fails before the fix (`unknownDisplayIdReturnsTaskNotFound`)
- [x] Regression assertions pass in `make test-quick`
- [x] `make test-quick` passes for the complete macOS `TransitTests` target, including existing malformed-identifier, duplicate-ID, status, and status/comment atomicity coverage
- [x] `make lint` passes with 0 violations in 319 files, including the SwiftData ownership guard
- [ ] `make test` — the iOS simulator suite built and ran, but three unrelated existing UI tests failed: `TransitUITests.testClearAll`, `TransitUITests.testEditViewPreservesTaskMilestone`, and `DataMaintenanceUITests.testDataMaintenanceGoldenPath`. No UI production or UI test files changed for T-1803; the Makefile pipeline also returned status 0 despite `xcodebuild` reporting these failures.

**Manual verification:**
- The exact display-ID assertion fails against the pre-fix generic hint and passes after the fix.
- `TaskService.resolveTask(from:)` still rejects malformed present identifiers before lookup, and duplicate display IDs still map to `INTERNAL_ERROR`.
- Resolution happens before `TaskService.updateStatus`, so not-found responses cannot mutate status; the existing macOS status/comment atomicity tests remain green.

## Prevention

**Recommendations to avoid similar bugs:**
- Build not-found hints from the identifier key that was actually supplied rather than using one fallback for every lookup form.
- Keep exact response-hint assertions beside error-code assertions for automation-facing intents.

## Related

- Requirement 17.5: `specs/transit-v1/requirements.md`
- Transit ticket: T-1803
