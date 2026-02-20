# PR Review Overview - Iteration 1

**PR**: #31 | **Branch**: T-110/get-projects-mcp | **Date**: 2026-02-20

## Valid Issues

### PR-Level Issues

#### Issue 1: Unrelated cosmetic changes mixed into the diff
- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "The PR bundles functional work with two unrelated reformats in `MCPToolHandler.swift`: collapsing switch arms in `handleCreateTask`, renaming `isoFormatter` → `fmt` in `handleAddComment`."
- **Validation**: Confirmed. The diff includes cosmetic reformatting in `handleCreateTask` (switch arms collapsed to single lines, response dict collapsed, local variable inlined) and `handleAddComment` (variable rename, dict collapsed, MARK comment removed). These should be reverted to keep the diff focused.

#### Issue 2: `fmt` is a worse name than `isoFormatter`
- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "`isoFormatter` communicates what kind of formatter it is; `fmt` is opaque."
- **Validation**: Correct. `isoFormatter` is self-documenting. Reverting as part of Issue 1.

#### Issue 3: No test for `gitRepo` conditional inclusion
- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "It's worth a test that verifies `gitRepo` is absent when nil and present with the correct value when set."
- **Validation**: Valid. `MCPTestHelpers.makeProject` always passes `gitRepo: nil`, so no existing test exercises the presence path. Adding a test.

#### Issue 4: PR checklist items are unchecked
- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "`make test-quick` and `make lint` are marked unchecked in the test plan."
- **Validation**: Valid. Will run both and confirm they pass.

## Invalid/Skipped Issues

_None — all four issues are valid._
