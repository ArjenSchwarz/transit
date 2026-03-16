# Bugfix Report: mcp-update-status-noop-comment

**Date:** 2025-07-14
**Status:** Fixed

## Description of the Issue

When calling `update_task_status` via MCP with the same status the task already has (a no-op) plus a comment, the comment was silently ignored but the response included stale comment details from a previous comment — implying the new comment was added when it wasn't.

**Reproduction steps:**
1. Create a task and move it to "planning" status
2. Add a comment to the task (e.g. "Old comment")
3. Call `update_task_status` with status="planning" (same), comment="New note", authorName="Agent"
4. Observe the response contains the old comment's details, not the new one

**Impact:** MCP clients (agents) believe their comment was persisted when it was silently dropped. This breaks agent workflows that rely on comment confirmation in status update responses.

## Investigation Summary

- **Symptoms examined:** Response includes comment details that don't match the submitted comment text
- **Code inspected:** `MCPToolHandler.handleUpdateStatus`, `TaskService.updateStatus`, `validateCommentArgs`, `appendCommentDetails`
- **Hypotheses tested:** The short-circuit guard in TaskService.updateStatus was confirmed as the root cause

## Discovered Root Cause

**Defect type:** Logic error — early return skips comment persistence on no-op status

**Why it occurred:** `TaskService.updateStatus` had `guard task.status != newStatus else { return }` at line 122, which short-circuited the entire method including comment creation. Meanwhile, `MCPToolHandler.handleUpdateStatus` determined `hasComment=true` before calling `updateStatus` and never learned the comment was ignored. `appendCommentDetails` then fetched the last existing comment for the task, returning stale data.

**Contributing factors:** The comment logic was coupled inside the status-change guard rather than being independent. The method's original doc comment explicitly stated "Comment parameters passed with a no-op status request are ignored" — but the MCP handler didn't account for this.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/TaskService.swift:122` — Replaced early-return guard with a conditional: status transition only applies when status actually changes, but comment creation always executes regardless

**Approach rationale:** Comments are user-provided data that should always be persisted when explicitly submitted. Coupling comment persistence to status change was an unnecessary restriction. The fix decouples these concerns while preserving the no-op behavior for timestamps.

**Alternatives considered:**
- Suppress comment details in the MCP handler when status is unchanged — rejected because this still silently drops the user's comment
- Return `updateStatus` result indicating whether status changed — rejected as more invasive and still drops the comment

## Regression Test

**Test files:**
- `Transit/TransitTests/TaskServiceTests.swift` — `updateStatusNoOpWithCommentStillAddsComment`
- `Transit/TransitTests/MCPToolHandlerCommentTests.swift` — `updateStatusNoOpWithCommentReturnsNewComment`, `updateStatusNoOpWithoutCommentOmitsCommentDetails`

**What they verify:**
1. TaskService persists comments even when status is unchanged
2. MCP handler returns the newly added comment (not a stale one) on no-op with comment
3. MCP handler omits comment details on no-op without comment (no stale data leaks)

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/TaskService.swift` | Decouple comment persistence from status-change guard |
| `Transit/TransitTests/TaskServiceTests.swift` | Add regression test for no-op + comment |
| `Transit/TransitTests/MCPToolHandlerCommentTests.swift` | New file: regression tests for MCP comment response on no-op |

## Verification

**Automated:**
- [x] Regression tests pass
- [x] Full test suite passes (0 failures)
- [x] Linter passes (0 violations)

## Prevention

**Recommendations to avoid similar bugs:**
- When a method short-circuits, audit all callers to ensure they handle the no-op case
- Decouple independent side effects (comments) from the primary operation (status change)
- Test no-op paths with all optional parameter combinations

## Related

- Transit ticket: T-471
