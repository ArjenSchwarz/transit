# Bugfix Report: Create Task Paths Silently Ignore Non-Object Metadata

**Date:** 2026-08-02
**Status:** Investigating
**Transit ticket:** T-1991

## Description of the Issue

When the `metadata` key is present in JSON `CreateTaskIntent` input or an MCP
`create_task` request, callers can supply a string, array, number, boolean, or
null. Both create paths silently treat those values as omitted metadata and
successfully insert a task. This violates the documented contract that
`metadata` is an object and loses the caller's input without an error.

**Reproduction steps:**
1. Create a valid task request with `metadata` set to a non-object JSON value.
2. Send it through `CreateTaskIntent.execute` or MCP `tools/call` for
   `create_task`.
3. Observe a success response and a newly inserted task with empty metadata.

**Impact:** Automation callers receive a misleading success response and may
believe metadata was persisted when it was discarded. The bug affects both
JSON/App Intent and macOS MCP integrations.

## Investigation Summary

The investigation followed the systematic debugging workflow:

- **Phase 1 — Initial overview:** The expected behavior is field-specific
  rejection before mutation for every non-object shape, while an omitted key
  remains valid. The actual behavior is successful insertion with no metadata.
- **Phase 2 — Systematic inspection:** `CreateTaskIntent.execute` validates
  required fields and then passes `json["metadata"]` to
  `IntentHelpers.stringMetadata`; `MCPToolHandler.handleCreateTask` follows
  the same pattern with `args["metadata"]`. The helper returns `nil` for
  non-dictionaries, and `TaskService.createTask` treats `nil` as omitted
  metadata. No caller checks whether the key was present first.
- **Phase 3 — Root cause analysis:** The shared helper intentionally filters
  values inside a valid object for T-723, but its `nil` result conflates
  absent metadata, empty/all-non-string objects, and invalid top-level shapes.
  The create callers never distinguish those cases before task creation.
- **Phase 4 — Proposed solution:** Add a present-key container-shape check in
  each create path before project/milestone resolution and insertion. Return
  `INVALID_INPUT` with `metadata must be an object` from the intent and an MCP
  tool error with the same field-specific message. Continue routing valid
  object values through `stringMetadata` so non-string entries inside the
  object remain dropped under T-723.

## Discovered Root Cause

`IntentHelpers.stringMetadata(from:)` accepts only dictionaries and returns
`nil` for all other values. Both create paths pass that result directly to
`TaskService.createTask`, where `nil` means no metadata was supplied. Because
presence is not validated separately, a malformed present value is
indistinguishable from omission.

**Defect type:** Missing input validation / data-flow ambiguity.

**Why it occurred:** The helper was designed to preserve the T-723 behavior
of dropping non-string entries inside valid metadata objects, but callers used
its optional output as both parser and validator. That made invalid container
shapes silently follow the omission path.

**Contributing factors:** Existing tests covered valid objects and mixed values
inside objects, but did not cover malformed top-level metadata shapes or
assert no mutation on rejection.

## Resolution for the Issue

_To be completed after the regression tests and implementation pass._

## Regression Test

**Test file:** `Transit/TransitTests/CreateTaskMetadataShapeValidationTests.swift`

**Test names:**
- `createTaskIntentRejectsEveryNonObjectMetadataShapeWithoutMutation`
- `mcpCreateTaskRejectsEveryNonObjectMetadataShapeWithoutMutation`

**What it verifies:** A present metadata string, array, number, boolean, or
null is rejected with a field-specific error and neither surface inserts a
task. Existing T-723 tests continue to verify that non-string values inside a
valid object are dropped.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/TransitTests/CreateTaskMetadataShapeValidationTests.swift` | Add symmetric regression and no-mutation coverage for both create paths. |
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Add present-key metadata object validation. |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Add present-key metadata object validation. |
| `CHANGELOG.md` | Add an unreleased fixed entry for T-1991. |
| `specs/bugfixes/create-task-paths-silently-ignore-non-object-metadata/report.md` | Record investigation, resolution, and verification. |

## Verification

**Automated:**
- [ ] Regression tests fail before the fix and pass after it.
- [ ] Full test suite passes.
- [ ] Linters/validators pass.

**Manual verification:**
- [ ] Confirm omitted metadata still creates a task.
- [ ] Confirm a valid object still preserves string values and drops
  non-string values under T-723.

## Prevention

- Validate presence and top-level shape before passing optional parsed values to
  mutating service methods.
- Keep symmetric App Intent/MCP regression tests for equivalent JSON contracts.
- Continue treating non-string entries inside a valid metadata object according
  to the established T-723 contract.

## Related

- Transit ticket T-1991
- T-723: MCP create_task drops non-string metadata values inside valid objects
