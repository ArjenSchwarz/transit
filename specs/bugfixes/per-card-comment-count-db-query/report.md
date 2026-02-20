# Bugfix Report: Per-Card Comment Count DB Query

**Date:** 2026-02-20
**Status:** Fixed

## Description of the Issue

TaskCardView was calling `commentService.commentCount(for: task.id)` inside its `body` computed property. This executed a SwiftData `fetchCount` query with a predicate for every visible task card on every render cycle. On a board with 30+ tasks, this produced 30+ database queries per re-render. Errors from these queries were silently swallowed with `try?`.

**Reproduction steps:**
1. Open the dashboard with 30+ tasks
2. Observe that each TaskCardView body evaluation triggers a `fetchCount` query
3. Any UI interaction that causes a re-render repeats all N queries

**Impact:** Performance degradation on boards with many tasks. N+1 query pattern scales linearly with task count and multiplies with render frequency.

## Investigation Summary

- **Symptoms examined:** `commentService.commentCount(for:)` call on line 67 of TaskCardView.swift, inside the view body
- **Code inspected:** TaskCardView.swift, CommentService.swift, TransitTask.swift (model relationships), DashboardView.swift, ColumnView.swift
- **Hypotheses tested:** Checked whether the `comments` relationship on TransitTask could be used directly instead of a service query

## Discovered Root Cause

The comment count was fetched via `CommentService.commentCount(for:)` which creates a new `FetchDescriptor` and runs `modelContext.fetchCount()` on every call. Placing this in the view `body` meant it ran on every SwiftUI render cycle, for every visible card.

**Defect type:** Performance anti-pattern (N+1 queries in view body)

**Why it occurred:** The comment count display was added without considering that SwiftUI view bodies are re-evaluated frequently. A database query per card per render is an N+1 pattern.

**Contributing factors:** The `try?` silently swallowed errors, masking any issues. The TransitTask model already had a `comments` relationship that could provide the count without a separate query.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/Dashboard/TaskCardView.swift` - Replaced `commentService.commentCount(for: task.id)` with `task.comments?.count`, using the existing SwiftData relationship. Removed the now-unused `@Environment(CommentService.self)` dependency.

**Approach rationale:** TransitTask already has an `@Relationship(deleteRule: .cascade, inverse: \Comment.task) var comments: [Comment]?` relationship. Accessing `task.comments?.count` uses SwiftData's managed object graph rather than issuing a separate fetch query. This eliminates both the N+1 query pattern and the `try?` error swallowing.

**Alternatives considered:**
- **Pre-fetch counts as dictionary at dashboard level** - Single batch query, pass `[UUID: Int]` through the view hierarchy. More code changes for marginal benefit over the relationship approach. SwiftData also lacks GROUP BY, so batch counting requires fetching all Comment objects.
- **Move query to `.onAppear` with `@State`** - Runs once per card appearance instead of per render, but still N queries total. Adds state management complexity without eliminating the fundamental issue.
- **Denormalize count on TransitTask model** - Add a `commentCount` stored property. Requires CloudKit migration considerations and manual count maintenance. Over-engineered for a single-user app.

## Regression Test

**Test file:** `Transit/TransitTests/TaskCommentCountTests.swift`
**Test name:** `TaskCommentCountTests` (4 tests)

**What it verifies:** That `task.comments?.count` correctly reflects zero comments, added comments, and deleted comments -- the exact data path TaskCardView now uses for the comment badge.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/Dashboard/TaskCardView.swift` | Replaced `commentService.commentCount(for:)` with `task.comments?.count`; removed `CommentService` environment dependency |
| `Transit/TransitTests/TaskCommentCountTests.swift` | New regression test verifying relationship-based comment count |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

**Manual verification:**
- Build succeeds for macOS

## Prevention

**Recommendations to avoid similar bugs:**
- Avoid database queries in SwiftUI view bodies. Use relationships, `@Query`, or pre-fetched data instead.
- When a model already has a relationship, prefer accessing it directly over a separate service query for read-only counts/existence checks.
- Treat `try?` in view bodies as a code smell -- errors should be handled explicitly or the operation should be moved out of the render path.

## Related

- T-151: Per-card comment count DB query in TaskCardView body
- PR #29: Code audit quick-wins (identified but did not fix this issue)
