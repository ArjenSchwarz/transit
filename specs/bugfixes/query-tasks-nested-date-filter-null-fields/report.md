# Bugfix Report: Query Tasks Nested Date Filter Null Fields

**Date:** 2026-08-02
**Status:** In Progress
**Ticket:** T-1644

## Description of the Issue

`QueryTasksIntent` rejects explicit JSON `null` values for top-level filters, but it accepts explicit `null` values inside the `completionDate` and `lastStatusChangeDate` filter objects. `JSONDecoder` decodes those present nulls into optional `nil` values, making them indistinguishable from omitted fields.

For example, `{"completionDate":{"from":null}}` can become an open-ended date filter rather than a malformed request. A missing bound can broaden the result set compared with the caller's intended bounded query.

**Reproduction steps:**
1. Seed tasks with dates inside and outside a bounded date range.
2. Call `QueryTasksIntent` with `{"completionDate":{"from":null}}` or the equivalent `lastStatusChangeDate` payload.
3. Observe that the nested null is not rejected before date-filter parsing.

**Impact:** Medium correctness issue for Shortcut/JSON callers. Malformed date filters can be accepted with altered or broader query semantics. No task data is mutated.

## Investigation Summary

The investigation followed the project's systematic debugging workflow: inspect the input boundary, trace decoded values through validation and filtering, and compare the behavior with the existing top-level null contract.

- **Symptoms examined:** Nested `relative`, `from`, or `to` nulls are accepted while top-level null filters return `INVALID_INPUT`; malformed date-filter shapes must not turn into an unfiltered query.
- **Code inspected:** `Transit/Transit/Intents/QueryTasksIntent.swift`, `QueryTasksIntentNullFilterTests.swift`, `QueryTasksIntentDateFilterTests.swift`, `DateFilterHelpers.swift`, `TransitShortcuts.swift`, and all direct `QueryTasksIntent.execute` callers.
- **Hypotheses tested:** The issue is not in date range calculation or task filtering. It is caused by presence information being erased during Codable decoding. Non-object nested filters already fail through JSONDecoder and must retain their existing generic `INVALID_INPUT` contract.

## Discovered Root Cause

`QueryTasksIntent.parseInput` checks only the top-level `[String: Any]` dictionary for `NSNull` values, then decodes into `QueryFilters`. The nested `DateRangeFilter` fields are optional strings, so synthesized `decodeIfPresent` maps a present JSON null to `nil`, exactly as it does for an omitted field. `dateRange(from:)` then passes those nil values to `DateFilterHelpers.parseDateFilter`, which can interpret a missing bound as an open-ended range.

**Defect type:** Missing presence-aware validation / data transformation issue.

**Why it occurred:** The original null guard was added at the filter-object level but did not recurse into the two nested date-filter dictionaries before decoding.

**Contributing factors:** Codable's optional decoding intentionally erases the distinction between omitted and explicit null values. The date filter API intentionally allows omitted bounds, so the erased value can be interpreted as valid input with different query semantics.

## Resolution for the Issue

_To be completed after implementation._

## Regression Test

**Test file:** `Transit/TransitTests/QueryTasksIntentNullFilterTests.swift`

**Test names:**
- `nullCompletionDateRelativeIsRejected`
- `nullCompletionDateFromIsRejected`
- `nullCompletionDateToIsRejected`
- `nullLastStatusChangeDateRelativeIsRejected`
- `nullLastStatusChangeDateFromIsRejected`
- `nullLastStatusChangeDateToIsRejected`
- `scalarCompletionDateFilterIsRejected`
- `arrayLastStatusChangeDateFilterIsRejected`
- `malformedNestedDateFiltersDoNotBroadenResults`

**What it verifies:** Every recognized nested date-filter field rejects explicit JSON null under both date filters. Scalar/array date-filter values retain `INVALID_INPUT`, and malformed nested filters do not return the seeded task set.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/QueryTasksIntent.swift` | Pending presence-aware nested date-filter validation |
| `Transit/TransitTests/QueryTasksIntentNullFilterTests.swift` | Nested null and malformed-shape regressions |
| `specs/bugfixes/query-tasks-nested-date-filter-null-fields/report.md` | Investigation and resolution record |
| `CHANGELOG.md` | Pending Unreleased fixed entry |

## Verification

**Automated:**
- [ ] Red regression tests fail before the fix
- [ ] Regression tests pass after the fix
- [ ] Full unit test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Confirm omitted date-filter fields retain existing semantics.
- Confirm top-level null error hints remain unchanged.

## Prevention

**Recommendations to avoid similar bugs:**
- Validate presence-sensitive JSON fields from the `JSONSerialization` object before decoding into optional Codable properties.
- Treat nested filter objects as a separate validation boundary and preserve the existing error contract for malformed shapes.
- Add paired omitted-versus-explicit-null regressions whenever optional JSON fields are introduced.

## Related

- T-1644 — QueryTasksIntent accepts nested null date filter fields.
- `QueryTasksIntentNullFilterTests` — existing top-level explicit-null contract.
