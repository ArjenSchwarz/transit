# Bugfix Report: MCP update_task leaves unsaved changes on save failure

**Date:** 2026-03-27
**Status:** Fixed
**Ticket:** T-531

## Description of the Issue

The MCP `update_task` tool handler called `milestoneService.setMilestone()` with `save: true` (the default), which persisted milestone changes immediately. It then called `projectService.context.save()` separately. If that second save failed, the handler returned an error but never called `safeRollback()`, leaving dirty in-memory state on the shared model context. This dirty state could later be persisted by an unrelated save, causing the caller's error response to be inconsistent with the actual data state.

**Reproduction scenario:**
1. Call `update_task` to assign a milestone to a task
2. The milestone assignment succeeds and is saved internally by `setMilestone`
3. The subsequent `context.save()` fails (e.g., due to a concurrent write conflict)
4. The handler returns an error, but the milestone assignment is already persisted
5. Alternatively, if there were other dirty state on the context, it would leak through

**Impact:** Data integrity issue. MCP clients receive an error response but the task may be partially modified. Inconsistent with the rollback-on-save-failure pattern used by all other handlers and services.

## Investigation Summary

- **Symptoms examined:** `handleUpdateTask` in `MCPToolHandler.swift` called `setMilestone(save: true)` which saved internally, then called `context.save()` again without rollback on failure.
- **Code inspected:** `MCPToolHandler.handleUpdateTask`, `MilestoneService.setMilestone`, `MCPToolHandler.handleUpdateMilestone` (correct reference pattern from T-391)
- **Pattern comparison:** `handleUpdateMilestone` (fixed in T-391) uses validate-then-apply with `save: false` on mutations and a single atomic `save()` with `safeRollback()` on failure. `handleUpdateTask` did not follow this pattern.

## Discovered Root Cause

**Defect type:** Missing rollback on save failure + non-atomic save pattern

**Why it occurred:** Two issues combined:
1. `setMilestone()` was called with its default `save: true`, causing it to persist changes independently before the handler's own save
2. The handler's `catch` block on `context.save()` returned an error without calling `safeRollback()`, violating the project's established save/rollback pattern

**Contributing factors:** The handler was written before the T-391 atomic update pattern was established. The `setMilestone` method defaults to `save: true` for standalone use, but handlers should pass `save: false` to defer saving.

## Resolution for the Issue

**Changes made:**

- `Transit/Transit/MCP/MCPToolHandler.swift` — Two fixes in `handleUpdateTask`:
  1. All three `setMilestone` call sites now pass `save: false`, deferring persistence to the handler's single atomic save
  2. Added `projectService.context.safeRollback()` in the `catch` block of the final `save()`, matching the pattern in `handleUpdateMilestone` and all service methods

- `Transit/Transit/TransitApp.swift` — Fixed pre-existing build error (unrelated to T-531): `ModelContext` captured in `@Sendable` closure caused "sending 'context' risks causing data races" compiler error. Used `nonisolated(unsafe)` since the context is MainActor-isolated and only used on MainActor.

**Approach rationale:** Matches the established atomic save pattern from T-391's `handleUpdateMilestone` fix. Mutations happen in memory, then a single `save()` persists everything atomically with `safeRollback()` on failure.

## Regression Test

**Test file:** `Transit/TransitTests/MCPUpdateTaskTests.swift`
**Tests added:**
- `setMilestoneByDisplayId` — verifies happy path for milestone assignment via update_task
- `clearMilestone` — verifies milestone can be cleared
- `milestoneProjectMismatchReturnsError` — verifies error returned and task not mutated on cross-project assignment
- `milestoneNotFoundReturnsError` — verifies error for nonexistent milestone
- `doesNotLeakDirtyStateOnMilestoneError` — T-531 regression test verifying no dirty context state after failed update
