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

## Effective Completion Date Pattern

When `completionDate` is nil on a terminal task or milestone (legacy data), `ReportLogic` falls back to `lastStatusChangeDate`. This applies in three places:
1. Task/milestone filtering (date range check)
2. Task sorting within a project group
3. `ReportTask.completionDate` field

The dashboard uses a similar defensive pattern: `task.completionDate?.isWithin48Hours(of: now) ?? true`.

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

## ReportView

Native SwiftUI view at `Transit/Transit/Views/Reports/ReportView.swift`.

- Uses `@Query` with `#Predicate` filtering on `statusRawValue` for terminal tasks
- `@State private var selectedRange: ReportDateRange = .thisWeek` (default per req 3.7)
- Calls `ReportLogic.buildReport()` inline in `body` — report regenerates on range change
- Copy button uses `ReportMarkdownFormatter.format()` with platform-conditional clipboard code
- Accessibility identifiers: `report.dateRangePicker`, `report.copyButton`, `report.emptyState`
- Navigation: `NavigationDestination.report` case, routed in `TransitApp.swift`
- Dashboard toolbar button placed before the settings gear

## GenerateReportIntent

App Intent that generates a markdown report via Shortcuts. Located at `Transit/Transit/Intents/GenerateReportIntent.swift`.

- `openAppWhenRun = false` — runs entirely in the background
- Has a static `execute(dateRange:modelContext:)` method for testability (avoids `@Dependency`)
- Fetches terminal tasks (done/abandoned) via `FetchDescriptor` with a predicate on `statusRawValue`
- Delegates to `ReportLogic.buildReport()` then `ReportMarkdownFormatter.format()`
- Registered in `TransitShortcuts.swift` with shortcut phrases
- `TaskService.modelContext` was changed from `private` to internal access to support this intent

## Test Infrastructure
- `ReportMarkdownFormatterTests` uses `@MainActor` (no `@Suite(.serialized)` needed — no SwiftData)
- `ReportLogicTests` uses `@Suite(.serialized)` with `TestModelContainer` since it needs SwiftData
- Test helpers in `ReportLogicTestHelpers.swift` for SwiftData-based tests
- Formatter tests construct `ReportData`/`ProjectGroup`/`ReportTask` directly via local helpers
- `GenerateReportIntentTests` uses `makeReportTestContext()` and tests the static `execute` method directly
- `IntentCompatibilityAndDiscoverabilityTests` checks shortcut count — must be updated when adding new shortcuts

## SwiftLint
This project enforces no trailing commas in collection literals (trailing_comma rule). Always omit trailing commas in array/dictionary literals.
