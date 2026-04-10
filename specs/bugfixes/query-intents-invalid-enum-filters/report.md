# Bugfix Report: Query Intents Invalid Enum Filters

**Date:** 2026-04-10
**Status:** Fixed

## Description of the Issue

`QueryTasksIntent` and `QueryMilestonesIntent` accept arbitrary strings for enum-like filter fields (`status`, `type`) without validating that the value is a recognized enum member. Invalid values silently produce empty results instead of returning an explicit error.

**Reproduction steps:**
1. Call `QueryTasksIntent` with `{"status":"not-a-status"}`
2. Observe an empty array is returned instead of an `INVALID_STATUS` error
3. Same issue with `{"type":"not-a-type"}` and `QueryMilestonesIntent`'s `{"status":"not-a-status"}`

**Impact:** Callers (CLI tools, agents) receive misleading empty results when they pass a typo or unsupported value, making debugging difficult. This violates the error contract established by other intents (e.g., `UpdateStatusIntent`, `CreateTaskIntent`) which validate these enums.

## Investigation Summary

- **Symptoms examined:** Invalid enum values passed through to `applyFilters` where they were compared as raw strings against model raw values, never matching any record.
- **Code inspected:** `QueryTasksIntent.swift` (execute, applyFilters), `QueryMilestonesIntent.swift` (execute, applyFilters), `UpdateStatusIntent.swift` and `CreateTaskIntent.swift` (for reference on how validation is done elsewhere).
- **Hypotheses tested:** Single root cause confirmed — missing validation before filtering.

## Discovered Root Cause

Both query intents parse enum filter values as raw strings and pass them directly to their `applyFilters` methods without checking membership in the corresponding enum (`TaskStatus`, `TaskType`, `MilestoneStatus`).

**Defect type:** Missing validation

**Why it occurred:** The query intents were built to accept flexible string filters for filtering, but validation was only added for other fields (projectId, dates, displayId). The enum filters were overlooked.

**Contributing factors:** The `QueryFilters` struct in `QueryTasksIntent` uses `String?` for status and type rather than typed enums, making it easy to skip validation. `QueryMilestonesIntent` parses into a raw `[String: Any]` dict, which also provides no type safety.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Intents/QueryTasksIntent.swift` — Added `validateEnumFilters` method that checks `status` via `TaskStatus(rawValue:)` and `type` via `TaskType(rawValue:)`, returning `INVALID_STATUS` or `INVALID_TYPE` errors respectively.
- `Transit/Transit/Intents/QueryMilestonesIntent.swift` — Added status validation in `execute()` that checks the `status` field via `MilestoneStatus(rawValue:)`, returning `INVALID_STATUS` on mismatch.

**Approach rationale:** Validates early in the execute flow (fail-fast), consistent with how other intents handle enum validation. Uses the failable `rawValue` initializer on each enum to check membership without hardcoding values.

**Alternatives considered:**
- Validate inside `applyFilters` — rejected because errors should be caught before filtering begins, consistent with the existing projectId/date validation pattern.
- Convert `QueryFilters.status`/`type` to typed enums — would provide compile-time safety but changes the struct's Codable behavior and is a larger refactor than needed.

## Regression Test

**Test file:** `Transit/TransitTests/QueryIntentEnumValidationTests.swift`
**Test names:** `queryTasksWithInvalidStatusReturnsError`, `queryTasksWithInvalidTypeReturnsError`, `queryMilestonesWithInvalidStatusReturnsError`, plus positive tests for valid values.

**What it verifies:** Invalid enum values return the correct error code; valid values continue to work.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/QueryTasksIntent.swift` | Added enum validation for status and type filters |
| `Transit/Transit/Intents/QueryMilestonesIntent.swift` | Added enum validation for status filter |
| `Transit/TransitTests/QueryIntentEnumValidationTests.swift` | New regression tests |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- When adding string-based filters that map to known enums, always validate membership before using them in filtering logic
- Consider using typed enum fields in filter structs instead of raw strings where possible

## Related

- T-754: Query intents accept invalid enum filters without validation
- T-732: MCP side enum filter validation (separate tracking bug)
