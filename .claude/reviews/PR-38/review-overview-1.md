# PR Review Overview - Iteration 1

**PR**: #38 | **Branch**: T-173/bugfix-dashboard-status-context-mismatch | **Date**: 2026-02-20

## Valid Issues

### PR-Level Issues

#### Issue 1: CommentService.resolveTask() docstring is misleading

- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "After this fix, both the view and `CommentService` use the same `mainContext`, so the 'separate context' explanation is no longer accurate. The `resolveTask()` fast-path (`registeredModel(for:)`) will always succeed now, making the re-fetch fallback dead code. The workaround is harmless but the docstring will confuse anyone who reads it next. Worth updating the comment to reflect the current invariant -- or removing `resolveTask()` entirely now that both parties share a context."
- **Validation**: Valid. The `addComment` docstring (lines 20-25) explicitly says "this service uses a separate context" which is no longer true after the fix. The `resolveTask()` private method's docstring (line 101) also says "Re-fetches a task from this service's ModelContext" implying cross-context re-fetch. Both should be updated. Keeping `resolveTask()` as a safety net is reasonable, but the docstrings must match reality.

#### Issue 2: rollback() in updateStatus now has broader blast radius

- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "Before this fix, each service had its own context, so `modelContext.rollback()` on error only discarded that service's unsaved changes. Now that all services share `mainContext`, a rollback in `updateStatus` will also discard any other unsaved mutations on `mainContext` at that moment."
- **Validation**: Valid as an awareness note. The reviewer acknowledges this is "probably fine" but the behavioral change is worth documenting with a code comment for future developers. A brief inline comment at the rollback site is sufficient.

## Invalid/Skipped Issues

### Issue A: Regression test design note

- **Location**: PR-level
- **Reviewer**: @claude
- **Comment**: Notes about the test using its own ModelContainer and `@Suite(.serialized)` scope.
- **Reason**: Informational feedback, no change requested. The reviewer confirms the test design is intentional and justified.

### Issue B: ProjectServiceTests.swift fix is correct

- **Location**: PR-level
- **Reviewer**: @claude
- **Comment**: Confirms the `project.id` capture fix is correct for Swift 6.
- **Reason**: Positive feedback, no action needed.

### Issue C: Documentation additions are good

- **Location**: PR-level
- **Reviewer**: @claude
- **Comment**: Approves the new section in technical-constraints.md.
- **Reason**: Positive feedback, no action needed.

### Issue D: Manual test still pending

- **Location**: PR-level
- **Reviewer**: @claude
- **Comment**: Test plan has unchecked item for drag-and-drop + force-quit verification.
- **Reason**: Manual testing item, cannot be addressed via code changes. Requires physical device interaction.
