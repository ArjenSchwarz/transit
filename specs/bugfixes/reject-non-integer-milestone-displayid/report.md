# Bugfix Report: Reject Non-Integer milestoneDisplayId Inputs

**Date:** 2026-03-27
**Status:** Fixed

## Description of the Issue

Several intent and MCP code paths parse `milestoneDisplayId` using `IntentHelpers.parseIntValue()` but only branch when parsing succeeds. If `milestoneDisplayId` is present but non-integral or non-numeric (e.g. `1.5`, `"abc"`), the code silently treats it as if the parameter was not provided instead of returning a validation error.

**Reproduction steps:**
1. Call `create_task` MCP tool with `milestoneDisplayId: "abc"` or `milestoneDisplayId: 1.5`
2. Observe that the task is created successfully without a milestone, with no error
3. Same behavior occurs with `update_task`, `query_tasks`, `IntentHelpers.assignMilestone`, and `CreateTaskIntent`

**Impact:** Medium severity. Callers sending malformed `milestoneDisplayId` values get silent success instead of a validation error, leading to unexpected behavior: tasks created without milestones, queries returning unfiltered results, and updates silently ignoring milestone assignment.

## Investigation Summary

- **Symptoms examined:** Non-integer `milestoneDisplayId` values silently ignored across 5 call sites
- **Code inspected:** `IntentHelpers.swift`, `CreateTaskIntent.swift`, `MCPToolHandler.swift`
- **Hypotheses tested:** The issue is consistently a missing validation guard — when `parseIntValue` returns `nil` for a present-but-invalid value, code falls through to the next branch

## Discovered Root Cause

**Defect type:** Missing validation

**Why it occurred:** The `parseIntValue` helper correctly returns `nil` for non-integer values, but all call sites use `if let` patterns that treat `nil` as "parameter not provided" rather than distinguishing between "not provided" and "provided but invalid".

**Contributing factors:** The `parseIntValue` function conflates two meanings of `nil`: "value not present" and "value present but not parseable as integer". The call sites have no way to distinguish these cases without checking for the key's presence separately.

## Resolution for the Issue

**Changes made:**
- `IntentHelpers.swift` — Added an inline guard in `assignMilestone()` that checks whether `milestoneDisplayId` is present in the dictionary but non-integral, returning INVALID_INPUT if so.
- `CreateTaskIntent.swift` — Added the same inline guard in `resolveMilestone()`, returning an error tuple when the key is present but `parseIntValue` returns `nil`.
- `MCPToolHandler.swift` — Added inline guards in `handleCreateTask()`, `handleQueryTasks()`, and `handleUpdateTask()` that validate `milestoneDisplayId` when the key is present but non-integral.

**Approach rationale:** Check for key presence in the dictionary separately from parsing the value. When the key exists but `parseIntValue` returns `nil`, return a validation error. This is a minimal change that doesn't alter the `parseIntValue` API.

**Alternatives considered:**
- Changing `parseIntValue` to return a `Result` type — rejected because it would require changes to all callers including those where the current behavior is correct (e.g. `displayId` on tasks/milestones which have their own validation)
- Adding a dedicated `parseRequiredIntValue()` function — rejected because the inline `json[key] != nil && parseIntValue(...) == nil` pattern is clear and avoids API proliferation

## Regression Test

**Test file:** `Transit/TransitTests/NonIntegerMilestoneDisplayIdTests.swift`
**Test names:** 10 tests covering string and fractional inputs across all 5 affected call sites

**What it verifies:** That providing a non-integer `milestoneDisplayId` (string like "abc" or fractional like 1.5) returns a validation error containing "milestoneDisplayId must be an integer" rather than silently ignoring the parameter.

**Run command:** `make test-quick` or `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -only-testing:TransitTests/NonIntegerMilestoneDisplayIdTests`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/TransitApp.swift` | Fix pre-existing `@Sendable` build error (unrelated to T-613 but required for tests to build) |
| `Transit/Transit/Intents/IntentHelpers.swift` | Add validation in `assignMilestone()` for non-integer `milestoneDisplayId` |
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Add validation in `resolveMilestone()` for non-integer `milestoneDisplayId` |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Add validation in `handleCreateTask()`, `handleQueryTasks()`, and `handleUpdateTask()` |
| `Transit/TransitTests/NonIntegerMilestoneDisplayIdTests.swift` | New regression tests (10 tests) |

## Verification

**Automated:**
- [x] Regression test passes (10/10 tests green)
- [x] Full test suite passes (all TransitTests pass on macOS)
- [x] Linters/validators pass (0 violations)

**Manual verification:**
- Confirmed all 10 regression tests fail before the fix (red phase)
- Confirmed all 10 regression tests pass after the fix (green phase)
- Full test suite shows no regressions

## Prevention

**Recommendations to avoid similar bugs:**
- When parsing optional parameters from untyped dictionaries, always check for key presence separately from value parsing to distinguish "not provided" from "invalid"
- Consider adding a lint rule or code review checklist item for `parseIntValue` call sites to ensure they handle the "present but invalid" case

## Related

- T-613: Reject non-integer milestoneDisplayId inputs
