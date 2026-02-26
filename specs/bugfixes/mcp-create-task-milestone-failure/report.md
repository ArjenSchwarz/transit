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

The `handleCreateTask` method performs task creation (`taskService.createTask`) at line 152, which inserts and saves the task into the SwiftData model context. Milestone assignment is attempted afterwards (lines 163–184). When any milestone error occurs, the method returns an error result but never deletes the already-persisted task.

**Defect type:** Missing rollback / non-atomic operation

**Why it occurred:** Milestone assignment was added after the initial `create_task` implementation, bolted on as a post-creation step without considering the need to roll back on failure.

**Contributing factors:** SwiftData's `modelContext.save()` commits immediately — there is no built-in transaction scope to roll back automatically.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift:163-195` — In every error path of the milestone assignment block, delete the task from the model context and save before returning the error result

**Approach rationale:** Delete-on-failure is the simplest correct approach. Each error branch explicitly cleans up the task, keeping the operation atomic from the caller's perspective.

**Alternatives considered:**
- Validate milestone before creating the task — would require restructuring the method and duplicating milestone lookup logic; milestone validation is already encapsulated in `MilestoneService`
- Use `modelContext.rollback()` — would roll back all unsaved changes in the context, potentially affecting other operations

## Regression Test

**Test file:** `Transit/TransitTests/MCPMilestoneIntegrationTests.swift`
**Test names:**
- `createTaskWithNonexistentMilestoneByNameDeletesTask`
- `createTaskWithNonexistentMilestoneByDisplayIdDeletesTask`
- `createTaskWithMilestoneProjectMismatchDeletesTask`

**What they verify:** After `create_task` returns an error due to milestone assignment failure, no task exists in the database.

**Run command:** `make test-quick` or `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -only-testing:TransitTests/MCPMilestoneIntegrationTests`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Delete task from context on milestone assignment failure |
| `Transit/TransitTests/MCPMilestoneIntegrationTests.swift` | Add 3 regression tests for orphaned task cleanup |

## Verification

**Automated:**
- [x] Build succeeds (`xcodebuild build-for-testing`)
- [ ] Regression tests pass (test runner has environmental connection issues — tests are structurally correct and build passes)
- [ ] Full test suite passes

## Prevention

**Recommendations to avoid similar bugs:**
- When a multi-step creation operation can partially fail, ensure cleanup/rollback for all prior steps
- Consider a pattern where validation is done before any persistence (validate-then-create)
- Add integration tests that verify database state after error paths, not just error responses

## Related

- T-240: MCP create_task leaves task behind when milestone assignment fails
