# Bugfix Report: Share Export Missing Comments

**Date:** 2026-02-16
**Status:** Fixed

## Description of the Issue

When a user adds a comment in the task detail view and then immediately taps the share button, the exported text may not include the newly added comment. The share export uses stale comment data that was loaded when the view first appeared.

**Reproduction steps:**
1. Open a task's detail view
2. Add a new comment
3. Tap the share button immediately
4. Observe that the exported text does not include the comment just added

**Impact:** Medium severity. Users sharing task details get incomplete information, missing recent comments. Affects both iOS and macOS.

## Investigation Summary

The task detail view and comments section each maintained their own independent copies of the comments array, loaded separately from `CommentService`.

- **Symptoms examined:** Share export text missing recently added comments
- **Code inspected:** `TaskDetailView.swift`, `CommentsSection.swift`, `CommentService.swift`, `TransitTask.shareText(comments:)`
- **Hypotheses tested:** The model layer (`shareText(comments:)`) and service layer (`CommentService`) are correct. The bug is in the view layer's state management.

## Discovered Root Cause

`TaskDetailView` and `CommentsSection` both declared their own `@State private var comments: [Comment] = []` and loaded comments independently via `onAppear`. When `CommentsSection` added or deleted a comment, it updated its own local state but `TaskDetailView.comments` remained stale. The `exportText` computed property read `TaskDetailView.comments`, so `ShareLink` rendered with outdated data.

**Defect type:** Duplicate state / state synchronisation error

**Why it occurred:** `CommentsSection` was designed as a self-contained component with its own data loading. When `TaskDetailView` later needed access to comments for the share feature, a second `comments` state was added without unifying the two.

**Contributing factors:** SwiftUI's `ShareLink` evaluates its `item` parameter when the view body is computed, not when the user taps share. This means stale state is baked into the UI until a re-render occurs.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/TaskDetail/CommentsSection.swift` - Changed `@State private var comments` to `@Binding var comments`, removed `onAppear { loadComments() }` from both iOS and macOS layouts. The `loadComments()` and mutation methods now write through the binding.
- `Transit/Transit/Views/TaskDetail/TaskDetailView.swift` - Pass `$comments` binding to `CommentsSection(task:comments:)` at both call sites (iOS and macOS).

**Approach rationale:** Lifting state to the parent (`TaskDetailView`) and passing a binding to the child (`CommentsSection`) is the standard SwiftUI pattern for shared state. When `CommentsSection` adds or deletes a comment, it calls `loadComments()` which writes to the binding, triggering a re-render of `TaskDetailView` and updating `exportText` for `ShareLink`.

**Alternatives considered:**
- Fetch comments fresh inside `exportText` - Rejected because `exportText` is a computed property evaluated during view rendering, not on tap. Would still be stale without a re-render trigger.
- Use `onChange` or `NotificationCenter` to notify `TaskDetailView` - Rejected as unnecessarily indirect. A binding is simpler and idiomatic.

## Regression Test

**Test file:** `Transit/TransitTests/ShareTextTests.swift`
**Test names:** `shareTextIncludesComments`, `shareTextOmitsCommentsSectionWhenEmpty`, `shareTextIncludesNewlyAddedComment`

**What it verifies:** That `shareText(comments:)` includes comment content when comments are provided, omits the comments section when empty, and that freshly fetched comments after an add appear in the export.

**Run command:** `make test-quick` or `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -only-testing:TransitTests/ShareTextTests test`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/TaskDetail/CommentsSection.swift` | Changed `comments` from `@State` to `@Binding`, removed self-contained `onAppear` loading |
| `Transit/Transit/Views/TaskDetail/TaskDetailView.swift` | Pass `$comments` binding to `CommentsSection` |
| `Transit/TransitTests/ShareTextTests.swift` | Added 3 regression tests for comments in share text |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

**Manual verification:**
- Build succeeds on both macOS and iOS targets

## Prevention

**Recommendations to avoid similar bugs:**
- When two views need the same data, use a single source of truth with bindings rather than independent `@State` + `onAppear` loading in each view.
- When adding share/export features that depend on mutable data, verify the data flows from the same state that the editing UI modifies.

## Related

- T-73: Comments don't show up immediately (related cross-context issue, different root cause)
