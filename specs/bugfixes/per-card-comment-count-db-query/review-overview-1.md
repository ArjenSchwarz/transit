# PR Review Overview - Iteration 1

**PR**: #35 | **Branch**: T-151/bugfix-per-card-comment-count-db-query | **Date**: 2026-02-20

## Valid Issues

### PR-Level Issues

#### Issue 1: Test 4 is redundant with Test 1

- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "`commentsRelationshipCount_isNilNotCount_whenNoRelationshipLoaded` asserts the same thing as test 1 (`commentsRelationshipCount_returnsZeroWhenNoComments`) — both end with `#expect(count == 0)` for a task with no comments. The difference is that test 4 skips `context.save()`, but in an in-memory context this distinction has no observable effect on relationship loading. The name implies it's testing lazy-load/faulting behaviour, but that can't be exercised through an in-memory container."
- **Validation**: Valid. Both tests create a task with no comments and assert count == 0. The only difference (save vs no save) is not observable in an in-memory SwiftData container. The test name misleadingly implies faulting behavior is being tested. Dropping the test removes noise from the suite.

## Invalid/Skipped Issues

### Issue A: SwiftData still faults on first access

- **Location**: PR-level
- **Reviewer**: @claude
- **Comment**: "`task.comments?.count` does not issue a `fetchCount` query — but the first access per task per context lifetime will trigger SwiftData to resolve the relationship fault..."
- **Reason**: Informational note, not an actionable change request. No code change needed.
