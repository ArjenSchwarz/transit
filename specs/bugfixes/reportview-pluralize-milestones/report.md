# Bugfix Report: ReportView pluralizes one-task milestones incorrectly

**Date:** 2026-05-30
**Status:** Fixed

## Description of the Issue

`ReportView.milestoneRow(_:)` always rendered `"\(milestone.taskCount) tasks"`, so a
milestone with exactly one assigned task appeared as `1 tasks` in the native report UI.
The Markdown formatter already handled the singular form correctly, so the two report
surfaces disagreed for single-task milestones.

**Reproduction steps:**
1. Create a milestone and assign exactly one task to it.
2. Complete or abandon that task so it appears in a report date range.
3. Open the in-app Report view and observe the milestone shows `1 tasks` (incorrect).

**Impact:** Cosmetic — incorrect grammar in the native report UI. Low severity, but
inconsistent with the Markdown report which already pluralized correctly.

## Investigation Summary

- **Symptoms examined:** Hardcoded `"\(milestone.taskCount) tasks"` string in the view.
- **Code inspected:** `Views/Reports/ReportView.swift`, `Reports/ReportMarkdownFormatter.swift`,
  `Reports/ReportData.swift`.
- **Hypotheses tested:** Confirmed the Markdown formatter (`formatMilestone`) already
  branched on `taskCount == 1`, while the SwiftUI view did not. The duplication was the
  reason the two surfaces could diverge.

## Discovered Root Cause

The pluralization logic existed only in `ReportMarkdownFormatter.formatMilestone(_:)`. The
SwiftUI `ReportView` used its own unconditional `"... tasks"` string, so the singular case
was never handled there.

**Defect type:** Logic error / duplicated logic that drifted between two call sites.

**Why it occurred:** The pluralization rule was implemented inline in the formatter and not
shared, so the view's separate rendering path missed it.

**Contributing factors:** No single source of truth for the human-facing task-count label.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Reports/ReportData.swift` — added a `taskCountLabel` computed property on
  `ReportMilestone` that returns `"1 task"` for a single task and `"\(taskCount) tasks"`
  otherwise.
- `Transit/Transit/Views/Reports/ReportView.swift:152` — render `milestone.taskCountLabel`
  instead of the hardcoded `"\(milestone.taskCount) tasks"`.
- `Transit/Transit/Reports/ReportMarkdownFormatter.swift:49` — use `milestone.taskCountLabel`
  instead of the inline ternary, removing the duplicated logic.

**Approach rationale:** Centralizing the label on the model gives both report surfaces a
single source of truth, fixing the view bug and preventing future drift. It is also
directly unit-testable, unlike the SwiftUI view's rendered text.

**Alternatives considered:**
- Inline the `taskCount == 1` ternary directly in the view — Rejected: would re-duplicate
  the logic and leave the same drift risk.

## Regression Test

**Test file:** `Transit/TransitTests/ReportMilestoneTaskCountLabelTests.swift`
**Test name:** `ReportMilestone taskCountLabel` suite (`singularForm`, `zeroTasks`, `multipleTasks`)

**What it verifies:** `taskCountLabel` returns `"1 task"` for a single task and the plural
form for zero and multiple tasks. The singular case directly covers the reported bug.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Reports/ReportData.swift` | Added `taskCountLabel` computed property |
| `Transit/Transit/Views/Reports/ReportView.swift` | Use `taskCountLabel` for milestone row |
| `Transit/Transit/Reports/ReportMarkdownFormatter.swift` | Use `taskCountLabel`, drop inline ternary |
| `Transit/TransitTests/ReportMilestoneTaskCountLabelTests.swift` | New regression tests |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (`make test-quick`)
- [x] Linters/validators pass (`make lint`)

**Manual verification:**
- Code review confirms both report surfaces now route through the shared property.

## Prevention

**Recommendations to avoid similar bugs:**
- Keep human-facing formatting (pluralization, labels) on the data model rather than
  inline in individual views/formatters, so all surfaces share one source of truth.

## Related

- Transit ticket T-879
