# Bugfix Report: Report Date Range Rollover

**Date:** 2026-08-05
**Status:** In Progress

## Description of the Issue

An open report only recalculates when SwiftUI receives an unrelated state or data update. Its report data and date label are built inline with the default `Date.now`, so leaving the view open across a relative-range boundary can retain the previous period.

**Reproduction steps:**
1. Open Report with a relative range selected.
2. Leave it open across the next relevant local calendar boundary (midnight for current periods; week, month, or year boundary for completed periods).
3. Observe that the task set and displayed date label can remain from the previous snapshot until unrelated UI or data activity occurs.

**Impact:** Long-lived report screens can show stale period contents and labels, particularly when used overnight or left open while the app backgrounds and returns.

## Investigation Summary

### Phase 1: Initial Overview

Relative report ranges are expected to roll as calendar time advances, without a polling timer. Returning to an active scene must also refresh the view.

### Phase 2: Systematic Inspection

- `Transit/Transit/Views/Reports/ReportView.swift` calls `ReportLogic.buildReport` in `body` without retaining a time snapshot, scheduling a refresh, or observing scene activation.
- `Transit/Transit/Reports/ReportLogic.swift` passes its `now` value to both filtering and `ReportDateRange.labelWithDates`, but `ReportView` does not inject a stable value.
- `Transit/Transit/Intents/Shared/Utilities/DateFilterHelpers.swift` defines current periods as start-of-period through `now`, so current-week/month/year labels and filters need a new snapshot at the next local midnight. Previous periods remain stable until their next enclosing week/month/year boundary.

### Phase 3: Root Cause Analysis

**Defect type:** Missing time-driven state / stale view state.

1. Why does the report remain stale? `ReportView` owns no state that changes at a calendar boundary.
2. Why does `body` not recalculate? `@Query` and `selectedRange` can remain unchanged while time passes.
3. Why is the displayed label affected too? The label is generated from the same implicit current-time call only when `body` happens to rerun.
4. Why is a generic timer not appropriate? It would wake unnecessarily, be susceptible to lifecycle leaks, and still not model calendar/DST boundaries precisely.
5. Root cause: the view lacks a calendar-aware snapshot and one-shot boundary scheduling lifecycle.

## Resolution for the Issue

Pending implementation.

**Proposed approach:**
- Add pure `ReportRefreshScheduler` and `ReportRefreshState` types with injected clock and calendar providers.
- Schedule one cancellable SwiftUI task to the next local calendar boundary and recreate it when range, state snapshot, or scene phase changes.
- Capture one `now` and calendar snapshot for both filtering and date-label formatting; retain default behavior for existing App Intent and absolute-range callers.

**Alternatives considered:**
- Periodic `Timer` / `TimelineView` polling — rejected because it wakes unnecessarily and does not naturally model DST-aware calendar boundaries.
- Computing `Date.now` separately for label and report — rejected because a boundary between reads can make the displayed label and filtered data disagree.

## Regression Test

**Test file:** `Transit/TransitTests/ReportRefreshStateTests.swift`

**Test names:**
- `currentRangesRefreshAtLocalMidnight`
- `completedRangesRefreshAtPeriodBoundary`
- `refreshStateRollsReportAndLabelTogether`

**What they verify:** DST-aware local-midnight scheduling for current ranges, week/month/year boundary scheduling for completed ranges, and a single injected clock snapshot driving both report contents and label.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/Reports/ReportView.swift` | Add lifecycle-aware one-shot report refresh. |
| `Transit/Transit/Reports/ReportRefreshState.swift` | Add pure scheduler and injected snapshot state. |
| `Transit/Transit/Reports/ReportLogic.swift` | Accept the captured calendar for matching report data and labels. |
| `Transit/Transit/Reports/ReportDateRange.swift` | Format labels with the captured calendar. |
| `Transit/Transit/Intents/Shared/Utilities/DateFilterHelpers.swift` | Accept a defaulted calendar injection without changing absolute semantics. |
| `Transit/TransitTests/ReportRefreshStateTests.swift` | Add scheduling and rollover regressions. |

## Verification

**Automated:**
- [x] Regression suite fails before implementation because the scheduler/state APIs are absent.
- [ ] Regression test passes.
- [ ] Full test suite passes.
- [ ] Linters/validators pass.

**Manual verification:**
- Open each relative report range and keep it visible over its next relevant boundary.
- Background and reactivate the app after a boundary; confirm the report refreshes.

## Prevention

- Keep calendar-bound refresh decisions in pure, clock/calendar-injected logic.
- Use a single report snapshot for filter and label inputs.
- Prefer cancellable one-shot lifecycle tasks to polling timers for calendar boundaries.

## Related

- T-1838 — Open reports do not roll relative date ranges.
- T-1801 — Dashboard terminal-card expiry, related but independent.
