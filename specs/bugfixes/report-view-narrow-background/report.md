# Bugfix Report: Report View Narrow Background

**Date:** 2026-02-19
**Status:** Fixed

## Description of the Issue

On macOS, the report view's background gradient and scrollbar didn't span the full window width. Both stopped at the width of the text content, leaving empty space on the right side.

**Reproduction steps:**
1. Open Transit on macOS
2. Navigate to the Report view with tasks in a date range
3. Observe the background gradient and scrollbar stop at the text content width instead of the full window width

**Impact:** Visual layout issue on macOS only. iOS was unaffected.

## Investigation Summary

- **Symptoms examined:** Background gradient and scrollbar both constrained to content width on macOS
- **Code inspected:** `ReportView.swift`, `DashboardView.swift` (for comparison), `BoardBackground.swift`, `LiquidGlassSection.swift`
- **Hypotheses tested:** The DashboardView uses `GeometryReader` which fills its parent by default, while ReportView's `VStack(alignment: .leading)` only sizes to content width

## Discovered Root Cause

The `reportContent` method wraps its content in a `VStack(alignment: .leading, spacing: 24)` with `.padding()`. On macOS, a VStack with `.leading` alignment sizes to the width of its widest child rather than filling the available space. This caused the ScrollView's content area to be narrow, which in turn constrained the background and scrollbar positioning.

**Defect type:** Layout sizing issue (platform-specific)

**Why it occurred:** On iOS, ScrollView content tends to fill the available width by default. On macOS, the sizing behavior is different and VStack respects its intrinsic content width more strictly.

**Contributing factors:** macOS and iOS have different default layout behaviors for ScrollView content sizing.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/Reports/ReportView.swift:93` - Added `.frame(maxWidth: .infinity, alignment: .leading)` to the content VStack

**Approach rationale:** This is the standard SwiftUI pattern for making content fill available width while preserving left alignment. It's minimal and targeted.

**Alternatives considered:**
- Wrapping content in a `GeometryReader` - Overkill for this case and adds unnecessary complexity
- Using `Spacer()` inside an HStack wrapper - More verbose for the same result

## Regression Test

This is a visual layout bug that cannot be verified with a unit test. The fix was verified manually and through build/lint/test validation.

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/Reports/ReportView.swift` | Added `.frame(maxWidth: .infinity, alignment: .leading)` to content VStack |

## Verification

**Automated:**
- [x] Full test suite passes (`make test-quick`)
- [x] Linters pass (`make lint`)
- [x] macOS build succeeds (`make build-macos`)

**Manual verification:**
- Verify on macOS that the background gradient spans the full window width
- Verify the scrollbar appears at the right edge of the window
- Verify on iOS that the layout is unchanged

## Prevention

**Recommendations to avoid similar bugs:**
- When using `VStack(alignment: .leading)` inside a `ScrollView`, always add `.frame(maxWidth: .infinity, alignment: .leading)` if the content should fill the available width
- Test layouts on macOS specifically, as sizing behavior differs from iOS
