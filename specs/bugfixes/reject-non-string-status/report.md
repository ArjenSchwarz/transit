# Bugfix Report: Reject Non-String Task Status Updates Explicitly

**Date:** 2026-06-15
**Status:** Fixed
**Ticket:** T-1544

## Description of the Issue

Task status updates accepted via JSON had a validation inconsistency. When the
`status` key was present but held a non-string value (e.g. a number, boolean,
array, or null), both the App Intent and the MCP tool misreported the problem as
a *missing* status rather than a *malformed* one.

- `UpdateStatusIntent` read `json["status"] as? String`; a present-but-non-string
  value caused `as? String` to fail and returned `INVALID_INPUT` with the hint
  `Missing required field: status`.
- `MCPToolHandler.handleUpdateStatus` read `args["status"] as? String`; the same
  silent failure returned `Missing required argument: status`.

This was inconsistent with the milestone status paths (`UpdateMilestoneIntent`,
`QueryMilestonesIntent`) and enum filter validation, which already reject a
present-but-non-string `status` explicitly with `status must be a string`.

**Reproduction steps:**
1. Call Transit: Update Status with `{"displayId":1,"status":123}`.
2. Observe the response: `{"error":"INVALID_INPUT","hint":"Missing required field: status"}`.
3. Expected: `{"error":"INVALID_STATUS","hint":"status must be a string"}`.

**Impact:** Low severity, correctness/consistency. Callers (CLI / AI agents)
received a misleading error that pointed them at the wrong fix (supply a status)
when the real problem was the status field's type. No data corruption — the
mutation never occurred.

## Investigation Summary

- **Symptoms examined:** Misleading error code/message for non-string status.
- **Code inspected:**
  - `Transit/Transit/Intents/UpdateStatusIntent.swift`
  - `Transit/Transit/MCP/MCPToolHandler.swift`
  - Reference patterns: `UpdateMilestoneIntent.swift`, `QueryMilestonesIntent.swift`,
    `CreateTaskIntent.swift` (priority), `MCPToolHandler` create_task (priority).
- **Hypotheses tested:** Confirmed that `as? String` silently fails for
  non-string values, so the single `guard let ... as? String` collapsed the
  "missing" and "wrong type" cases into one branch.

## Discovered Root Cause

A single `guard let statusString = json["status"] as? String` (resp. `args[...]`)
conflated two distinct error conditions: the key being absent and the key being
present with a non-string value. Optional downcasting returns `nil` for both, so
the malformed-type case was reported with the missing-field message.

**Defect type:** Missing validation / conflated error conditions.

**Why it occurred:** The original implementation predated the project convention
(established for milestones and enum filters in T-830, T-1116, T-1156, T-1230)
of explicitly rejecting present-but-non-string fields before downcasting.

**Contributing factors:** `as? String` silently dropping wrong-typed values is an
easy trap; the task status path was not updated when the milestone paths were.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Intents/UpdateStatusIntent.swift` — split the status guard into
  a presence check (returns `INVALID_INPUT` / `Missing required field: status`)
  followed by a string-type check (returns `INVALID_STATUS` / `status must be a string`).
- `Transit/Transit/MCP/MCPToolHandler.swift` — split the status guard in
  `handleUpdateStatus` into a presence check (`Missing required argument: status`)
  followed by a string-type check (`status must be a string`), before any mutation.

**Approach rationale:** Mirrors the existing, tested milestone status validation
pattern exactly, keeping behaviour consistent across the codebase and preserving
the existing "truly missing" messages.

**Alternatives considered:**
- Returning `INVALID_INPUT` for non-string status — rejected to stay consistent
  with milestone status paths and enum filter validation, which use `INVALID_STATUS`.

## Regression Test

**Test files:**
- `Transit/TransitTests/UpdateStatusIntentTests.swift`
- `Transit/TransitTests/MCPUpdateStatusValidationTests.swift`

**Test names (new):**
- `numericStatusReturnsInvalidStatus`, `booleanStatusReturnsInvalidStatus`,
  `arrayStatusReturnsInvalidStatus`, `nullStatusReturnsInvalidStatus`,
  `nonStringStatusDoesNotMutateTask` (App Intent)
- `numericStatusReturnsErrorAndDoesNotMutate`, `booleanStatusReturnsError`,
  `arrayStatusReturnsError`, `nullStatusReturnsError`,
  `missingStatusStillReportsMissingArgument` (MCP)

**What they verify:** Numeric, boolean, array, and null status values are rejected
with `INVALID_STATUS` / `status must be a string` (App Intent) and
`status must be a string` (MCP), the task is not mutated, and a genuinely missing
status still reports the missing-field/argument message.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/UpdateStatusIntent.swift` | Explicit non-string status rejection |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Explicit non-string status rejection before mutation |
| `Transit/TransitTests/UpdateStatusIntentTests.swift` | Regression tests (App Intent) |
| `Transit/TransitTests/MCPUpdateStatusValidationTests.swift` | Regression tests (MCP) |

## Verification

**Automated:**
- [x] Regression tests pass (red confirmed before fix, green after)
- [x] Full unit test suite passes (`make test-quick` → Test Succeeded)
- [x] Linters pass (`make lint` → 0 violations in 262 files)

**Manual verification:**
- Reviewed diffs against the milestone status validation pattern for consistency.

## Prevention

**Recommendations to avoid similar bugs:**
- When reading a typed field from a JSON dictionary, distinguish "key absent" from
  "key present, wrong type" before downcasting with `as?`.
- Keep parallel validation paths (task vs milestone status) in sync when one is changed.

## Related

- T-830, T-1116, T-1156, T-1230 — milestone/enum non-string validation precedent.
- T-808 — malformed identifier rejection in the same handlers.
