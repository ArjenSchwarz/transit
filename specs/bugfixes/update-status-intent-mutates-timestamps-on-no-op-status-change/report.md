# Bugfix Report: Update Status Intent Mutates Timestamps on No-Op Status Change

**Date:** 2026-03-13
**Status:** Fixed
**Ticket:** T-440

## Description of the Issue

Calling Update Status with a task's current status still flowed through `StatusEngine.applyTransition`, which rewrote `lastStatusChangeDate` and, for terminal statuses, `completionDate`.

**Reproduction steps:**
1. Create a task and move it to Done or Abandoned
2. Record its `lastStatusChangeDate` and `completionDate`
3. Call the App Intent or MCP `update_task_status` tool with the same status the task already has
4. Observe the timestamps change even though the status does not

**Impact:** Tasks reorder unexpectedly, and done/abandoned tasks can remain visible in the 48-hour completed filter because their completion timestamp is refreshed by a no-op update.

## Investigation Summary

Systematic tracing focused on the public status-update entry points and the shared service layer.

- **Symptoms examined:** no-op App Intent and MCP status updates changing task ordering and terminal visibility windows
- **Code inspected:** `Transit/Transit/Intents/UpdateStatusIntent.swift`, `Transit/Transit/MCP/MCPToolHandler.swift`, `Transit/Transit/Services/TaskService.swift`, `Transit/Transit/Services/StatusEngine.swift`, `Transit/Transit/Views/Dashboard/DashboardView.swift`
- **Hypotheses tested:** missing no-op guard in callers; missing guard in service layer; status engine semantics causing timestamp mutation on unchanged status

## Discovered Root Cause

`UpdateStatusIntent` and MCP `update_task_status` both delegate unchanged statuses to `TaskService.updateStatus`, which unconditionally calls `StatusEngine.applyTransition`. `StatusEngine.applyTransition` always updates `lastStatusChangeDate` and resets `completionDate` for terminal statuses, so unchanged status requests still mutate task timestamps.

**Defect type:** Missing guard

**Why it occurred:** The service layer treated every call to `updateStatus` as a real state transition and relied on callers to avoid no-op requests. The dashboard drag/drop path already had a same-column no-op check, but the App Intent and MCP paths did not.

**Contributing factors:** `StatusEngine` is intentionally side-effectful for real transitions, so any caller that reaches it without first validating the change will rewrite timestamps.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/TaskService.swift` — Added a no-op guard to `updateStatus` so unchanged status requests return before `StatusEngine.applyTransition` mutates timestamps or terminal completion dates
- `Transit/TransitTests/TaskServiceTests.swift` — Added regression coverage proving service-level no-op status updates preserve `lastStatusChangeDate` and `completionDate`
- `Transit/TransitTests/UpdateStatusIntentTests.swift` — Added App Intent regression coverage for same-status terminal updates
- `Transit/TransitTests/MCPToolHandlerTests.swift` — Added MCP `update_task_status` regression coverage for same-status terminal updates

**Approach rationale:** Guarding `TaskService.updateStatus` fixes the issue at the shared business-logic layer used by App Intent, MCP, and other callers, avoiding duplicated checks in multiple entry points. This keeps `StatusEngine` focused on applying real transitions while ensuring no-op requests do not reorder tasks or refresh completion windows.

**Alternatives considered:**
- Guarding only `UpdateStatusIntent` and `MCPToolHandler` — would fix the reported entry points but duplicate logic and leave other service callers vulnerable
- Guarding inside `StatusEngine.applyTransition` — central but less explicit about whether a caller intended to perform a real transition

## Regression Test

**Test files:** `Transit/TransitTests/TaskServiceTests.swift`, `Transit/TransitTests/UpdateStatusIntentTests.swift`, `Transit/TransitTests/MCPToolHandlerTests.swift`
**Test names:** `updateStatusNoOpPreservesTimestamps`, `noOpUpdatePreservesTerminalTimestamps`, `updateStatusNoOpPreservesTerminalTimestamps`

**What it verifies:** No-op status updates through the service, App Intent, and MCP handler preserve `lastStatusChangeDate` and `completionDate` for terminal tasks.

**Run command:** `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -configuration Debug -derivedDataPath ./DerivedData -only-testing:TransitTests/TaskServiceTests -only-testing:TransitTests/UpdateStatusIntentTests -only-testing:TransitTests/MCPToolHandlerTests | xcbeautify`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/TaskService.swift` | Added no-op guard before applying status transition side effects |
| `Transit/TransitTests/TaskServiceTests.swift` | Added no-op timestamp regression coverage |
| `Transit/TransitTests/UpdateStatusIntentTests.swift` | Added App Intent no-op timestamp regression coverage |
| `Transit/TransitTests/MCPToolHandlerTests.swift` | Added MCP no-op timestamp regression coverage |

## Verification

**Automated:**
- [x] Regression test passes
- [ ] Full test suite passes — blocked by pre-existing failures in `TaskEditSaveErrorTests`, `ProjectEditSaveErrorTests`, `ActionButtonSaveErrorTests`, `PromotionRollbackTests`, and `TransitUITests.testClearAll`
- [ ] Linters/validators pass — blocked by pre-existing `type_body_length` violation in `Transit/TransitTests/TaskEditSaveErrorTests.swift`

**Manual verification:**
- Confirmed the new regression tests fail before the fix because timestamps are rewritten on same-status updates.

## Prevention

**Recommendations to avoid similar bugs:**
- Treat status updates as no-ops unless the requested status actually differs from the current status
- Keep no-op guards in the shared service layer when multiple entry points delegate to the same transition logic
- Add regression tests for public automation entry points whenever timestamp side effects affect sorting or filtering

## Related

- Transit ticket: T-440
- Full regression command run: `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -configuration Debug -derivedDataPath ./DerivedData -only-testing:TransitTests/TaskServiceTests -only-testing:TransitTests/UpdateStatusIntentTests -only-testing:TransitTests/MCPToolHandlerTests | xcbeautify`
- Full suite attempts: `make test-quick` and `make test`
