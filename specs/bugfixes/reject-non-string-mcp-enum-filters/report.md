# Bugfix Report: Reject Non-String MCP Enum Filters

**Date:** 2026-05-02
**Status:** Fixed
**Ticket:** T-809

## Description of the Issue

`MCPToolHandler.validateEnumFilter` only validated values when the argument was a `String` or `[String]`. When an MCP caller supplied a non-string value such as `{"status": 123}`, `{"not_status": true}`, `{"type": 5}`, or a mixed-type array like `{"status": ["idea", 123]}`, both `as? String` and `as? [String]` returned `nil`, the function returned `nil`, and `MCPQueryFilters.from` also treated the filter as absent. The query then succeeded with an unintentionally broad result set instead of returning an `isError` response.

**Reproduction steps:**
1. Send `tools/call` with name `query_tasks` and arguments `{"status": 123}`.
2. Observe the response: a full unfiltered task list rather than an `isError` payload.
3. Same with `query_milestones` and `{"status": 42}`, or any mixed-type array.

**Impact:** Affected `query_tasks` (`status`, `not_status`, `type`) and `query_milestones` (`status`). MCP callers received silently incorrect results when they sent malformed enum filters, which is particularly dangerous for agents that build queries programmatically.

## Investigation Summary

- **Symptoms examined:** Filter keys with non-string values do not produce an error response, and unfiltered tasks/milestones come back.
- **Code inspected:**
  - `Transit/Transit/MCP/MCPToolHandler.swift` — `validateEnumFilter` and the call sites in `handleQueryTasks` / `handleQueryMilestones`.
  - `Transit/Transit/MCP/MCPHelperTypes.swift` — `MCPQueryFilters.from` (mirrors the same string-only narrowing logic).
- **Hypotheses tested:**
  - Whether `JSONSerialization` somehow coerces numeric values — confirmed it does not (numbers come through as `__NSCFNumber`, booleans as `__NSCFBoolean`).
  - Whether mixed-type arrays cast successfully via `as? [String]` — confirmed they do not (cast returns `nil` for the entire array).

## Discovered Root Cause

`validateEnumFilter` used Swift's optional cast pattern (`as? String`, `as? [String]`) to extract values, then returned `nil` if neither cast succeeded. That branch conflated three semantically distinct cases:

1. Key absent — filter does not apply.
2. Key present with a valid string or string array — validate enum values.
3. **Key present with an invalid shape (number, bool, dict, mixed array) — silently treated as case 1.**

**Defect type:** Missing validation / silent coercion.

**Why it occurred:** The function was originally written to support both `String` and `[String]` shapes for backward compatibility, and its `else` branch was reused for the absent-key case. The "key present but wrong type" case was not handled separately.

**Contributing factors:** The same shape-narrowing pattern is repeated in `MCPQueryFilters.from`, so even if the handler check were bypassed, the fallback path would still ignore malformed input.

## Resolution for the Issue

`validateEnumFilter` now distinguishes the three cases. If the key is absent, it returns `nil` (no error). If the value is `String` or `[String]`, it validates the enum raw values as before. If the key is present but the value is anything else (number, bool, dict, mixed-type array), it returns a field-specific error result naming the offending key.

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift` — Replace the `String` / `[String]` cast chain in `validateEnumFilter` with explicit shape checks: absent (return `nil`), `[String]` (validate), `String` (validate), `[Any]` containing only strings (validate), otherwise return an error naming the field.

**Approach rationale:** The fix is contained to the single validation helper because the handler already calls `validateEnumFilter` before `MCPQueryFilters.from`. Once the handler rejects malformed input, the helper never sees it, so changes in `MCPHelperTypes.swift` are unnecessary for correctness.

**Alternatives considered:**
- Also harden `MCPQueryFilters.from` — Rejected because the helper has no error channel (it returns a non-optional `MCPQueryFilters`) and the handler is the right place to enforce input validation.

## Regression Test

**Test file:** `Transit/TransitTests/MCPToolHandlerEnumValidationTests.swift`

**New tests:**
- `queryTasksNumericStatusReturnsError`
- `queryTasksBooleanNotStatusReturnsError`
- `queryTasksNumericTypeReturnsError`
- `queryTasksMixedTypeStatusArrayReturnsError`
- `queryTasksMixedTypeNotStatusArrayReturnsError`
- `queryTasksDictionaryStatusReturnsError`
- `queryMilestonesNumericStatusReturnsError`
- `queryMilestonesMixedTypeStatusArrayReturnsError`
- `queryTasksNumericStatusDoesNotReturnUnfilteredResults`

**What they verify:** Non-string enum filter values (numbers, booleans, dictionaries, and mixed-type arrays) produce an `isError` response naming the offending field, both for `query_tasks` (`status`, `not_status`, `type`) and `query_milestones` (`status`). The last test guards specifically against the silent-fallback behaviour by seeding tasks and asserting the response is an error rather than an unfiltered list.

**Run command:**
```
xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit \
  -destination 'platform=macOS' \
  -only-testing:TransitTests/MCPToolHandlerEnumValidationTests
```

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Tighten `validateEnumFilter` to reject non-string shapes. |
| `Transit/TransitTests/MCPToolHandlerEnumValidationTests.swift` | Add nine regression tests covering numeric, boolean, dictionary, and mixed-array values. |

## Verification

**Automated:**
- [x] Regression tests pass
- [x] Full unit test suite passes (`make test-quick`)
- [x] Linter passes (`make lint`)

## Prevention

**Recommendations to avoid similar bugs:**
- When validating loosely-typed dictionary inputs, separate "key absent" from "key present with wrong type" — silent coercion of malformed input is a common pitfall.
- Consider centralising MCP argument extraction so this rule is enforced uniformly across handlers.

## Related

- T-732 — earlier work that introduced `validateEnumFilter` for invalid string values; this bug closes the type-check gap.
- T-808, T-810 — sibling bugs in the same family (non-string identifiers being treated as missing).
