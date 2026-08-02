# Bugfix Report: Query Tasks Intent Accepts Invalid Calendar Date Strings

**Date:** 2026-08-02
**Status:** Investigation complete; fix in progress

## Description of the Issue

`QueryTasksIntent` documents absolute date filters as `YYYY-MM-DD`, but `DateFilterHelpers` delegates parsing to a lenient `DateFormatter`. Foundation accepts non-padded values and normalizes invalid calendar components, so inputs such as `2026-02-30` can be treated as a different valid date instead of returning `INVALID_INPUT`.

**Reproduction steps:**
1. Invoke `QueryTasksIntent` with `{"completionDate":{"from":"2026-02-30"}}` or a non-padded value such as `2026-2-01`.
2. Observe that the date filter is accepted rather than rejected.
3. Compare with the documented exact `YYYY-MM-DD` contract.

**Impact:** CLI, Shortcuts, and agent callers can receive results for a silently altered date filter. The issue affects absolute `completionDate` and `lastStatusChangeDate` filters; relative filters are unaffected.

## Investigation Summary

- **Symptoms examined:** Invalid days/months, non-padded fields, Unicode digits/separators, valid leap-day input, inclusive absolute ranges, and relative date filters.
- **Code inspected:** `DateFilterHelpers`, `QueryTasksIntent` validation/application paths, `FindTasksIntent` shared-helper usage, and existing date-filter tests.
- **Hypotheses tested:** The defect is in shared date parsing rather than intent JSON decoding or task filtering. Focused pre-fix regressions fail for normalized invalid days, non-padded values, and non-ASCII input while existing valid and relative cases pass.

## Discovered Root Cause

`DateFilterHelpers.dateFromString` calls `DateFormatter.date(from:)` with only a `yyyy-MM-dd` format. That API does not enforce exact lexical width/ASCII characters and can normalize invalid date components before returning a `Date`. `QueryTasksIntent` treats any non-`nil` parsed date as valid.

**Defect type:** Missing input validation and date normalization.

**Why it occurred:** The formatter was configured for output shape but not strict input validation. No lexical check or parsed-date round-trip check guarded the public filter boundary.

**Contributing factors:** Foundation date parsing is permissive; both JSON date fields share the helper, so a single parser defect affects both absolute filters.

## Resolution for the Issue

_To be completed after implementation._

## Regression Test

**Test files:**
- `Transit/TransitTests/DateFilterHelpersTests.swift`
- `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift`

**Test names:**
- `parseAbsoluteFilterAcceptsLeapDay()`
- `parseAbsoluteFilterRejectsInvalidCalendarDateStrings(value:)`
- `parseAbsoluteFilterRejectsNonPaddedDateStrings(value:)`
- `malformedAbsoluteDateStringsReturnInvalidInput(value:)`

**What it verifies:** Absolute filters accept real Gregorian leap days, reject invalid month/day boundaries and non-leap-year dates, reject non-ASCII and non-padded values, and surface `INVALID_INPUT` through both QueryTasksIntent date fields.

**Run command:** `make test-quick` (or the focused macOS xcodebuild command with the two test classes)

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/Shared/Utilities/DateFilterHelpers.swift` | Pending strict date parsing fix |
| `Transit/TransitTests/DateFilterHelpersTests.swift` | Added parser regressions |
| `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift` | Added intent-level regressions |

## Verification

**Automated:**
- [ ] Regression tests pass
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Focused pre-fix run confirmed the new malformed-date tests fail while existing valid absolute, inclusive, and relative tests pass.

## Prevention

- Validate exact input shape before invoking Foundation date parsing.
- Use explicit Gregorian calendar, locale, and time-zone semantics for machine-readable dates.
- Require formatter round-trip equality before accepting a parsed calendar date.
- Keep parser-level and intent-level regressions for externally documented input formats.

## Related

- Transit ticket T-1799
