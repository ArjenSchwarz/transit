# Bugfix Report: Query Tasks Intent Accepts Invalid Calendar Date Strings

**Date:** 2026-08-02
**Status:** Fixed

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

**Changes made:**
- `Transit/Transit/Intents/Shared/Utilities/DateFilterHelpers.swift` - Added an explicit Gregorian calendar using the current local time zone and POSIX locale; rejected every input without exactly ten ASCII bytes in `YYYY-MM-DD` shape; disabled formatter leniency; and required formatter round-trip equality so normalized invalid dates are rejected. Absolute range comparisons use the same local Gregorian calendar, while relative filters retain their existing `Calendar.current` behavior.
- `Transit/TransitTests/DateFilterHelpersTests.swift` - Added valid leap-day coverage plus invalid leap-year, month/day boundary, non-ASCII, and non-padded regressions.
- `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift` - Added intent-level `INVALID_INPUT` coverage for malformed values in both absolute date-filter fields.

**Approach rationale:** Exact byte-shape validation prevents Foundation from accepting alternate lexical forms, and round-trip equality detects dates that Foundation normalizes. Explicit calendar/time-zone configuration keeps date-only values aligned with existing local inclusive range semantics without changing relative filters.

**Alternatives considered:**
- Relying only on `DateFormatter.isLenient = false` - Not sufficient for the documented exact ASCII lexical contract, so shape validation and round-trip equality are both required.
- Parsing with `Date.ISO8601FormatStyle` - Would introduce different date-only/time-zone semantics and is unnecessary for this existing helper boundary.

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

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/Shared/Utilities/DateFilterHelpers.swift` | Strict exact-shape, Gregorian, local-time-zone, round-trip date parsing |
| `Transit/TransitTests/DateFilterHelpersTests.swift` | Parser regressions |
| `Transit/TransitTests/QueryTasksIntentDateFilterTests.swift` | Intent-level regressions |
| `specs/bugfixes/query-tasks-intent-accepts-invalid-calendar-date-strings/report.md` | Investigation and resolution report |
| `CHANGELOG.md` | Unreleased fix entry |

## Verification

**Automated:**
- [x] Focused helper and QueryTasksIntent tests pass on macOS
- [x] Full `make test-quick` suite passes
- [x] `make lint` and the SwiftData ownership validator pass

**Manual verification:**
- The pre-fix focused run reproduced failures for normalized invalid days, non-padded values, non-ASCII input, and the intent-level validation path.
- The post-fix focused run passed all existing relative/inclusive cases and all new regressions.

## Prevention

- Validate exact input shape before invoking Foundation date parsing.
- Use explicit Gregorian calendar, locale, and time-zone semantics for machine-readable dates.
- Require formatter round-trip equality before accepting a parsed calendar date.
- Keep parser-level and intent-level regressions for externally documented input formats.

## Related

- Transit ticket T-1799
