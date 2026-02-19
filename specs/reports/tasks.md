---
references:
    - specs/reports/requirements.md
    - specs/reports/design.md
    - specs/reports/decision_log.md
---
# Report Functionality

## Foundation

- [x] 1. Extend DateFilterHelpers with new date range cases <!-- id:1vyyl45 -->
  - Add 5 new cases to DateRange enum: yesterday, lastWeek, lastMonth, thisYear, lastYear
  - Implement dateInRange for each new case using Calendar.current
  - Boundary rule: Last X ranges use exclusive upper bound (date < interval.end), This X use inclusive (date <= now)
  - Add new token mappings in parseDateFilter: yesterday, last-week, last-month, this-year, last-year
  - File: Transit/Transit/Intents/Shared/Utilities/DateFilterHelpers.swift
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4)
  - References: specs/reports/design.md#1-datefilterhelpers-extension

- [x] 2. Write DateFilterHelpers tests for new date range cases <!-- id:1vyyl46 -->
  - Extend existing DateFilterHelpersTests with tests for each new range
  - Test yesterday boundaries (inclusive start, exclusive end at midnight)
  - Test lastWeek uses locale-aware week start and exclusive upper bound
  - Test lastMonth covers full previous calendar month
  - Test thisYear from Jan 1 to now
  - Test lastYear full previous calendar year
  - Test exact boundary timestamps (midnight at period edges) to verify inclusive/exclusive rules
  - Test parseDateFilter accepts new token strings
  - Use injected now parameter for deterministic assertions
  - File: Transit/TransitTests/DateFilterHelpersTests.swift
  - Blocked-by: 1vyyl45 (Extend DateFilterHelpers with new date range cases)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4)

- [x] 3. Create ReportDateRange enum with AppEnum conformance <!-- id:1vyyl47 -->
  - Create ReportDateRange: String, AppEnum, CaseIterable, Identifiable
  - 8 cases with raw values matching canonical JSON tokens
  - Add nonisolated(unsafe) static var typeDisplayRepresentation and caseDisplayRepresentations for Shortcuts picker
  - Add label computed property for in-app display
  - Add dateRange computed property mapping to DateFilterHelpers.DateRange
  - File: Transit/Transit/Reports/ReportDateRange.swift
  - Blocked-by: 1vyyl45 (Extend DateFilterHelpers with new date range cases)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [4.2](requirements.md#4.2)
  - References: specs/reports/design.md#2-reportdaterange-enum

- [x] 4. Create ReportData model structs <!-- id:1vyyl48 -->
  - Create ReportData struct: dateRangeLabel, projectGroups, totalDone, totalAbandoned, computed totalTasks and isEmpty
  - Create ProjectGroup struct: Identifiable, id (UUID), projectName, tasks, computed doneCount and abandonedCount
  - Create ReportTask struct: Identifiable, id (UUID), displayID (String), name, isAbandoned, completionDate, permanentDisplayId (Int? for sorting)
  - All are plain structs, not SwiftData models
  - File: Transit/Transit/Reports/ReportData.swift
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.5](requirements.md#1.5)
  - References: specs/reports/design.md#3-reportdata-model

## Core Logic

- [x] 5. Write ReportLogic tests <!-- id:1vyyl49 -->
  - Create ReportLogicTests using @Suite(.serialized) and TestModelContainer
  - Test tasks grouped by project (req 1.5)
  - Test projects sorted alphabetically case-insensitive (req 1.6)
  - Test tasks sorted by completionDate asc, permanentDisplayId asc tiebreak, UUID fallback (req 1.7)
  - Test only terminal tasks (done/abandoned) included (req 1.1)
  - Test nil completionDate excluded (req 1.9)
  - Test orphan tasks (nil project) excluded
  - Test date range filtering for each of the 8 ranges (req 1.2, 1.4)
  - Test boundary timestamps at period edges (req 1.4)
  - Test empty result when no tasks match (req 1.8)
  - Test provisional displayId uses DisplayID.formatted (req 5.1)
  - Inject now parameter for deterministic tests
  - File: Transit/TransitTests/ReportLogicTests.swift
  - Blocked-by: 1vyyl45 (Extend DateFilterHelpers with new date range cases), 1vyyl47 (Create ReportDateRange enum with AppEnum conformance), 1vyyl48 (Create ReportData model structs)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [1.7](requirements.md#1.7), [1.8](requirements.md#1.8), [1.9](requirements.md#1.9), [5.1](requirements.md#5.1)

- [x] 6. Implement ReportLogic.buildReport() <!-- id:1vyyl4a -->
  - Create enum ReportLogic with static func buildReport(tasks:dateRange:now:) -> ReportData
  - Algorithm: 1) Exclude orphan tasks, 2) Filter terminal statuses with non-nil completionDate, 3) Filter by DateFilterHelpers.dateInRange, 4) Group by project ID, 5) Sort groups by name (case-insensitive), 6) Sort tasks by completionDate asc then permanentDisplayId asc (nil last) then UUID, 7) Compute counts, 8) Return ReportData
  - Map TransitTask to ReportTask using DisplayID.formatted for display
  - File: Transit/Transit/Reports/ReportLogic.swift
  - Blocked-by: 1vyyl49 (Write ReportLogic tests)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [1.7](requirements.md#1.7), [1.9](requirements.md#1.9), [5.1](requirements.md#5.1)
  - References: specs/reports/design.md#4-reportlogic

## Markdown Formatter

- [x] 7. Write ReportMarkdownFormatter tests <!-- id:1vyyl4b -->
  - Create ReportMarkdownFormatterTests
  - Test output matches template structure from req 2.8
  - Test title includes date range label (req 2.2)
  - Test summary section with correct total and per-status counts (req 2.3)
  - Test per-project summary omits zero counts
  - Test abandoned tasks have strikethrough (Abandoned) format (req 2.6)
  - Test GFM metacharacter escaping: backslash, backtick, asterisk, underscore, tilde, brackets, hash, angle brackets, pipe (req 2.7)
  - Test newlines in project/task names are normalized (req 2.7)
  - Test empty state message (req 1.8)
  - File: Transit/TransitTests/ReportMarkdownFormatterTests.swift
  - Blocked-by: 1vyyl48 (Create ReportData model structs)
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [2.7](requirements.md#2.7), [2.8](requirements.md#2.8), [1.8](requirements.md#1.8)

- [x] 8. Implement ReportMarkdownFormatter.format() <!-- id:1vyyl4c -->
  - Create enum ReportMarkdownFormatter with static func format(_ data: ReportData) -> String
  - Implement GFM metacharacter escaping for user content
  - Strip/normalize newlines in project names and task names
  - Render abandoned tasks with strikethrough and (Abandoned) label
  - Per-project summary line: show both counts when non-zero, omit zero count
  - Handle empty state message
  - Follow template from req 2.8 exactly
  - File: Transit/Transit/Reports/ReportMarkdownFormatter.swift
  - Blocked-by: 1vyyl4b (Write ReportMarkdownFormatter tests)
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [2.7](requirements.md#2.7), [2.8](requirements.md#2.8)
  - References: specs/reports/design.md#5-reportmarkdownformatter

## UI Integration

- [x] 9. Add NavigationDestination.report and wire routing in TransitApp <!-- id:1vyyl4d -->
  - Add case report to NavigationDestination enum
  - Add .report case to navigationDestination switch in TransitApp.swift routing to ReportView()
  - Files: Transit/Transit/Models/NavigationDestination.swift, Transit/Transit/TransitApp.swift
  - Stream: 1
  - Requirements: [3.2](requirements.md#3.2)
  - References: specs/reports/design.md#7-navigation-integration

- [x] 10. Implement ReportView <!-- id:1vyyl4e -->
  - Create ReportView with @Query filtering terminal tasks
  - @State selectedRange: ReportDateRange = .thisWeek (default per req 3.7)
  - Toolbar: Menu picker for date range, copy-to-clipboard button
  - Content: ScrollView with summary, per-project sections, task list
  - Abandoned tasks: strikethrough styling + (Abandoned) label
  - Empty state when no tasks match
  - Copy button with #if os(iOS) UIPasteboard / #else NSPasteboard
  - Accessibility identifiers: report.dateRangePicker, report.copyButton, report.emptyState
  - Style consistent with app visual patterns (glass effects, theme-aware)
  - Report regenerates immediately when date range changes (req 3.6)
  - File: Transit/Transit/Views/Reports/ReportView.swift
  - Blocked-by: 1vyyl4a (Implement ReportLogic.buildReport()), 1vyyl4c (Implement ReportMarkdownFormatter.format()), 1vyyl4d (Add NavigationDestination.report and wire routing in TransitApp)
  - Stream: 1
  - Requirements: [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7)
  - References: specs/reports/design.md#6-reportview

- [x] 11. Add report button to DashboardView toolbar <!-- id:1vyyl4f -->
  - Add NavigationLink(value: NavigationDestination.report) to toolbar
  - Use Label(Report, systemImage: chart.bar.doc.horizontal)
  - Place before the settings gear button
  - File: Transit/Transit/Views/Dashboard/DashboardView.swift
  - Blocked-by: 1vyyl4d (Add NavigationDestination.report and wire routing in TransitApp)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1)
  - References: specs/reports/design.md#7-navigation-integration

## Shortcuts Integration

- [x] 12. Implement GenerateReportIntent <!-- id:1vyyl4g -->
  - Create GenerateReportIntent: AppIntent with nonisolated(unsafe) static properties
  - title: Transit: Generate Report, openAppWhenRun: false
  - Add IntentDescription with categoryName: Reports
  - @Parameter(title: Date Range) var dateRange: ReportDateRange
  - @Dependency private var taskService: TaskService
  - Testable static func execute(dateRange:modelContext:) -> String
  - Fetch terminal tasks via FetchDescriptor, build ReportData, format as Markdown
  - File: Transit/Transit/Intents/GenerateReportIntent.swift
  - Blocked-by: 1vyyl4a (Implement ReportLogic.buildReport()), 1vyyl4c (Implement ReportMarkdownFormatter.format())
  - Stream: 2
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4)
  - References: specs/reports/design.md#8-generatereportintent

- [x] 13. Register GenerateReportIntent in TransitShortcuts and write intent tests <!-- id:1vyyl4h -->
  - Add GenerateReportIntent to appShortcuts array in TransitShortcuts.swift
  - Create GenerateReportIntentTests with @Suite(.serialized)
  - Test each date range returns non-empty Markdown for matching tasks
  - Test empty range returns empty-state Markdown
  - Test all 8 ReportDateRange cases produce valid output
  - Files: Transit/Transit/Intents/TransitShortcuts.swift, Transit/TransitTests/GenerateReportIntentTests.swift
  - Blocked-by: 1vyyl4g (Implement GenerateReportIntent)
  - Stream: 2
  - Requirements: [4.2](requirements.md#4.2), [4.3](requirements.md#4.3)
  - References: specs/reports/design.md#9-transitshortcuts-registration

## Verification

- [x] 14. Build verification and lint <!-- id:1vyyl4i -->
  - Run make build to verify both iOS and macOS targets compile
  - Run make lint to check SwiftLint compliance
  - Run make test-quick to verify all unit tests pass
  - Fix any issues found
  - Blocked-by: 1vyyl4e (Implement ReportView), 1vyyl4f (Add report button to DashboardView toolbar), 1vyyl4h (Register GenerateReportIntent in TransitShortcuts and write intent tests)
  - Stream: 1
