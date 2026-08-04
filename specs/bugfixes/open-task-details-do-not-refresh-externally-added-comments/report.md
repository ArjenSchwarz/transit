# Bugfix Report: Open Task Details Do Not Refresh Externally Added Comments

**Date:** 2026-08-04
**Status:** Fixed

## Description of the Issue

An already-open task detail screen held comments in a one-time `@State` snapshot. Comments created or deleted by MCP in the shared app `ModelContext` were invisible until the detail screen was reopened. The Share action exported that same stale snapshot.

**Reproduction steps:**
1. Open a task detail screen.
2. Add or delete a comment through MCP while the screen remains open.
3. Observe that the visible comments and Share export do not change.

**Impact:** Agents and users could see and export obsolete task discussion data.

## Investigation Summary

- **Symptoms examined:** `TaskDetailView` only called `loadComments()` on appearance; `CommentsSection` only reloaded after its own local mutations.
- **Code inspected:** `TaskDetailView`, `CommentsSection`, `CommentService`, `TransitTask.shareText`, and the existing share-text tests.
- **Hypotheses tested:** The comment relation is CloudKit-compatible when queried from the child `Comment` side. `CommentService` already uses that query shape with chronological, UUID-tiebreaker ordering.

## Discovered Root Cause

The detail view used imperative snapshot state instead of a reactive SwiftData query. External mutations did not invoke either manual reload site, so neither the comment list nor `exportText` received current values.

**Defect type:** Stale state / missing observation.

**Why it occurred:** The original parent-owned binding fixed local Share consistency but did not observe mutations outside `CommentsSection`.

**Contributing factors:** The task-to-comments relationship is optional for CloudKit, so the query must be expressed on `Comment.task?.id` rather than from the optional to-many task relationship.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/TaskDetail/TaskDetailCommentQuery.swift` - adds the reusable task-scoped child-side SwiftData descriptor with deterministic `creationDate`, then UUID ordering.
- `Transit/Transit/Views/TaskDetail/TaskDetailView.swift` - installs that descriptor as `@Query` during view initialization and shares its current value with both rendering and Share export.
- `Transit/Transit/Views/TaskDetail/CommentsSection.swift` - consumes the parent query value and lets query observation replace manual reloads after local add/delete actions.

**Approach rationale:** `@Query` is SwiftUI's native reactive SwiftData mechanism and observes both MCP and UI changes in the shared context without timers, notifications, or duplicate fetching.

**Alternatives considered:**
- Reload on lifecycle events or timers - misses arbitrary external mutations and is wasteful.
- Pass mutable snapshot state through more callbacks - remains vulnerable to mutation paths that omit a callback.

## Regression Test

**Test file:** `Transit/TransitTests/ShareTextTests.swift`
**Test name:** `taskScopedCommentsReflectExternalInsertionDeletionAndKeepShareCurrent`

**What it verifies:** The exact descriptor installed by `TaskDetailView` excludes unrelated-task comments, reflects a locally saved agent insertion and deletion, and produces current Share text from each result.

**Run command:** `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -only-testing:TransitTests/ShareTextTests`

## Affected Files

| File | Change |
|---|---|
| `TaskDetailCommentQuery.swift` | Reactive task-scoped descriptor |
| `TaskDetailView.swift` | Replace snapshot with `@Query` |
| `CommentsSection.swift` | Remove redundant manual refetching |
| `ShareTextTests.swift` | Regression coverage retained from prior work |

## Verification

**Automated:**
- [x] Regression test passes (`TransitTests/ShareTextTests` on macOS)
- [x] Fast macOS unit suite passes (`make test-quick`)
- [x] Linters/validators pass (`make lint`)
- [ ] Full iOS suite has three unrelated existing UI failures: `TransitUITests.testClearAll()`, `TransitUITests.testEditViewPreservesTaskMilestone()`, and `DataMaintenanceUITests.testDataMaintenanceGoldenPath()` (1,246 passed / 3 failed). The same three failures recur in `make test-ui`; no T-1800/ShareText test failed.

**Manual verification:** Open a task detail screen, mutate comments through MCP, and confirm the list and Share sheet update without reopening.

## Prevention

- Detail data shared with an export action should derive from a reactive store query, not an independently refreshed snapshot.
- Reuse the exact descriptor in query-contract tests when a SwiftUI property wrapper cannot be rendered in a unit test host.

## Related

- T-1800
