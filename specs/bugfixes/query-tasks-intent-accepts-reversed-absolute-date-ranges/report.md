# Bugfix Report: QueryTasksIntent Accepts Reversed Absolute Date Ranges

**Date:** 2026-08-02
**Status:** In Progress

## Description of the Issue

`QueryTasksIntent` accepts an absolute date filter whose `from` date is later than its `to` date. The parser validates each date independently, then returns a range that can never match a task, so callers receive an empty array instead of the established `INVALID_INPUT` response. The visual `FindTasksIntent` already rejects inverted custom ranges.

**Reproduction steps:**
1. Call `QueryTasksIntent` with `{"completionDate":{"from":"2026-07-20","to":"2026-07-01"}}` or the equivalent `lastStatusChangeDate` filter.
2. Observe that the JSON intent returns `[]` instead of an `INVALID_INPUT` error.

**Impact:** Medium. CLI, Shortcuts, and other JSON callers can silently accept caller mistakes and interpret an empty result as valid data. Both task date fields are affected.

## Investigation Summary

The shared date-filter path and the visual path were inspected before implementation.

- **Symptoms examined:** Reversed absolute ranges return no matches; valid one-sided, same-day, relative, and strict calendar-date cases already have regression coverage.
- **Code inspected:** `DateFilterHelpers.parseDateFilter`, `QueryTasksIntent.validateDateFilters`, `QueryTasksIntent.dateRange`, `FindTasksIntent.buildDateRange`, and their tests.
- **Hypotheses tested:** The defect is not caused by date parsing or date inclusivity. T-1799's strict `YYYY-MM-DD` parsing is intact. The missing check is endpoint ordering after both absolute dates parse.

## Discovered Root Cause

`DateFilterHelpers.parseDateFilter` converts `from` and `to` independently and returns `.absolute` whenever either endpoint is present, but it never rejects the case where both parsed endpoints exist and `from > to`. `QueryTasksIntent` treats a non-nil parsed range as valid, while `FindTasksIntent` performs the ordering check for custom ranges in its own builder.

**Defect type:** Missing validation / cross-surface contract mismatch.

**Why it occurred:** Absolute endpoint parsing and range ordering were implemented as separate concerns, and only the visual App Intent added an explicit ordering guard.

**Contributing factors:** The range matcher correctly treats bounds inclusively, so a reversed range naturally produces zero matches without surfacing an error. The shared helper is the correct parity point for JSON and visual consumers, but the visual path currently validates before calling it.

## Resolution for the Issue

_To be completed after implementation._

## Regression Test

**Test files:**
- `Transit/TransitTests/DateFilterHelpersTests.swift`
- `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift`
- `Transit/TransitTests/FindTasksIntentTests.swift`

**What it verifies:** Reversed absolute ranges are rejected by the shared parser, produce `INVALID_INPUT` for both `completionDate` and `lastStatusChangeDate` in `QueryTasksIntent`, and remain rejected by the visual intent for both date fields. Existing tests continue to cover open bounds, inclusive same-day/range behavior, relative filters, and T-1799 strict date parsing.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/Shared/Utilities/DateFilterHelpers.swift` | Validate absolute endpoint ordering. |
| `Transit/TransitTests/DateFilterHelpersTests.swift` | Add shared-parser regression. |
| `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift` | Add JSON `INVALID_INPUT` regressions for both fields. |
| `Transit/TransitTests/FindTasksIntentTests.swift` | Add last-status visual parity regression. |
| `CHANGELOG.md` | Document the user-visible validation fix. |

## Verification

**Automated:**
- [ ] Regression tests pass
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Confirm the final diff preserves one-sided ranges, same-day inclusive ranges, relative filters, and strict date parsing.

## Prevention

- Keep absolute-range ordering validation in the shared date-filter parser used by all surfaces.
- Retain cross-surface tests for both task date fields whenever date-filter contracts change.

## Related

- T-1799: strict absolute calendar-date parsing.
- T-1819: this bugfix.
