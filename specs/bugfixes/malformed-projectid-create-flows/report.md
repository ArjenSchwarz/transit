# Bugfix Report: Create Flows Ignore Malformed projectId Values

**Date:** 2026-04-10
**Status:** Fixed

## Description of the Issue

`CreateTaskIntent`, `CreateMilestoneIntent`, and MCP handlers `create_task`/`create_milestone` parse `projectId` via `(value as? String).flatMap(UUID.init)`. When `projectId` is present but malformed (not a valid UUID), it silently becomes `nil` and the code falls back to name-based lookup (or no-identifier handling) instead of returning an explicit validation error.

**Reproduction steps:**
1. Call `create_task` with `{"name": "Task", "type": "bug", "projectId": "not-a-uuid", "project": "SomeProject"}`
2. Observe that the task is created in "SomeProject" via name-based fallback
3. Expected: validation error about invalid `projectId`

**Impact:** Callers passing a malformed `projectId` alongside a `project` name silently get name-based resolution. This violates the documented precedence (projectId takes priority) and can create records in the wrong project. Without a `project` name, the error is "no identifier" rather than the specific "invalid projectId" message.

## Investigation Summary

- **Symptoms examined:** Passing `"not-a-uuid"` as `projectId` to create flows falls through to name-based lookup
- **Code inspected:** `CreateTaskIntent.execute`, `CreateMilestoneIntent.execute`, `MCPToolHandler.handleCreateTask`, `MCPToolHandler.handleCreateMilestone`
- **Hypotheses tested:** The issue is the `flatMap(UUID.init)` pattern that conflates "key absent" with "key present but invalid" -- confirmed by comparing with the already-fixed query tools (T-665)

## Discovered Root Cause

Four locations parse `projectId` with the pattern `(json["projectId"] as? String).flatMap(UUID.init)`:

1. `CreateTaskIntent.execute` (line 71)
2. `CreateMilestoneIntent.execute` (line 60)
3. `MCPToolHandler.handleCreateTask` (line 140)
4. `MCPToolHandler.handleCreateMilestone` (line 384)

When `UUID.init` fails on a malformed string, `flatMap` returns `nil`. This makes the code behave as if `projectId` was never provided, falling through to name-based or no-identifier handling.

**Defect type:** Missing validation

**Why it occurred:** The `flatMap(UUID.init)` pattern is idiomatic Swift for optional chaining but inappropriate here because it cannot distinguish between "key absent" (no filter intended) and "key present with invalid value" (user error).

**Contributing factors:** The query tools already had this fixed (T-665), but the create flows were not updated at that time.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Intents/CreateTaskIntent.swift` -- Add explicit projectId validation before UUID parsing
- `Transit/Transit/Intents/CreateMilestoneIntent.swift` -- Add explicit projectId validation before UUID parsing
- `Transit/Transit/MCP/MCPToolHandler.swift` -- Add explicit projectId validation in `handleCreateTask` and `handleCreateMilestone`

**Approach rationale:** Matches the existing validated pattern used by the query tools (`handleQueryTasks`, `QueryMilestonesIntent`, `handleQueryMilestones`). Separate the "is the key present?" check from the "is the value valid?" check.

## Regression Test

**Test files:**
- `Transit/TransitTests/CreateTaskIntentTests.swift`
- `Transit/TransitTests/CreateMilestoneIntentTests.swift`
- `Transit/TransitTests/MCPToolHandlerTests.swift`
- `Transit/TransitTests/MCPMilestoneToolTests.swift`

**Test names:**
- `malformedProjectIdReturnsInvalidInput` (CreateTaskIntentTests)
- `malformedProjectIdWithoutFallbackReturnsInvalidInput` (CreateTaskIntentTests)
- `malformedProjectIdReturnsInvalidInput` (CreateMilestoneIntentTests)
- `malformedProjectIdWithoutFallbackReturnsInvalidInput` (CreateMilestoneIntentTests)
- `createTaskMalformedProjectIdReturnsError` (MCPToolHandlerTests)
- `createMilestoneMalformedProjectIdReturnsError` (MCPMilestoneToolTests)

**What they verify:** Passing a malformed UUID string for `projectId` produces a validation error instead of falling through to name-based lookup.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Validate projectId UUID format before parsing |
| `Transit/Transit/Intents/CreateMilestoneIntent.swift` | Validate projectId UUID format before parsing |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Validate projectId UUID format in `handleCreateTask` and `handleCreateMilestone` |
| `Transit/TransitTests/CreateTaskIntentTests.swift` | Add regression tests for malformed projectId |
| `Transit/TransitTests/CreateMilestoneIntentTests.swift` | Add regression tests for malformed projectId |
| `Transit/TransitTests/MCPToolHandlerTests.swift` | Add regression test for MCP create_task |
| `Transit/TransitTests/MCPMilestoneToolTests.swift` | Add regression test for MCP create_milestone |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- When parsing optional parameters where key presence implies intent, always separate the "is key present?" check from the "is value valid?" check
- Avoid `flatMap(UUID.init)` for user-provided values where presence of the key is semantically meaningful
- The query tools were fixed in T-665 but the create flows were missed -- consider auditing all endpoints when fixing a pattern-level bug

## Related

- T-743: Create flows ignore malformed projectId values
- T-665: Milestone queries ignore invalid projectId filter (the same pattern bug in query tools)
