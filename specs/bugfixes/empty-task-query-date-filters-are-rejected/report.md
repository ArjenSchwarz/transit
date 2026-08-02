# Bugfix Report: Empty Task Query Date Filters Are Rejected

**Date:** 2026-08-02
**Status:** In Progress
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

_To be completed after the implementation and verification pass._

## Regression Test

**Test file:** `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift`
**Test name:** `emptyDateFilterObjectsReturnAllTasks`

**What it verifies:** `completionDate: {}`, `lastStatusChangeDate: {}`, and both empty objects together are accepted as no-op filters and return the complete seeded task set.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift` | Added failing regressions for both empty date-filter fields and the combined case. |
| `specs/bugfixes/empty-task-query-date-filters-are-rejected/report.md` | Investigation checkpoint; resolution pending. |

## Verification

**Automated:**
- [x] Red regression run confirmed `emptyDateFilterObjectsReturnAllTasks` fails before the fix (`make test-quick`; test execution completed and reported the focused failure).
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Existing T-1644 tests cover nested null rejection and malformed nested date-filter shapes.
- Existing T-1799 and T-1819 regressions cover strict dates and reversed absolute ranges.
- Existing open-bound and relative-precedence tests must remain unchanged and passing.

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
