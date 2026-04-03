# Bugfix Report: milestone-update-non-atomic

**Date:** 2026-04-03
**Status:** In Progress
**Ticket:** T-626

## Description of the Issue

`UpdateMilestoneIntent` applies status changes and field updates (name, description) as two independent operations. When the field update fails (e.g., duplicate name or empty name), the status change has already been persisted and is not rolled back.

**Reproduction steps:**
1. Create two milestones in the same project: "v1.0" (displayId 1) and "v2.0" (displayId 2)
2. Call `UpdateMilestoneIntent.execute` with `{"displayId":2,"name":"v1.0","status":"done"}` (rename to duplicate + status change)
3. The intent returns a `DUPLICATE_MILESTONE_NAME` error
4. Observe that milestone 2's status has changed to "done" despite the error

**Impact:** Medium. Partial updates leave milestones in an inconsistent state when field updates fail alongside status changes.

## Investigation Summary

- **Symptoms examined:** Status persists even when the overall operation fails
- **Code inspected:** `UpdateMilestoneIntent.swift` (execute, applyStatusChange, applyFieldUpdates), `MilestoneService.swift` (updateStatus, updateMilestone), `MCPToolHandler.swift` (handleUpdateMilestone)
- **Hypotheses tested:** The MCP handler for `update_milestone` was checked for the same bug -- it already uses a validate-then-apply-atomically pattern (T-391), confirming the correct approach

## Discovered Root Cause

In `UpdateMilestoneIntent.execute()`, `applyStatusChange()` calls `milestoneService.updateStatus()` which saves the model context immediately. Then `applyFieldUpdates()` calls `milestoneService.updateMilestone()` which can fail (duplicate name, empty name). By that point, the status change is already persisted.

**Defect type:** Non-atomic multi-step mutation

**Why it occurred:** The intent was built with two independent helper methods that each call their own service method with its own save. There was no validation-before-mutation phase.

**Contributing factors:** The MCP handler was fixed for the same pattern in T-391, but the App Intent was not updated to match.

## Resolution for the Issue

_To be filled in after fix is implemented._

## Regression Test

**Test file:** `Transit/TransitTests/UpdateMilestoneIntentTests.swift`
**Test names:** `statusNotAppliedWhenFieldUpdateFails`, `statusNotAppliedWhenNameIsEmpty`

**What it verifies:** When a combined status + field update is requested and the field update fails, the milestone's status remains unchanged.

**Run command:** `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -only-testing:TransitTests/UpdateMilestoneIntentTests test`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/UpdateMilestoneIntent.swift` | Reorder to validate before applying |
| `Transit/TransitTests/UpdateMilestoneIntentTests.swift` | Add regression tests |

## Verification

**Automated:**
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- Follow the validate-then-apply pattern used by the MCP handler (T-391)
- When an intent modifies multiple fields, validate all inputs before mutating any state
- Consider adding a shared validation helper that both the Intent and MCP handler can use

## Related

- T-626: UpdateMilestoneIntent applies status even when field update fails
- T-391: MCP update_milestone partial apply fix (already resolved)
- `specs/bugfixes/mcp-update-milestone-partial-apply/` -- the MCP equivalent of this bug
