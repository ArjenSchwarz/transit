# Bugfix Report: Empty Task Query Date Filters Are Rejected

**Date:** 2026-08-02
**Status:** Fixed
**Ticket:** T-2036

## Description of the Issue

`QueryTasksIntent` rejects a present but empty `completionDate` or `lastStatusChangeDate` object even though the Shortcut intent design defines `{}` as a valid no-op date filter. Callers using either empty date object receive `INVALID_INPUT` instead of the unfiltered task set.

**Reproduction steps:**
1. Seed tasks in more than one status.
2. Query with `{"completionDate":{}}`, `{"lastStatusChangeDate":{}}`, or both fields as empty objects.
3. Observe that the intent returns an `INVALID_INPUT` object rather than all seeded tasks.

**Impact:** Medium correctness issue for JSON/Shortcuts callers. Empty date filter objects cannot be used as valid no-op filters, while the malformed-input contract must remain strict.

## Investigation Summary

The investigation followed the systematic debugging workflow: inspect the raw JSON boundary, trace date-filter values through Codable decoding and validation, and compare the behavior with the design and existing T-1644/T-1799/T-1819 regressions.

- **Symptoms examined:** Empty date objects are decoded into non-optional `DateRangeFilter` values whose optional fields are all `nil`; `validateDateFilters` then reports an invalid format.
- **Code inspected:** `Transit/Transit/Intents/QueryTasksIntent.swift`, `QueryTasksIntentDateFilterTests.swift`, `QueryTasksIntentNullFilterTests.swift`, `DateFilterHelpers.swift`, the Shortcut design, and prior date-filter bugfix reports.
- **Hypotheses tested:** The filtering path already treats a missing parsed range as no filtering. The defect is at validation, where an empty object and malformed non-empty object are indistinguishable after Codable decoding. Existing nested-null preflight must remain intact.

## Discovered Root Cause

`parseInput` validates nested date-filter object shape and then decodes into `DateRangeFilter`, whose optional `relative`, `from`, and `to` properties all become `nil` for `{}`. After Codable erases the raw object's presence/emptiness, `validateDateFilters` calls `dateRange(from:)`; the resulting `nil` is currently treated as malformed regardless of whether the original object was empty or contained invalid non-empty content.

**Defect type:** Missing presence-aware validation / data transformation issue.

**Why it occurred:** The T-1644 presence preflight retained nested null validation but did not retain whether a recognized date-filter object had any keys. The existing date parser intentionally returns `nil` for invalid content and for no date bounds, so validation needs the raw emptiness distinction before decoding.

**Contributing factors:** Codable optional decoding intentionally maps omitted and explicit-null values to `nil`; date filters also intentionally support open bounds, so the decoded representation cannot be used alone to distinguish valid no-op input from malformed content.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Intents/QueryTasksIntent.swift` — During raw JSON preflight, record which recognized date-filter objects are genuinely empty; apply that marker after Codable decoding and skip date-format validation only for those objects. Non-empty objects continue through the existing strict parser and validation.
- `Transit/Transit/Intents/QueryTasksIntent+FilterTypes.swift` — Keep the Codable filter models separate and add the transient `isEmptyObject` marker to `DateRangeFilter`.
- `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift` — Add regressions for each empty date-filter field and both fields together, asserting the complete seeded task set is returned.
- `Transit/TransitTests/QueryTasksIntentEmptyDateFilterTests.swift` — Add focused regressions proving empty filters compose with other filters and unknown nested keys remain ignored alongside valid bounds for both date fields.
- `Transit/TransitTests/QueryTasksIntentNullFilterTests.swift` — Add non-empty unknown-key regressions proving malformed date objects remain `INVALID_INPUT`.
- `CHANGELOG.md` — Record the T-2036 fix under Unreleased.

**Approach rationale:** The raw JSON dictionary is already inspected before Codable for top-level and nested null validation. Retaining only the emptiness bit at that boundary preserves the existing Codable/date-parser behavior, makes `{}` a no-op through the existing `flatMap(dateRange)` path, and prevents malformed non-empty objects from being mistaken for no filtering.

**Alternatives considered:**
- Treat every decoded date filter with no parsed range as a no-op — rejected because malformed non-empty objects would be accepted and could broaden queries.
- Add custom Codable presence tracking for every nested field — rejected as unnecessary; only object emptiness needs to survive decoding for this contract.


## Regression Test

**Test files:** `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift` and `Transit/TransitTests/QueryTasksIntentEmptyDateFilterTests.swift`
**Test names:** `emptyDateFilterObjectsReturnAllTasks`, `emptyDateFiltersRemainNoOpsWhenCombinedWithOtherFilters`, and `unknownNestedKeysDoNotChangeValidDateFilters`

**What it verifies:** `completionDate: {}`, `lastStatusChangeDate: {}`, and both empty objects together are accepted as no-op filters and return the complete seeded task set. Empty filters do not override an unrelated status filter, and unknown nested keys remain ignored when a valid recognized date bound is present for either date field.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/QueryTasksIntent.swift` | Preserved empty date-object presence before Codable and skipped validation only for valid empty no-op filters. |
| `Transit/Transit/Intents/QueryTasksIntent+FilterTypes.swift` | Added the transient decoded date-filter emptiness marker and relocated filter models. |
| `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift` | Added regressions for both empty date-filter fields and the combined case, proving all seeded tasks are returned. |
| `Transit/TransitTests/QueryTasksIntentEmptyDateFilterTests.swift` | Added composition and unknown-key compatibility regressions for both date fields. |
| `Transit/TransitTests/QueryTasksIntentNullFilterTests.swift` | Added malformed non-empty unknown-key regressions. |
| `specs/bugfixes/empty-task-query-date-filters-are-rejected/report.md` | Investigation and resolution record. |
| `CHANGELOG.md` | Unreleased T-2036 fixed entry. |

## Verification

**Automated:**
- [x] Red regression run confirmed `emptyDateFilterObjectsReturnAllTasks` failed before the fix (`make test-quick`; focused test reported by the test runner).
- [x] Regression and full macOS unit suite pass (`make test-quick`).
- [x] Linters/validators pass (`make lint`; SwiftData ownership guard and SwiftLint report zero violations).

**Manual verification:**
- `emptyDateFilterObjectsReturnAllTasks` covers `completionDate: {}`, `lastStatusChangeDate: {}`, and both fields together, and compares the returned names with all three seeded tasks.
- Existing T-1644 nested-null and malformed-shape tests continue to pass.
- Existing T-1799 strict date, T-1819 reversed-range, open-bound, relative-precedence, and inclusive-range tests continue to pass.
- New unknown-key cases return field-specific `Invalid <field> filter format` errors instead of being treated as no-op filters.

## Prevention

**Recommendations to avoid similar bugs:**
- Preserve raw JSON presence and emptiness for optional Codable filter objects before decoding.
- Keep empty-object no-op cases paired with malformed non-empty object regressions for every presence-sensitive filter.
- Validate malformed content before applying filters so invalid input cannot broaden a query.

## Related

- T-1644 — nested null date-filter fields must remain rejected.
- T-1799 — absolute date strings remain strict.
- T-1819 — reversed absolute ranges remain rejected.
- `specs/shortcuts-friendly-intents/design.md` — empty date-filter objects are no-op filters.
