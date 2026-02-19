# Bugfix Report: Date.isWithin48Hours Counts Future Dates

**Date:** 2026-02-19
**Status:** Fixed

## Description of the Issue

`Date.isWithin48Hours(of:)` returned `true` for dates in the future relative to the reference date. The method is meant to check whether a date falls within the *last* 48 hours, but any future date was incorrectly accepted.

**Reproduction steps:**
1. Call `futureDate.isWithin48Hours(of: now)` where `futureDate` is any date after `now`
2. The method returns `true` instead of `false`

**Impact:** Low in current production code. The `DashboardView` uses its own cutoff-based comparison (`completionDate > cutoff`) rather than calling `isWithin48Hours`. However, the method is a public utility on `Date` and could be called by future code or extensions, silently including future-dated tasks in the "last 48 hours" filter.

## Investigation Summary

- **Symptoms examined:** `reference.timeIntervalSince(self)` returns a negative value when `self` is in the future, which is always `<= 48 * 60 * 60`
- **Code inspected:** `Date+TransitHelpers.swift`, `DashboardView.swift` (caller analysis)
- **Hypotheses tested:** Single hypothesis -- missing lower bound check on the time interval

## Discovered Root Cause

The comparison `reference.timeIntervalSince(self) <= 48 * 60 * 60` only checks the upper bound (not more than 48 hours in the past) but has no lower bound check. When `self` is in the future, the interval is negative, which trivially satisfies the `<=` condition.

**Defect type:** Missing validation (missing lower bound check)

**Why it occurred:** The original implementation assumed the method would only be called with past dates, so it only checked one direction.

**Contributing factors:** None -- straightforward logic error.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Extensions/Date+TransitHelpers.swift:5-7` - Added `interval >= 0` check to reject future dates

**Approach rationale:** The simplest correct fix: store the interval in a local variable and check both `>= 0` (not in the future) and `<= 48h` (not too far in the past).

**Alternatives considered:**
- Using `abs()` with the interval -- rejected because the method semantics are explicitly "within the *last* 48 hours", not "within 48 hours in either direction"

## Regression Test

**Test file:** `Transit/TransitTests/DateTransitHelpersTests.swift`
**Test names:** `futureDateReturnsFalse`, `dateOneSecondInFutureReturnsFalse`, `dateFarInFutureReturnsFalse`

**What it verifies:** Future dates (1 second, 1 hour, and 7 days ahead) are all rejected by `isWithin48Hours(of:)`. Also includes positive tests for past dates within/outside the 48-hour window and the boundary case.

**Run command:** `make test-quick` or `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -only-testing:TransitTests/DateTransitHelpersTests`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Extensions/Date+TransitHelpers.swift` | Added lower bound check (`interval >= 0`) |
| `Transit/TransitTests/DateTransitHelpersTests.swift` | New test file with 7 tests covering the 48-hour window logic |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- When writing range-check utility methods, always verify both bounds (lower and upper) explicitly
- Add tests for boundary conditions including the "wrong direction" case (future vs past, negative vs positive)

## Related

- Transit ticket: T-136
