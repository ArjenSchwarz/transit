# Bugfix Report: Update Status Intent Not-Found Display-ID Hint

**Date:** 2026-08-02
**Status:** In Progress
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

_To be completed after the fix is implemented._

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
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Confirmed `TaskService.resolveTask(from:)` throws `invalidIdentifier(field:)` for malformed present values and `duplicateDisplayID` remains separately mapped.
- Confirmed status mutation occurs only after successful task resolution.

## Prevention

**Recommendations to avoid similar bugs:**
- Build not-found hints from the identifier key that was actually supplied rather than using one fallback for every lookup form.
- Keep exact response-hint assertions beside error-code assertions for automation-facing intents.

## Related

- Requirement 17.5: `specs/transit-v1/requirements.md`
- Transit ticket: T-1803
