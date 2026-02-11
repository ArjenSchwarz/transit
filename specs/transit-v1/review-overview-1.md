# PR Review Overview - Iteration 1

**PR**: #2 | **Branch**: feature/transit-v1 | **Date**: 2026-02-11

## Valid Issues

### Code-Level Issues

#### Issue 1: Use full status label in task detail view
- **File**: `Transit/Transit/Views/TaskDetail/TaskDetailView.swift:45`
- **Reviewer**: @chatgpt-codex-connector (P2)
- **Comment**: `task.status.shortLabel` collapses multiple states — `readyForReview` becomes "Active" and `abandoned` becomes "Done". The detail view should show the canonical status.
- **Validation**: Confirmed. `shortLabel` maps by dashboard column, so `readyForImplementation` → "Spec", `readyForReview` → "Active", `abandoned` → "Done". The `displayName` property exists and returns the full label (e.g., "Ready for Review", "Abandoned"). A detail sheet should show the exact status.

#### Issue 2: Avoid returning null displayId from create intent
- **File**: `Transit/Transit/Intents/CreateTaskIntent.swift:90`
- **Reviewer**: @chatgpt-codex-connector (P1)
- **Comment**: `task.permanentDisplayId` is nil in provisional mode (CloudKit unavailable), so the intent returns `"displayId": null`. `UpdateStatusIntent` requires an integer `displayId`, breaking create→update workflows offline.
- **Validation**: Confirmed. `TaskService.createTask` falls back to `.provisional` when `allocateNextID()` throws. The response includes `taskId` (UUID) which is always present, but `UpdateStatusIntent` only accepts `displayId` (integer). Fix: accept `taskId` as alternative lookup in `UpdateStatusIntent`. Also applies to `QueryTasksIntent:110` which has the same `permanentDisplayId as Any` pattern.

## Invalid/Skipped Issues

_None._
