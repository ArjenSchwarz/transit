# Bugfix Report: Comments Don't Show Immediately

**Date:** 2026-02-16
**Status:** Fixed
**Transit Ticket:** T-73

## Description of the Issue

After adding a comment in the task detail view, the comment does not appear in the UI. The user must navigate away from the detail view, wait, and then navigate back for the comment to become visible.

**Reproduction steps:**
1. Open the Transit app and tap on a task to view its details
2. Type a comment and submit it
3. Observe that the comment does not appear in the comments list
4. Navigate back to the dashboard and re-open the task
5. The comment now appears

**Impact:** Poor user experience. Comments appear to not work, causing confusion about whether the action succeeded.

## Investigation Summary

The investigation traced the comment creation flow from the UI through the service layer, examining how SwiftData ModelContexts are used across the app.

- **Symptoms examined:** Comment is persisted (appears after navigation away/back) but not visible immediately after creation
- **Code inspected:** `TransitApp.swift` (context setup), `CommentsSection.swift` (view), `CommentService.swift` (service), `TaskDetailView.swift`, `DashboardView.swift`
- **Hypotheses tested:** Cross-context relationship issues between `mainContext` (used by `@Query`) and the separate `ModelContext` used by services

## Discovered Root Cause

`TransitApp.init()` creates a separate `ModelContext` (line 45) for all services, distinct from `container.mainContext` used by `@Query` in views. When a user taps a task card, the `TransitTask` object comes from `mainContext` (via `@Query` in `DashboardView`). This task is then passed to `CommentsSection`, which calls `commentService.addComment(to: task, ...)`.

Inside `CommentService.addComment`, the `Comment` was created with a relationship to the task from `mainContext`, but inserted into the service's separate context. This cross-context relationship meant the `fetchComments` predicate (`$0.task?.id == taskID`) could not resolve the relationship immediately because the task object was not registered in the service's context.

**Defect type:** Cross-context SwiftData relationship issue

**Why it occurred:** The `Comment` model was assigned a relationship to a `TransitTask` from a different `ModelContext`. SwiftData does not immediately resolve cross-context relationships, so the subsequent fetch query (which filters on the relationship) returned no results.

**Contributing factors:** Existing tests all used a single shared context for both the service and the task, so the cross-context scenario was never exercised.

## Resolution for the Issue

**Primary fix - `CommentService.swift`:**
Added a `resolveTask(_:)` private method that re-fetches the task from the service's own `ModelContext` by UUID before establishing the relationship. If the task is already registered in the service's context, it is returned directly (fast path).

**Secondary fix - `TaskService.swift`:**
Fixed a related pre-existing bug where `updateStatus(task:to:comment:)` checked `!comment.isEmpty` without trimming whitespace first. A whitespace-only comment would pass the emptiness check but then fail validation in `CommentService.addComment` (which trims before checking), causing the entire status update to roll back.

**Tertiary fix - `AddCommentIntent.swift` and `AddCommentIntentTests.swift`:**
Fixed a pre-existing compilation error in tests. The tests tried to access `@Dependency` property wrappers which are private. Refactored `AddCommentIntent` to expose a static `execute()` method (matching the pattern used by all other intents) for testability.

## Regression Test

**Test file:** `Transit/TransitTests/CommentServiceTests.swift`
**Test name:** `addComment_taskFromDifferentContext_immediatelyFetchable`

**What it verifies:** Creates a task in one `ModelContext` (simulating `mainContext` / `@Query`), adds a comment via `CommentService` using a separate `ModelContext`, and immediately fetches comments from the service. Asserts the comment is returned with the correct content.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/CommentService.swift` | Added `resolveTask(_:)` to re-fetch task in service's own context; added `taskNotFound` error case |
| `Transit/Transit/Services/TaskService.swift` | Fixed whitespace-only comment check to use trimmed comparison |
| `Transit/Transit/Intents/AddCommentIntent.swift` | Refactored to expose static `execute()` for testability |
| `Transit/TransitTests/CommentServiceTests.swift` | Added cross-context regression test; fixed `Project` init call |
| `Transit/TransitTests/AddCommentIntentTests.swift` | Rewritten to use `AddCommentIntent.execute()` pattern |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (624 tests, 0 failures)
- [x] Linters pass (0 violations)

**Manual verification:**
- Build succeeds for macOS target

## Prevention

- When SwiftData services receive model objects from callers, always resolve them in the service's own `ModelContext` before establishing relationships
- Test cross-context scenarios explicitly, not just same-context flows
- This pattern is documented in `docs/agent-notes/` for future reference

## Related

- Transit ticket: T-73
- CLAUDE.md note on `registeredModel(for:)` vs fetch (project memory)
