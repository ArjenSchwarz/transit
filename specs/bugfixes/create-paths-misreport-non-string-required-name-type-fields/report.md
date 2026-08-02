# Bugfix Report: Create paths misreport non-string required name/type fields

**Date:** 2026-08-02
**Status:** Fixed

## Description of the Issue

The MCP and JSON-based App Intent create paths use a conditional `as? String` cast to validate required fields. When a caller supplies `name` or `type` with a numeric, boolean, array, object, or null value, the cast fails and the request is incorrectly reported as missing the field. The request contract requires a field-specific type error instead, and invalid input must not create a record.

**Reproduction steps:**
1. Call MCP `create_task` with `name: 123` or `type: false`, or invoke `CreateTaskIntent` with the equivalent JSON.
2. Call MCP `create_milestone` or `CreateMilestoneIntent` with `name: null` (or another non-string JSON value).
3. Observe the generic missing-field error instead of `name must be a string` / `type must be a string`.

**Impact:** MCP clients and Shortcuts callers receive misleading validation errors for malformed create requests. The affected records are not currently created for the required-field cases, but callers cannot distinguish omission from invalid input and cannot reliably diagnose their request.

## Investigation Summary

- **Symptoms examined:** Required field values present with non-string JSON types were collapsed into existing missing-field errors.
- **Code inspected:** `MCPToolHandler.handleCreateTask`, `MCPToolHandler.handleCreateMilestone`, `CreateTaskIntent.validateInput`, `CreateMilestoneIntent.execute`, their dispatch/callers, and existing T-1192/T-1453/T-1579 validation regressions.
- **Hypotheses tested:** The defect is isolated to presence/type validation order; service creation and rollback paths are not reached for malformed required fields. Existing optional-field and update validation already demonstrates the intended presence-first pattern.

## Discovered Root Cause

**Defect type:** Missing validation / data-flow type mismatch.

**Why it occurred:** `as? String` returns `nil` for both an absent dictionary key and a present value of the wrong type. The create paths used that result directly in `guard let` statements, so both cases entered the missing-field branch.

**Contributing factors:** The MCP argument dictionaries and App Intent JSON dictionaries are dynamically typed. The project had already hardened several optional and update fields, but these four required create-field call sites remained on the older combined presence/type pattern.

## Resolution for the Issue

The four create entry points now validate required fields in three stages: key presence, string type, then the existing empty/enum value rules. Present non-string values are rejected before project lookup or service mutation, and legacy missing-field and invalid-string errors remain unchanged.

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift: handleCreateTask` - uses presence-first validation for `name` and `type`, reusing `requiredString` for task names.
- `Transit/Transit/MCP/MCPToolHandler.swift: handleCreateMilestone` - uses the same required-name validation as `create_task`.
- `Transit/Transit/Intents/CreateTaskIntent.swift: validateInput` - distinguishes missing, non-string, empty, and invalid-string `name`/`type` values.
- `Transit/Transit/Intents/CreateMilestoneIntent.swift: requiredName` - centralizes presence-first required-name validation.

**Approach rationale:** This follows the existing validation contract used by `TaskUpdateValidator`, MCP status/comment handlers, and the T-1192/T-1453 regressions. It is minimal, preserves error strings for existing valid/missing/invalid-string cases, and guarantees malformed required input is rejected before mutation.

**Alternatives considered:**
- Add a new shared cross-surface validator - not chosen because the MCP and App Intent error envelope types differ and the existing local helpers already provide the project’s established patterns.
- Validate after project resolution - not chosen because malformed required fields should fail before any lookup or mutation work.

## Regression Test

**Test file:** `Transit/TransitTests/CreateRequiredStringValidationTests.swift`
**Test names:**
- `mcpCreateTaskRejectsNonStringNameAndTypeWithoutMutation`
- `createTaskIntentRejectsNonStringNameAndTypeWithoutMutation`
- `mcpCreateMilestoneRejectsNonStringNameWithoutMutation`
- `createMilestoneIntentRejectsNonStringNameWithoutMutation`

**What it verifies:** Numeric, boolean, array, object, and null required values return field-specific type errors; missing fields and invalid string task types retain their existing errors; malformed requests create no task or milestone.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Presence-first required `name`/`type` validation for MCP task and milestone creates. |
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Presence-first required `name`/`type` validation for the JSON App Intent. |
| `Transit/Transit/Intents/CreateMilestoneIntent.swift` | Presence-first required `name` validation for the JSON App Intent. |
| `Transit/TransitTests/CreateRequiredStringValidationTests.swift` | Symmetric MCP/App Intent regression coverage. |
| `specs/bugfixes/create-paths-misreport-non-string-required-name-type-fields/report.md` | Investigation and resolution report. |

## Verification

**Automated:**
- [x] Regression test passes: the four-surface focused suite passes for numeric, boolean, array, object, and null values, plus missing and invalid-string compatibility cases.
- [x] Full macOS unit suite passes via `make test-quick`.
- [x] Linters/validators pass via `make lint`, including the SwiftData ownership guard.
- [ ] Full iOS Simulator suite: `make test` was started through the Makefile but did not complete after more than eight minutes while concurrent simulator builds were active; no code/test failure was reported before the run was stopped.

**Manual verification:**
- The pre-fix focused suite failed in all four affected create paths.
- The post-fix focused suite passed in both MCP and App Intent surfaces.
- Each malformed input case asserts that no task or milestone was created.

## Prevention

**Recommendations to avoid similar bugs:**
- Check dictionary-key presence before casting dynamically typed JSON values.
- Reuse the established `present -> type -> value` validation order for every JSON/MCP field.
- Keep cross-surface regression tests symmetric when MCP and App Intent paths expose the same contract.

## Related

- Transit T-1598
- T-1192, T-1453, T-1579
