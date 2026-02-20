# PR Review Overview - Iteration 1

**PR**: #33 | **Branch**: T-154/bugfix-projecteditview-silent-save-errors | **Date**: 2026-02-20

## Valid Issues

### PR-Level Issues

#### Issue 1: Alert title inconsistency between ProjectEditView and TaskEditView
- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "ProjectEditView uses `\"Error\"` as the alert title, while TaskEditView uses `\"Save Failed\"`. This inconsistency predates this PR, but since the fix adds a new error code path to ProjectEditView, it's worth considering whether to align them at the same time."
- **Validation**: Confirmed. ProjectEditView line 26/33 uses `"Error"`, TaskEditView line 33 uses `"Save Failed"`. Since this PR adds a new save-failure alert path to ProjectEditView, aligning the title to `"Save Failed"` is a low-risk improvement that keeps the codebase consistent.

#### Issue 2: Add comment explaining post-rollback form state behaviour
- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "After `modelContext.rollback()`, the underlying `project` model reverts to its last-persisted values, but the `@State` variables (`name`, `projectDescription`, `gitRepo`, `color`) retain the user's in-progress edits. [...] Worth a brief comment in the code since this is a subtle point and the asymmetry could look like a bug to a future reader."
- **Validation**: Confirmed. In `save()` lines 173-179, `rollback()` reverts the model but `@State` is unaffected by SwiftData rollback. This asymmetry is intentional (user can retry without re-typing) but non-obvious. A brief comment clarifies the design intent.

#### Issue 3: Clarify test suite docstring about scope
- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "The regression tests verify that `modelContext.rollback()` reverts direct property mutations, which is the mechanism the fix relies on. They don't test the view's `save()` method itself [...] the suite's docstring could make this distinction explicit to avoid misleading future readers into thinking the view's error-alert path is covered."
- **Validation**: Confirmed. The current docstring ("The fix ensures save() uses do/catch instead of try?...") implies the tests cover the view's save() method directly. In reality, the tests verify the underlying SwiftData rollback guarantee. Clarifying this prevents misinterpretation.

## Invalid/Skipped Issues

None.
