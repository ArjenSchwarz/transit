# Bugfix Report: Report Summaries Ignore Terminal Milestones

**Date:** 2026-05-30
**Status:** Fixed

## Description of the Issue

Reports include terminal (done/abandoned) milestones, and can render a project
group that contains only milestones and no terminal tasks. However, every summary
count in a report was derived purely from task counts. As a result, a report
containing only completed/abandoned milestones produced misleading summaries:

- Top-level header rendered `**0 tasks** (0 done)`
- Per-project summary rendered `0 done`

even though the report body listed one or more completed/abandoned milestones.

**Reproduction steps:**
1. Complete (or abandon) a milestone in a project that has no terminal tasks in the period.
2. Open the Report view (or generate a report via `GenerateReportIntent`).
3. Observe the milestone is listed, but the summary reads `0 tasks (0 done)` / `0 done`.

**Impact:** Cosmetic but confusing — summaries contradicted the report body and
undercounted completed work. Scope: report rendering (in-app view, markdown
formatter, and CLI/automation report intent).

## Investigation Summary

- **Symptoms examined:** Summary lines showing zero counts despite milestones being present.
- **Code inspected:** `ReportData`, `ReportLogic.buildReport`, `ReportMarkdownFormatter`, `ReportView`.
- **Hypotheses tested:** Considered excluding milestone-only groups entirely; rejected
  because milestones are deliberately surfaced in reports, so the right fix is to count them.

## Discovered Root Cause

`ReportData.totalTasks` is `totalDone + totalAbandoned`, and `ProjectGroup.doneCount` /
`abandonedCount` only filter the `tasks` array. Milestones were never reflected in any
summary count, so a milestone-only group (or any milestone) contributed nothing to the
summaries.

**Defect type:** Logic error (incomplete aggregation).

**Why it occurred:** Milestone support was added to the report body and grouping, but the
summary aggregation was not extended to include milestone counts.

**Contributing factors:** The single `summaryText(done:abandoned:)` helper had no notion
of milestones, so callers could only express task counts.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Reports/ReportData.swift` — Added `doneMilestoneCount` /
  `abandonedMilestoneCount` to `ProjectGroup`; added `totalMilestonesDone` /
  `totalMilestonesAbandoned` to `ReportData` (defaulting to 0 to preserve existing
  call sites); added a milestone-aware `summaryText(done:abandoned:milestonesDone:milestonesAbandoned:)`
  overload that appends milestone counts only when present.
- `Transit/Transit/Reports/ReportLogic.swift` — Compute milestone totals from group-level
  counts and pass them into `ReportData`.
- `Transit/Transit/Reports/ReportMarkdownFormatter.swift` — Use the milestone-aware
  summary for both the top-level and per-project summaries.
- `Transit/Transit/Views/Reports/ReportView.swift` — Same, for the in-app summary sections.

**Approach rationale:** Milestones are intentionally part of reports, so the consistent
fix is to represent them in the summaries rather than hide milestone-only groups. The new
summary overload keeps the task-only output byte-for-byte identical when no milestones are
present, so existing reports and tests are unaffected.

**Alternatives considered:**
- Exclude milestone-only project groups from reports — rejected; it would hide
  legitimately completed work that the design chooses to surface.
- Fold milestones into `totalTasks` — rejected; conflates two distinct entities and would
  make `N tasks` inaccurate.

## Regression Test

**Test file:** `Transit/TransitTests/ReportMilestoneSummaryTests.swift`
**Test names:** `milestoneOnlyGroupReportsMilestoneDone`, `abandonedMilestoneCounted`,
`topLevelTotalsIncludeMilestones`, `markdownSummaryMentionsMilestones`, `taskOnlySummaryUnchanged`

**What it verifies:** Milestone done/abandoned counts appear in per-project and top-level
totals; the markdown summary mentions milestones for a milestone-only report; and the
task-only summary output is unchanged (no spurious milestone text).

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Reports/ReportData.swift` | Milestone counts + milestone-aware summary helper |
| `Transit/Transit/Reports/ReportLogic.swift` | Aggregate and pass milestone totals |
| `Transit/Transit/Reports/ReportMarkdownFormatter.swift` | Milestone-aware summaries |
| `Transit/Transit/Views/Reports/ReportView.swift` | Milestone-aware summaries |
| `Transit/TransitTests/ReportMilestoneSummaryTests.swift` | New regression tests |

## Verification

**Automated:**
- [x] Regression tests pass
- [x] Full unit test suite passes (`make test-quick`)
- [x] Linters pass (`make lint`)

**Manual verification:**
- Reviewed markdown output logic: milestone-only report now reads e.g.
  `**0 tasks** (0 done, 1 milestone done)` instead of `**0 tasks** (0 done)`.

## Prevention

**Recommendations to avoid similar bugs:**
- When adding a new entity to a report, extend aggregation/summary logic in the same change,
  not just the rendering of the body.
- Keep summary helpers entity-aware so callers cannot silently omit a category.

## Related

- Transit ticket: T-877
