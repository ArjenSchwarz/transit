# Bugfix Report: CreateTaskIntent leaves task on milestone failure

**Date:** 2026-03-27
**Status:** Fixed

## Description of the Issue

When `CreateTaskIntent.execute` creates a task and then fails to assign a milestone (via `MilestoneService.setMilestone`), the intent returns error JSON but does not delete or roll back the already-persisted task. This leaves an orphaned task in the database even though the caller receives an error response.

**Reproduction steps:**
1. Call `CreateTaskIntent` with valid task fields and a milestone that passes pre-validation
2. Have `setMilestone` fail due to a persistence error (e.g., concurrent save conflict)
3. Observe that the error response is returned but the task remains in the database

**Impact:** Low frequency (requires a persistence error after pre-validation succeeds), but when triggered creates orphaned/duplicate tasks that the user did not intend to create. Especially problematic for agent callers that retry on error.

## Investigation Summary

- **Symptoms examined:** The intent's catch block at line 111-113 returned error JSON without cleaning up the task
- **Code inspected:** `CreateTaskIntent.swift`, `MCPToolHandler.swift` (lines 184-192), `MilestoneService.setMilestone`, `TaskService.createTask`
- **Hypotheses tested:** Compared intent behavior with MCP handler behavior for the same operation

## Discovered Root Cause

**Defect type:** Missing cleanup / error recovery

**Why it occurred:** The T-260 fix pre-resolved milestones before task creation, eliminating the most common failure path. This made the post-creation `setMilestone` failure seem unlikely, so the catch block was left with only an error return and no cleanup. The MCP handler (`MCPToolHandler.handleCreateTask`) already had the correct cleanup pattern.

**Contributing factors:** The intent and MCP handler implement the same operation independently, making it easy for one to diverge from the other on error handling.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Intents/CreateTaskIntent.swift:113-114` - Added `projectService.context.delete(task)` and `try? projectService.context.save()` in the catch block when `setMilestone` fails
- `Transit/Transit/Intents/CreateTaskIntent.swift:1` - Added `import SwiftData` (required for `context.delete` and `context.save`)

**Approach rationale:** Matches the existing cleanup pattern in `MCPToolHandler.handleCreateTask` (lines 188-190). Uses `projectService.context` because it exposes a public `context` property, unlike `TaskService` which has a private `modelContext`. All services share the same `ModelContext` in production.

**Alternatives considered:**
- Add a `deleteTask` method to `TaskService` - Would add API surface for a single error recovery case; unnecessary since `projectService.context` is already available and the pattern is established in MCP
- Use `modelContext.safeRollback()` instead of delete+save - Rollback cannot selectively undo the task creation without also undoing other pending changes in the shared context

## Regression Test

**Test file:** `Transit/TransitTests/CreateTaskIntentMilestoneTests.swift`
**Test name:** `taskCleanupDeletesPersistedTask`

**What it verifies:** That the cleanup mechanism (context.delete + context.save via projectService) correctly removes a persisted task from the database, validating the T-558 fix path.

**Run command:** `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -only-testing:TransitTests/CreateTaskIntentMilestoneTests/taskCleanupDeletesPersistedTask`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Added import SwiftData; added task cleanup in setMilestone catch block |
| `Transit/TransitTests/CreateTaskIntentMilestoneTests.swift` | Added regression test for cleanup mechanism |
| `Transit/Transit/TransitApp.swift` | Fixed pre-existing build error (nonisolated(unsafe) for context capture in @Sendable closure) |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- When intent and MCP handler implement the same operation, review both for parity on error handling
- Consider extracting shared task creation logic (with milestone assignment and cleanup) into a common helper to avoid divergence

## Related

- T-260: Original fix that added milestone pre-resolution before task creation
- `MCP/MCPToolHandler.swift` lines 184-192: Reference implementation with correct cleanup
