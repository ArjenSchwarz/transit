# Bugfix Report: Query Tasks Nested Date Filter Null Fields

**Date:** 2026-08-02
**Status:** Fixed
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

**Changes made:**
- `Transit/Transit/Intents/QueryTasksIntent.swift` — Added a raw JSON preflight for `completionDate` and `lastStatusChangeDate`. Each recognized date filter must be an object, and `relative`, `from`, and `to` are checked for `NSNull` before `JSONDecoder` runs. Non-object shapes retain the existing `Expected valid JSON object` error contract, while unknown nested keys remain ignored.
- `Transit/TransitTests/QueryTasksIntentNullFilterTests.swift` — Added six nested-null regressions with exact error-hint assertions, malformed nested-field type regressions, malformed object-shape regressions, and a no-broadening regression covering both filters.
- `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift` — Added query-level regressions proving omitted `from` and `to` bounds preserve open-ended range semantics.
- `CHANGELOG.md` — Added the T-1644 fixed entry under `Unreleased`.

**Approach rationale:** The raw `JSONSerialization` object is already available for top-level null validation, so extending that preflight preserves the existing Codable model and date parsing semantics while retaining presence information only where required. Fixed field iteration order makes the nested null error deterministic.

**Alternatives considered:**
- Add custom `Decodable` presence tracking to `DateRangeFilter` — rejected as a larger change than the existing raw-object validation pattern.
- Reject every null-valued unknown nested key — rejected to avoid changing Codable's established behavior for ignored fields.
- Treat nested null as omitted — rejected because it can widen a bounded date query.

## Regression Test

**Test files:**
- `Transit/TransitTests/QueryTasksIntentNullFilterTests.swift`
- `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift`

**Test names:**
- `nullCompletionDateRelativeIsRejected`
- `nullCompletionDateFromIsRejected`
- `nullCompletionDateToIsRejected`
- `nullLastStatusChangeDateRelativeIsRejected`
- `nullLastStatusChangeDateFromIsRejected`
- `nullLastStatusChangeDateToIsRejected`
- `malformedNestedDateFilterFieldsAreRejected`
- `scalarCompletionDateFilterIsRejected`
- `arrayLastStatusChangeDateFilterIsRejected`
- `malformedNestedDateFiltersDoNotBroadenResults`
- `completionDateFromOnlyKeepsOpenUpperBound`
- `completionDateToOnlyKeepsOpenLowerBound`

**What it verifies:** Every recognized nested date-filter field rejects explicit JSON null under both date filters with stable field-path hints. Malformed scalar/array nested fields and date-filter shapes retain `INVALID_INPUT`, and malformed requests produce an error object rather than a broader task result. Query-level open-bound tests prove omitted `from` and `to` fields retain existing inclusive semantics.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/QueryTasksIntent.swift` | Presence-aware nested date-filter validation before Codable decoding |
| `Transit/TransitTests/QueryTasksIntentNullFilterTests.swift` | Nested null, malformed-type, stable-error, and no-broadening regressions |
| `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift` | Open-ended `from`/`to` range-semantics regressions |
| `specs/bugfixes/query-tasks-nested-date-filter-null-fields/report.md` | Investigation and resolution record |
| `CHANGELOG.md` | Unreleased T-1644 fixed entry |

## Verification

**Automated:**
- [x] Red regression run confirmed all six nested-null cases failed before the fix (`xcodebuild ... -only-testing:TransitTests/QueryTasksIntentNullFilterTests`, exit 65).
- [x] Focused regression suite passes after the fix (all `QueryTasksIntentNullFilterTests` cases passed).
- [x] Full unit test suite passes (`make test-quick`, exit 0).
- [x] Linters/validators pass (`make lint`, exit 0; ownership guard and SwiftLint pass).

**Manual verification:**
- Existing `omittedKeysStillReturnAllTasks` confirms omitted filters retain existing semantics, while `completionDateFromOnlyKeepsOpenUpperBound` and `completionDateToOnlyKeepsOpenLowerBound` verify omitted nested bounds remain open and inclusive.
- Exact nested-null hints are asserted for all six `relative`/`from`/`to` cases under both date filters.
- Existing top-level null regressions continue to pass, preserving their established `Filter \"<key>\" must not be null` contract.
- Malformed nested field types and scalar/array date-filter shapes continue to return `INVALID_INPUT` rather than broadening results; the no-broadening regression parses the response as an error object, not a task array.

## Prevention

**Recommendations to avoid similar bugs:**
- Validate presence-sensitive JSON fields from the `JSONSerialization` object before decoding into optional Codable properties.
- Treat nested filter objects as a separate validation boundary and preserve the existing error contract for malformed shapes.
- Add paired omitted-versus-explicit-null regressions whenever optional JSON fields are introduced.

## Related

- T-1644 — QueryTasksIntent accepts nested null date filter fields.
- `QueryTasksIntentNullFilterTests` — existing top-level explicit-null contract.
