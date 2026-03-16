# Bugfix Report: Report Date Range Labels Ending Early

**Date:** 2026-03-16
**Status:** Fixed
**Ticket:** T-460

## Description of the Issue

`ReportDateRange.labelWithDates` was reported to show end dates one day early for `lastWeek`, `lastMonth`, and `lastYear` ranges. The concern was that `dateInterval()` subtracts one day from `Calendar.dateInterval.end` to get the inclusive last day, then `labelWithDates()` formats using `(start ..< end).formatted(.interval...)` — a half-open `Range<Date>` — which could apply exclusive semantics and effectively subtract another day.

**Reproduction steps:**
1. Call `ReportDateRange.lastMonth.labelWithDates()` during February 2026
2. Observe the label for "Last Month" — expected "Jan 1 – 31" but could show "Jan 1 – 30"

**Impact:** Labels on generated reports would show incorrect date ranges, potentially confusing users about which period the report covers.

## Investigation Summary

Systematic analysis of `Range<Date>.formatted(.interval...)` behaviour on macOS 26.3 revealed that the formatter displays both bound dates as-is — it does **not** apply exclusive-end semantics. The current code therefore produces correct labels on this SDK version.

However, the code pattern is fragile and misleading:
- `dateInterval()` returns an inclusive last day (already subtracts 1 day)
- `labelWithDates()` uses `..< end` (half-open range) with that inclusive date
- A human reader (or a future SDK change) could interpret `..< end` as excluding the end date

- **Code inspected:** `ReportDateRange.swift` (lines 53–109), `ReportLogicDateRangeTests.swift`
- **Hypotheses tested:** Range<Date> exclusive formatting (not confirmed on macOS 26.3), DST edge cases (not applicable)
- **Verified:** `DateIntervalFormatter.string(from:to:)` produces identical output without Range semantics

## Discovered Root Cause

**Defect type:** Fragile API usage / misleading code pattern

The `Range<Date>.formatted(.interval...)` API accepts a half-open range (`start ..< end`) but formats both bounds as dates without exclusive adjustment. Using it with an inclusive end date works today but creates a semantic mismatch that could break if Foundation changes the formatter's treatment of Range exclusivity.

**Why it occurred:** The original code used the modern `Range<Date>.formatted` API without considering that `..< end` semantically implies the end is excluded, even though the formatter ignores this.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Reports/ReportDateRange.swift:63-65` — Replaced `Range<Date>.formatted(.interval...)` with `DateIntervalFormatter.string(from:to:)` which takes two explicit dates without Range semantics

**Approach rationale:** `DateIntervalFormatter.string(from:to:)` accepts two dates directly — no half-open range involved. This eliminates the semantic mismatch between "exclusive range" and "inclusive last day" and makes the code resilient to any future changes in how `Range<Date>` is formatted.

**Alternatives considered:**
- Using `interval.end` directly without day subtraction — produced incorrect labels ("Jan 1 – Feb 1" instead of "Jan 1 – 31")
- `ClosedRange<Date>.formatted(.interval...)` — not supported by Foundation (`Date.Stride` doesn't conform to `SignedInteger`)
- `DateInterval.formatted(...)` — not available on this SDK
- Comment-only fix — insufficient; the API usage itself is the risk

## Regression Test

**Test file:** `Transit/TransitTests/ReportDateRangeLabelTests.swift`
**Test names:** `lastWeekLabelEndDate`, `lastMonthLabelEndDate`, `lastYearLabelEndDate`

**What it verifies:** Each test computes the expected last day of the previous period using `Calendar` APIs and checks that the formatted label contains the correct end date string (locale-aware).

**Run command:** `make test-quick` or:
```bash
xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit \
  -destination 'platform=macOS' \
  -only-testing:TransitTests/ReportDateRangeLabelTests test
```

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Reports/ReportDateRange.swift` | Replaced `Range<Date>.formatted` with `DateIntervalFormatter.string(from:to:)` |
| `Transit/TransitTests/ReportDateRangeLabelTests.swift` | Added regression tests for last week/month/year label end dates |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (0 failures)
- [x] Linters pass (0 violations)

## Prevention

**Recommendations to avoid similar bugs:**
- Prefer `DateIntervalFormatter.string(from:to:)` over `Range<Date>.formatted(.interval...)` when formatting inclusive date ranges
- When `Calendar.dateInterval.end` is used, document whether the value is exclusive (Calendar convention) or has been converted to inclusive
- Add regression tests for formatted date labels to catch any Foundation behaviour changes across SDK updates
