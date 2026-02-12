# PR Review Overview - Iteration 1

**PR**: #6 | **Branch**: T-4/shortcuts-friendly-intents | **Date**: 2026-02-12

## Valid Issues

### Code-Level Issues

#### Issue 1: Merge conflict marker in CHANGELOG.md
- **File**: `CHANGELOG.md:15`
- **Reviewer**: Automated review
- **Comment**: Leftover Git merge conflict marker `>>>>>>> origin/main` was committed
- **Validation**: Confirmed — line 15 has the conflict marker, corrupting the changelog

#### Issue 2: Wrong string interpolation in TaskServiceTests.swift
- **File**: `Transit/TransitTests/TaskServiceTests.swift:106`
- **Reviewer**: Automated review
- **Comment**: Uses `\\(error)` (double backslash) instead of `\(error)` for string interpolation
- **Validation**: Confirmed — the escaped backslash renders as literal `\(error)` at runtime instead of interpolating the error value

#### Issue 3: Wrong error type in TaskService.createTask(projectID:)
- **File**: `Transit/Transit/Services/TaskService.swift:41`
- **Reviewer**: Automated review
- **Comment**: Throws `Error.taskNotFound` when a Project lookup fails, but the missing entity is a Project
- **Validation**: Confirmed — the guard catches a missing project but throws `.taskNotFound`. Need to add `.projectNotFound` case.

### PR-Level Issues

#### Issue 4: Compare custom-range bounds at day granularity
- **File**: `Transit/Transit/Intents/Visual/FindTasksIntent.swift:227`
- **Reviewer**: @chatgpt-codex-connector (P2)
- **Comment**: `buildDateRange` rejects custom range when `from > toDate` using raw `Date` values, but `dateInRange` normalizes both bounds to start-of-day. Same-day dates with different times would be incorrectly rejected.
- **Validation**: Confirmed — `dateInRange` normalizes via `calendar.startOfDay(for:)` at lines 84-94, but `buildDateRange` compares raw dates at line 227. A same-day range like (Feb 12 10:00, Feb 12 08:00) would be rejected despite being valid at day granularity.

#### Issue 5: Apply result cap after entity conversion
- **File**: `Transit/Transit/Intents/Visual/FindTasksIntent.swift:200-205`
- **Reviewer**: @chatgpt-codex-connector (P2)
- **Comment**: The 200-result cap is applied before `TaskEntityQuery.entities(from:)`, which drops tasks without a valid project. Orphan tasks consume cap slots, reducing the valid result count.
- **Validation**: Confirmed — `TaskEntity.from` throws when `task.project` is nil, and the `try?` in `entities(from:)` silently drops these. Practical impact is low (orphan tasks are rare) but it's a correctness issue. Fix by moving the cap after conversion.

## Invalid/Skipped Issues

(None)
