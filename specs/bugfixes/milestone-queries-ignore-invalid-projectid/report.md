# Bugfix Report: Milestone Queries Ignore Invalid projectId

**Date:** 2026-04-03
**Status:** Fixed

## Description of the Issue

`QueryMilestonesIntent` and MCP `query_milestones` silently ignore an invalid UUID string for the `projectId` filter. Instead of returning an input error, the filter is dropped entirely, causing the query to return all milestones (or a broader set than expected).

**Reproduction steps:**
1. Call MCP `query_milestones` with `{"projectId": "not-a-uuid"}`
2. Or call `QueryMilestonesIntent` with the same input
3. Observe that all milestones are returned instead of an error

**Impact:** Callers passing a malformed `projectId` get incorrect results without any indication of the error. This can cause agents or automations to act on stale or unscoped data.

## Investigation Summary

- **Symptoms examined:** Passing `"not-a-uuid"` as `projectId` to milestone queries returns all milestones instead of an error
- **Code inspected:** `MCPToolHandler.handleQueryMilestones`, `QueryMilestonesIntent.applyFilters`, and the correct implementations in `MCPToolHandler.handleQueryTasks` and `QueryTasksIntent.validateProjectFilter`
- **Hypotheses tested:** The issue is a missing validation step — confirmed by comparing with the task query implementations

## Discovered Root Cause

Two locations parse `projectId` without validating the UUID format:

1. **`MCPToolHandler.handleQueryMilestones`** (line 430): Uses a combined conditional `if let pidStr = ..., let pid = UUID(uuidString: pidStr)` — when UUID parsing fails, both conditions fail and the filter is silently skipped.

2. **`QueryMilestonesIntent.applyFilters`** (line 96): Uses `(json["projectId"] as? String).flatMap(UUID.init)` — when UUID parsing fails, `flatMap` returns `nil` and the filter is silently skipped.

**Defect type:** Missing validation

**Why it occurred:** The milestone query code was written with a different pattern than the task query code. The task query implementations separate the "is the key present?" check from the "is the value valid?" check, while the milestone implementations conflate both steps.

**Contributing factors:** The pattern `flatMap(UUID.init)` is idiomatic Swift for optional chaining but inappropriate here because it cannot distinguish between "key absent" (no filter intended) and "key present with invalid value" (user error).

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift` — Split the combined conditional into separate checks: first check if the key is present, then validate UUID format with a guard, returning an error on invalid format
- `Transit/Transit/Intents/QueryMilestonesIntent.swift` — Add explicit UUID validation before `applyFilters`, returning an `INVALID_INPUT` error when `projectId` is present but not a valid UUID

**Approach rationale:** Matches the existing validated pattern used by `handleQueryTasks` and `QueryTasksIntent.validateProjectFilter`.

## Regression Test

**Test files:**
- `Transit/TransitTests/MCPMilestoneToolTests.swift`
- `Transit/TransitTests/QueryMilestonesIntentTests.swift`

**Test names:**
- `queryMilestonesInvalidProjectIdReturnsError`
- `invalidProjectIdReturnsError`

**What they verify:** Passing an invalid UUID string for `projectId` produces an error response instead of silently returning all milestones.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Validate `projectId` UUID format in `handleQueryMilestones` |
| `Transit/Transit/Intents/QueryMilestonesIntent.swift` | Validate `projectId` UUID format in `applyFilters` / `execute` |
| `Transit/TransitTests/MCPMilestoneToolTests.swift` | Add regression test for MCP handler |
| `Transit/TransitTests/QueryMilestonesIntentTests.swift` | Add regression test for intent |
| `Transit/TransitTests/ModelContainerFallbackTests.swift` | Fix pre-existing build error (nil vs empty string) |
| `Transit/TransitTests/QueryTasksIntentMilestoneTests.swift` | Fix pre-existing build errors (wrong service init signatures) |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- When parsing optional filter parameters, always separate the "is key present?" check from the "is value valid?" check
- Avoid `flatMap(UUID.init)` for user-provided filter values where presence of the key implies intent to filter
- Consider a shared helper for UUID parameter validation across query handlers

## Related

- T-665: Milestone queries ignore invalid projectId filter
