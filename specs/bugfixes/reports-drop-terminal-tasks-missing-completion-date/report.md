# Bugfix Report: Reports Drop Terminal Tasks Missing completionDate

**Date:** 2026-02-23
**Status:** Fixed
**Ticket:** T-208

## Description of the Issue

Terminal tasks (done/abandoned) and milestones with a `nil` `completionDate` were silently dropped from generated reports. The report would show fewer completed items than expected, with no indication that tasks were missing.

**Reproduction steps:**
1. Have a terminal task (status = done or abandoned) where `completionDate` is nil (legacy data or data created before `StatusEngine` was in use)
2. Generate a report for any date range
3. Observe that the task is missing from the report

**Impact:** Medium. Any terminal task or milestone without a `completionDate` (legacy data, direct database manipulation, or earlier bugs that failed to set it) would be invisible in reports. The dashboard handled this case defensively, but reports did not.

## Investigation Summary

The ticket description pointed directly to `ReportLogic.buildReport` as the source.

- **Symptoms examined:** Terminal tasks with nil `completionDate` absent from reports
- **Code inspected:** `ReportLogic.swift` (filter logic, sorting, `ReportTask` construction), `DashboardView.swift` (comparison of how dashboard handles the same case), `StatusEngine.swift` (how `completionDate` is set), `TransitTask.swift` and `Milestone.swift` (model fields)
- **Hypotheses tested:** Confirmed that `StatusEngine.applyTransition` always sets `completionDate` on terminal transitions, meaning nil values only arise from legacy data or direct model manipulation

## Discovered Root Cause

`ReportLogic.buildReport()` used `guard let completionDate = task.completionDate else { return false }` in both the task filter (line 16) and the milestone filter (line 24). This hard requirement on `completionDate` being non-nil caused any terminal task or milestone with a nil `completionDate` to be excluded from reports entirely.

**Defect type:** Missing fallback / overly strict guard

**Why it occurred:** The original implementation assumed `completionDate` would always be set for terminal tasks. While `StatusEngine` enforces this for normal transitions, it does not account for legacy data.

**Contributing factors:** The dashboard already handled this case with `task.completionDate?.isWithin48Hours(of: now) ?? true`, treating nil as "just completed". The reports code was written separately without adopting the same defensive pattern.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Reports/ReportLogic.swift` - Three locations changed:
  1. Task filter: replaced `guard let completionDate` with `let effectiveDate = task.completionDate ?? task.lastStatusChangeDate`
  2. Milestone filter: same pattern applied
  3. `buildReportTasks`: sorting and `ReportTask.completionDate` now use `task.completionDate ?? task.lastStatusChangeDate` instead of `.distantPast`

**Approach rationale:** `lastStatusChangeDate` is always set (non-optional `Date` field with a default) and is updated by `StatusEngine` on every transition, so for terminal tasks it closely approximates the actual completion time. This matches the ticket's suggestion and provides a meaningful date for both filtering and display.

**Alternatives considered:**
- **Treat nil as "include always"** (like the dashboard's `?? true`) - Would include tasks in every date range, which is incorrect for reports that should be time-bounded
- **Populate completionDate on load** (migration) - More invasive, requires a migration step, and still needs the fallback for the window between app versions

## Regression Test

**Test file:** `Transit/TransitTests/ReportLogicTests.swift`
**Test names:**
- `nilCompletionDateFallsBackToLastStatusChangeDate` - Verifies legacy tasks are included in reports
- `nilCompletionDateUsesLastStatusChangeDateForRange` - Verifies fallback date is used for range filtering (out-of-range tasks still excluded)
- `nilCompletionDateReportTaskUsesLastStatusChangeDate` - Verifies the `ReportTask.completionDate` uses the fallback

**Test file:** `Transit/TransitTests/ReportMilestoneTests.swift`
**Test name:** `milestonesWithoutCompletionDateFallBack` - Verifies legacy milestones are included

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Reports/ReportLogic.swift` | Fall back to `lastStatusChangeDate` when `completionDate` is nil in task filter, milestone filter, and `buildReportTasks` |
| `Transit/TransitTests/ReportLogicTests.swift` | Replaced "nil excluded" test with three fallback tests |
| `Transit/TransitTests/ReportMilestoneTests.swift` | Updated milestone nil completionDate test to verify fallback |
| `Transit/TransitTests/MilestoneDisplayNameTests.swift` | Fixed pre-existing compile error (nil -> "" for non-optional String param) |

## Verification

**Automated:**
- [x] Regression tests pass
- [x] Full test suite passes (`make test-quick`)
- [x] Linter passes (`make lint`)

## Prevention

**Recommendations to avoid similar bugs:**
- When filtering on optional dates, prefer a fallback over exclusion. Use `completionDate ?? lastStatusChangeDate` as the standard pattern for "effective completion date"
- The dashboard and reports should share a common helper for determining a task's effective completion date to avoid divergence
