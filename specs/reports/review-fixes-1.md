---
references:
    - specs/reports/review-overview-1.md
---
# PR Review Fixes - Iteration 1

- [x] 1. Fix pluralization bug in ReportMarkdownFormatter (1 task vs N tasks)

- [x] 2. Deduplicate summary logic — move summaryText to ReportData

- [x] 3. Replace DispatchQueue.main.asyncAfter with .task in copyConfirmationBanner

- [x] 4. Add OSLog error logging in GenerateReportIntent fetch error path

- [x] 5. Remove force-unwraps in ReportLogic.buildReport using safe unwraps

- [x] 6. Use reduce over ProjectGroup counts instead of flatMap+filter for totals

- [x] 7. Remove stale CHANGELOG entry about TaskService.modelContext

- [x] 8. Fix PR description — remove mention of all time date range
