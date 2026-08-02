# Bugfix Report: Create paths misreport non-string required name/type fields

**Date:** 2026-08-02
**Status:** In Progress

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

Pending implementation.

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
| `Transit/Transit/MCP/MCPToolHandler.swift` | Pending: distinguish missing and non-string required create arguments. |
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Pending: distinguish missing and non-string `name`/`type`. |
| `Transit/Transit/Intents/CreateMilestoneIntent.swift` | Pending: distinguish missing and non-string `name`. |
| `Transit/TransitTests/CreateRequiredStringValidationTests.swift` | Added regression coverage for both surfaces. |

## Verification

**Automated:**
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Focused regression suite currently fails on the four affected paths, confirming the bug before implementation.

## Prevention

**Recommendations to avoid similar bugs:**
- Check dictionary-key presence before casting dynamically typed JSON values.
- Reuse the established `present -> type -> value` validation order for every JSON/MCP field.
- Keep cross-surface regression tests symmetric when MCP and App Intent paths expose the same contract.

## Related

- Transit T-1598
- T-1192, T-1453, T-1579
