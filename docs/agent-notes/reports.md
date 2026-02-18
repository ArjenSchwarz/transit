# Reports Feature

## Architecture

The reports feature generates markdown summaries of completed/abandoned tasks grouped by project.

### Data Flow
1. `ReportLogic.buildReport(tasks:dateRange:now:)` filters SwiftData tasks and produces `ReportData`
2. `ReportMarkdownFormatter.format(_:)` converts `ReportData` to a GFM markdown string
3. `ReportView` (UI) and `GenerateReportIntent` (Shortcuts) consume both

### Key Files
- `Transit/Transit/Reports/ReportData.swift` — Plain structs: `ReportData`, `ProjectGroup`, `ReportTask`
- `Transit/Transit/Reports/ReportDateRange.swift` — `AppEnum` with 8 date range cases
- `Transit/Transit/Reports/ReportLogic.swift` — Filtering, grouping, sorting logic
- `Transit/Transit/Reports/ReportMarkdownFormatter.swift` — GFM markdown rendering

## ReportMarkdownFormatter

### Escape Order
Backslash must be escaped first, then other GFM metacharacters. The full set: `\`, `` ` ``, `*`, `_`, `~`, `[`, `]`, `#`, `<`, `>`, `|`.

### Newline Normalization
`\r\n`, `\r`, and `\n` are replaced with spaces before escaping. The `\r\n` replacement comes first to avoid double-spacing.

### Summary Line Logic
- Both counts non-zero: "3 done, 1 abandoned"
- Only done: "3 done"
- Only abandoned: "2 abandoned"
- This applies to both the top-level summary (inside parentheses after task count) and per-project summaries.

### Empty State
When `ReportData.isEmpty` is true, outputs title + "No tasks completed or abandoned in this period." with no summary or project sections.

## Test Infrastructure
- `ReportMarkdownFormatterTests` uses `@MainActor` (no `@Suite(.serialized)` needed — no SwiftData)
- `ReportLogicTests` uses `@Suite(.serialized)` with `TestModelContainer` since it needs SwiftData
- Test helpers in `ReportLogicTestHelpers.swift` for SwiftData-based tests
- Formatter tests construct `ReportData`/`ProjectGroup`/`ReportTask` directly via local helpers

## SwiftLint
This project enforces no trailing commas in collection literals (trailing_comma rule). Always omit trailing commas in array/dictionary literals.
