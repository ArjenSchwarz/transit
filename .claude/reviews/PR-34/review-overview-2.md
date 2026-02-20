# PR Review Overview - Iteration 2

**PR**: #34 | **Branch**: T-153/bugfix-addtasksheet-dismisses-before-creation | **Date**: 2026-02-20

## Valid Issues

### Code-Level Issues

(None)

### PR-Level Issues

#### Issue 1: Cancel button not guarded during save
- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "`AddTaskSheet.swift` lines 45-48: `.interactiveDismissDisabled(isSaving)` blocks swipe-to-dismiss but does **not** prevent an explicit Cancel button tap. While a save is in-flight a user can tap the back chevron, which dismisses the sheet immediately. On the success path `dismiss()` becomes a harmless no-op; on the error path `errorMessage` is set on a view that is already gone, so the user never sees the alert."
- **Validation**: Valid. The Cancel button at line 46 calls `dismiss()` unconditionally. While `.interactiveDismissDisabled(isSaving)` (added in iteration 1) prevents swipe-to-dismiss, the explicit button tap bypasses that modifier. Adding `.disabled(isSaving)` to the Cancel button mirrors the existing guard on the Save button and closes this gap.

## Invalid/Skipped Issues

### Issue A: macOS layout has no second Save button (previous review concern resolved)
- **Location**: PR-level
- **Reviewer**: @claude
- **Comment**: "Reading `AddTaskSheet.swift` lines 117-193 confirms `macOSForm` does not have a second inline Save button."
- **Reason**: Reviewer explicitly confirms no action needed. Already flagged as invalid in iteration 1.

### Issue B: `createTaskWithEmptyNameThrowsInvalidName` uses a different overload
- **Location**: PR-level
- **Reviewer**: @claude
- **Comment**: "The added doc-comment now correctly explains this is testing the service-level contract, not the view path. That comment is sufficient."
- **Reason**: Already addressed in iteration 1 with a clarifying comment. Reviewer confirms the fix is sufficient.

### Issue C: `makeProject` skips `context.save()`
- **Location**: PR-level
- **Reviewer**: @claude
- **Comment**: "With an in-memory store this is fine. Low priority; would only matter if a test ever used a separate read context."
- **Reason**: No functional impact. Reviewer marks as low priority. Already noted as not-an-issue in iteration 1.
