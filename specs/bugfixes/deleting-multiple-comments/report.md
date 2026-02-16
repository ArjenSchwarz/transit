# Bugfix Report: Deleting Multiple Comments

**Date:** 2026-02-16
**Status:** Fixed

## Description of the Issue

When a user swipes to delete multiple comments simultaneously on iOS (via the `onDelete` modifier), the app could crash with an index-out-of-bounds error or silently delete the wrong comments.

**Reproduction steps:**
1. Create a task with 3+ comments
2. On iOS, enter edit mode on the comments list
3. Select multiple comments and tap delete (or swipe-delete triggers `onDelete` with multiple offsets)
4. Observe crash or wrong comments deleted

**Impact:** Medium severity. On iOS, batch deletion of comments is broken. Single-comment deletion (the common case) works fine. macOS uses a per-row delete button, which is unaffected.

## Investigation Summary

The ticket description pointed directly at `CommentsSection.swift` and the `onDelete` handler pattern.

- **Symptoms examined:** Array mutation during iteration over `IndexSet` offsets
- **Code inspected:** `CommentsSection.swift` (view), `CommentService.swift` (service layer)
- **Hypotheses tested:** The only hypothesis was the one described in the ticket, confirmed by code inspection

## Discovered Root Cause

The iOS `onDelete` handler iterated over offsets and called `deleteComment()` for each one. `deleteComment()` called `commentService.deleteComment()` (which saves to SwiftData) and then `loadComments()`, which re-fetched and replaced the `comments` array. After the first deletion and reload, subsequent offsets from the original `IndexSet` pointed to shifted positions in the now-shorter array.

**Defect type:** Array mutation during iteration

**Why it occurred:** The `deleteComment()` helper was designed for single-comment deletion (it reloads immediately), but was called in a loop from `onDelete` which can provide multiple offsets.

**Contributing factors:** The macOS path uses per-row delete buttons (single deletion), so this bug only manifested on iOS where SwiftUI's `onDelete` passes an `IndexSet` that can contain multiple indices.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/CommentService.swift` — Added `deleteComments(_:)` batch method that deletes all comments before saving once
- `Transit/Transit/Views/TaskDetail/CommentsSection.swift` — Added `deleteComments(at:)` method that maps offsets to comment objects before any mutation, then calls the batch delete, then reloads once. Changed `onDelete` to call this new method.

**Approach rationale:** Mapping offsets to objects before any mutation ensures indices are resolved against the original array. Batching into a single save is more efficient and avoids intermediate states.

**Alternatives considered:**
- Iterating offsets in descending order — Would prevent index shifting, but still does N saves and N reloads instead of one. More fragile.
- Mapping offsets to UUIDs and deleting by ID lookup — Correct but adds unnecessary fetch overhead when we already have the objects.

## Regression Test

**Test file:** `Transit/TransitTests/CommentServiceTests.swift`
**Test names:** `deleteComments_batchRemovesCorrectItems`, `deleteComments_emptyArrayIsNoOp`

**What it verifies:** Creating three comments (A, B, C), batch-deleting the first and third, and confirming only B remains. Also verifies that an empty array is a safe no-op.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/CommentService.swift` | Added `deleteComments(_:)` batch method |
| `Transit/Transit/Views/TaskDetail/CommentsSection.swift` | Added `deleteComments(at:)`, changed `onDelete` handler |
| `Transit/TransitTests/CommentServiceTests.swift` | Added two regression tests |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

**Manual verification:**
- Built successfully for both macOS and iOS

## Prevention

**Recommendations to avoid similar bugs:**
- When using SwiftUI's `onDelete`, always map `IndexSet` offsets to stable identifiers (objects or UUIDs) before performing any mutations
- Avoid calling reload/refresh inside a loop that depends on the collection being stable
- Prefer batch operations on the service layer when multiple items need to be deleted

## Related

- Transit ticket: T-85
