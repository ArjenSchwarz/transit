# Bugfix Report: Reject Non-String Milestone Arguments in Task Handlers

**Date:** 2026-05-17
**Status:** Fixed
**Ticket:** T-1114

## Description of the Issue

The task milestone-name code paths used `args["milestone"] as? String` (or the
equivalent on the App Intent JSON dictionary). When `milestone` was present but
the value was not a String (e.g. a number, boolean, array, or `NSNull`), the
optional cast returned `nil` and the code silently fell through to the
"milestone absent" branch. The create or update operation then succeeded
without assigning the requested milestone, instead of returning an input
validation error.

**Reproduction steps:**

1. Call MCP `create_task` with `{ "milestone": 42, ... }` (numeric value).
2. The task is created successfully with no milestone assignment.
3. The same applies to `update_task` and the matching App Intents.

**Impact:** Medium — agents and CLI callers receive a misleading success
response and a task is created or modified that does not reflect the caller's
intent. Aligns with prior validation patterns already in place for
`milestoneDisplayId` (T-613), `projectId` (T-788), `clearMilestone` (T-1060),
and identifier fields (T-810/T-830).

## Investigation Summary

- **Symptoms examined:** MCP and App Intent handlers accept malformed `milestone`
  values without raising an error.
- **Code inspected:**
  - `Transit/Transit/MCP/MCPToolHandler.swift` — `handleCreateTask`, `handleUpdateTask`
  - `Transit/Transit/Intents/CreateTaskIntent.swift` — `resolveMilestone`
  - `Transit/Transit/Intents/IntentHelpers.swift` — `assignMilestone`
- **Hypotheses tested:** Whether existing identifier validation already covered
  this case. It does not — the existing validation is for the
  `milestoneDisplayId` (integer) and `milestoneId`/`projectId` (UUID-shaped)
  fields, but the plain `milestone` (by-name) field had no type guard.

## Discovered Root Cause

`as? String` returns `nil` for any non-string value, and the surrounding
`if let milestoneName = args["milestone"] as? String { ... }` treats that
exactly like a missing key. A present-but-wrong-typed value therefore behaves
identically to an absent key, hiding the input error from the caller.

**Defect type:** Missing input validation.

**Why it occurred:** The validation pattern was added for identifier fields
that have explicit type guards (integer/UUID), but the legacy `milestone`
by-name field was left as a simple cast.

**Contributing factors:** No regression coverage existed for non-string values
on this field across the four call sites.

## Resolution for the Issue

**Changes made:**

- `Transit/Transit/MCP/MCPToolHandler.swift` — `handleCreateTask` and
  `handleUpdateTask`: when `args["milestone"]` is present, require a String
  value and reject otherwise with `"milestone must be a string"`.
- `Transit/Transit/Intents/CreateTaskIntent.swift` — `resolveMilestone`:
  same validation against the parsed JSON dictionary, returning
  `IntentError.invalidInput`.
- `Transit/Transit/Intents/IntentHelpers.swift` — `assignMilestone`:
  same validation for App Intent update paths.

**Approach rationale:** Mirror the existing
"present-but-malformed" guard pattern used for `milestoneDisplayId`,
`clearMilestone`, `projectId`, and `milestoneId`. Validation lives at each
call-site (close to the existing guards) rather than in a shared helper,
matching the style of the surrounding code.

**Alternatives considered:**

- A shared `parseStringValue` helper that all sites call — Rejected because
  the validation is one-line per site and a helper would obscure the
  field-specific error message wording.

## Regression Test

**Test files:**

- `Transit/TransitTests/NonStringMilestoneArgTests.swift` — covers
  `CreateTaskIntent`, `UpdateTaskIntent`, and `IntentHelpers.assignMilestone`.
- `Transit/TransitTests/MCPNonStringMilestoneArgTests.swift` — covers MCP
  `create_task` and `update_task`.

**What they verify:** A present-but-non-string `milestone` argument is
rejected with an INVALID_INPUT error whose hint contains
`"milestone must be a string"`. The tests additionally verify that no task is
persisted (for create paths) and the existing milestone assignment is
preserved (for update paths).

**Run command:**
```
xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit \
  -destination 'platform=macOS' \
  -only-testing:TransitTests/NonStringMilestoneArgTests \
  -only-testing:TransitTests/MCPNonStringMilestoneArgTests
```

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Reject non-string `milestone` in `handleCreateTask` and `handleUpdateTask` |
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Reject non-string `milestone` in `resolveMilestone` |
| `Transit/Transit/Intents/IntentHelpers.swift` | Reject non-string `milestone` in `assignMilestone` |
| `Transit/TransitTests/NonStringMilestoneArgTests.swift` | New regression tests for App Intent paths |
| `Transit/TransitTests/MCPNonStringMilestoneArgTests.swift` | New regression tests for MCP paths |

## Verification

**Automated:**

- [x] Regression tests pass
- [x] Full test suite passes
- [x] SwiftLint passes

## Prevention

**Recommendations to avoid similar bugs:**

- Whenever a JSON dictionary lookup uses `as? String`, decide explicitly
  whether a missing key and a wrongly-typed value should behave differently.
  If they should differ, gate on `args[key] != nil` before the cast.
- When adding a new field whose value type is constrained, add a test for
  the malformed case alongside the happy path.

## Related

- T-613 — Reject non-integer milestoneDisplayId
- T-743/T-788 — Reject malformed projectId
- T-810/T-830 — Reject non-string milestoneId / milestone status
- T-1060 — Reject malformed clearMilestone
