# Bugfix Report: create-task-intent-milestone-failure

**Date:** 2026-02-26
**Status:** Fixed

## Description of the Issue

When creating a task via `CreateTaskIntent` with a milestone parameter that doesn't exist (or belongs to a different project), the intent returns a `MILESTONE_NOT_FOUND` error JSON but the task is still persisted to SwiftData. This leaves an orphaned task even though the Shortcut/CLI reports failure.

**Reproduction steps:**
1. Call `CreateTaskIntent` with a valid project and task details, but an invalid `milestoneDisplayId` (e.g., 999)
2. The intent returns `{"error": "MILESTONE_NOT_FOUND", ...}`
3. Observe that the task was still created in the database despite the error response

**Impact:** Medium — CLI/agent callers that retry on failure will create duplicate tasks. The user sees an error but a task silently exists.

## Investigation Summary

The `execute()` method in `CreateTaskIntent` followed a create-then-validate pattern:
1. Task created via `taskService.createTask()` (persisted to SwiftData)
2. Milestone lookup attempted via `IntentHelpers.assignMilestone()`
3. If milestone lookup failed, error returned — but task already persisted

- **Symptoms examined:** Error response returned despite task being created
- **Code inspected:** `CreateTaskIntent.swift`, `IntentHelpers.assignMilestone()`, `MilestoneService`
- **Hypotheses tested:** Single root cause — ordering of operations (create before validate)

## Discovered Root Cause

**Defect type:** Logic error — incorrect operation ordering

**Why it occurred:** The original implementation created the task first (line 83), then attempted milestone assignment (line 96). This meant any milestone validation failure happened after the task was already persisted to SwiftData, with no rollback mechanism.

**Contributing factors:** SwiftData has no transaction rollback mechanism like traditional databases, so the create-then-validate pattern is inherently unsafe.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Intents/CreateTaskIntent.swift` — Moved milestone resolution before task creation. Extracted `resolveMilestone(from:in:using:)` helper that validates milestone existence and project match. Task is only created after milestone validation succeeds.

**Approach rationale:** Validate-then-create is the correct pattern when rollback isn't available. Pre-resolving the milestone ensures no task is created if the milestone doesn't exist.

**Alternatives considered:**
- Delete task on milestone failure — rejected because SwiftData deletions may sync via CloudKit, creating unnecessary churn
- Add SwiftData transaction support — not available in the framework

## Regression Test

**Test file:** `Transit/TransitTests/CreateTaskIntentMilestoneTests.swift`
**Test names:** `createTaskWithUnknownMilestoneDoesNotPersistTask`, `createTaskWithUnknownMilestoneNameDoesNotPersistTask`

**What it verifies:** When milestone lookup fails (by displayId or by name), no task is persisted to the model context.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Moved milestone resolution before task creation; extracted `resolveMilestone` helper |
| `Transit/TransitTests/CreateTaskIntentMilestoneTests.swift` | Added two regression tests verifying no orphaned task on milestone failure |
| `specs/bugfixes/create-task-intent-milestone-failure/report.md` | This report |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- Follow validate-then-create pattern for all intent operations that combine entity creation with relationship assignment
- Consider auditing `UpdateTaskIntent` for similar patterns (it updates an existing task, so less risky)

## Related

- Transit ticket: T-260
