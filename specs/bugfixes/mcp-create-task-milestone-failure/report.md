# Bugfix Report: MCP create_task Leaves Task Behind When Milestone Assignment Fails

**Date:** 2026-02-26
**Status:** Fixed
**Ticket:** T-240

## Description of the Issue

When calling the MCP `create_task` tool with a milestone argument that fails to resolve (non-existent milestone, wrong display ID, or project mismatch), the task was already created and persisted in the database before the milestone assignment was attempted. The error was returned to the caller, but the orphaned task remained in SwiftData.

**Reproduction steps:**
1. Call `create_task` with a valid project but a non-existent `milestone` name or invalid `milestoneDisplayId`
2. Receive an error response (e.g., "No milestone named 'nonexistent' in project 'MyProject'")
3. Query tasks — the task exists in the database despite the error

**Impact:** Medium — orphaned tasks accumulate in the database, polluting query results and confusing agents that rely on error responses to mean "nothing was created".

## Investigation Summary

- **Symptoms examined:** `handleCreateTask` in `MCPToolHandler.swift` creates and saves the task, then attempts milestone assignment as a separate step
- **Code inspected:** `MCPToolHandler.handleCreateTask`, `TaskService.createTask`, `MilestoneService.setMilestone`
- **Hypotheses tested:** The task creation and milestone assignment are not atomic — task is persisted before milestone validation

## Discovered Root Cause

The `handleCreateTask` method performs task creation (`taskService.createTask`) before milestone validation. When any milestone error occurs, the method returns an error result but never deletes the already-persisted task.

**Defect type:** Missing validation before persistence

**Why it occurred:** Milestone assignment was added after the initial `create_task` implementation, bolted on as a post-creation step without considering the need for upfront validation.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift` — Pre-validate milestone existence and project ownership before calling `createTask()`. The task is only created after all milestone validation passes, eliminating the possibility of orphaned tasks entirely.

**Approach rationale:** Validate-before-create is the cleanest approach — consistent with T-260's fix for `CreateTaskIntent`. No rollback logic needed since the task is never created when validation fails.

**Initial approach (superseded):** The first iteration used delete-on-failure (rollback after task creation). This was refactored to validate-first for consistency with the Intent layer and to eliminate rollback complexity.

## Regression Test

**Test file:** `Transit/TransitTests/MCPMilestoneIntegrationTests.swift`
**Test names:**
- `createTaskWithNonexistentMilestoneByNameDoesNotCreateTask`
- `createTaskWithNonexistentMilestoneByDisplayIdDoesNotCreateTask`
- `createTaskWithMilestoneProjectMismatchDoesNotCreateTask`

**What they verify:** After `create_task` returns an error due to milestone validation failure, no task exists in the database (task was never created).

**Run command:** `make test-quick` or `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -only-testing:TransitTests/MCPMilestoneIntegrationTests`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Pre-validate milestone before task creation; remove rollback logic and logger |
| `Transit/TransitTests/MCPMilestoneIntegrationTests.swift` | Update 3 regression test names/comments to reflect validate-first approach |

## Verification

**Automated:**
- [x] Build succeeds (`make build-macos`)
- [x] All tests pass (`make test-quick`)

## Prevention

**Recommendations to avoid similar bugs:**
- Validate all inputs before persisting any data (validate-then-create pattern)
- When a multi-step creation operation can partially fail, ensure validation is done upfront
- Add integration tests that verify database state after error paths, not just error responses

## Related

- T-240: MCP create_task leaves task behind when milestone assignment fails
- T-260: CreateTaskIntent returns error but still creates task when milestone assignment fails (same pattern, Intent layer)
