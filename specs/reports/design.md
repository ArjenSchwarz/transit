# Design: Report Functionality

## Overview

The report feature generates a summary of completed and abandoned tasks for a selected date range. It produces a structured data model consumed by two rendering paths: a native SwiftUI view for in-app display, and a Markdown formatter for clipboard export and the Shortcuts intent.

The feature follows existing Transit patterns: side-effect-free logic in a dedicated enum (like `DashboardLogic`), a new App Intent (like `QueryTasksIntent`), and navigation via `NavigationDestination`.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌───────────────────┐
│ ReportView   │────▶│ ReportLogic  │────▶│ DateFilterHelpers  │
│ (SwiftUI)    │     │ (stateless)  │     │ (extended)         │
└─────────────┘     └──────┬───────┘     └───────────────────┘
                           │
                    ┌──────▼───────┐
                    │  ReportData  │
                    │  (structs)   │
                    └──────┬───────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
┌─────────────────────┐   ┌──────────────────────┐
│ ReportView renders  │   │ ReportMarkdownFormat  │
│ native SwiftUI      │   │ generates GFM string  │
└─────────────────────┘   └──────────────────────┘
                                    ▲
                                    │
                          ┌─────────┴─────────┐
                          │ GenerateReport     │
                          │ Intent             │
                          └───────────────────┘
```

Data flows one direction: SwiftData query → `ReportLogic.buildReport()` → `ReportData` → consumed by SwiftUI view and/or `ReportMarkdownFormatter.format()`.

## Components and Interfaces

### 1. DateFilterHelpers Extension

**File:** `Transit/Transit/Intents/Shared/Utilities/DateFilterHelpers.swift` (modify existing)

Extend `DateRange` enum with new cases and update both `parseDateFilter` and `dateInRange`:

```swift
enum DateRange {
    case today          // existing
    case yesterday      // NEW
    case thisWeek       // existing
    case lastWeek       // NEW
    case thisMonth      // existing
    case lastMonth      // NEW
    case thisYear       // NEW
    case lastYear       // NEW
    case absolute(from: Date?, toDate: Date?)  // existing
}
```

New token mappings in `parseDateFilter`:
| Token | Case |
|-------|------|
| `"yesterday"` | `.yesterday` |
| `"last-week"` | `.lastWeek` |
| `"last-month"` | `.lastMonth` |
| `"this-year"` | `.thisYear` |
| `"last-year"` | `.lastYear` |

New `dateInRange` implementations:
- **yesterday**: `date >= calendar.startOfDay(for: now - 1 day) && date < calendar.startOfDay(for: now)`
- **lastWeek**: `calendar.dateInterval(of: .weekOfYear, for: now - 1 week)` → `date >= interval.start && date < interval.end`
- **lastMonth**: `calendar.dateInterval(of: .month, for: now - 1 month)` → `date >= interval.start && date < interval.end`
- **thisYear**: `date >= calendar.dateInterval(of: .year, for: now).start && date <= now`
- **lastYear**: `calendar.dateInterval(of: .year, for: now - 1 year)` → `date >= interval.start && date < interval.end`

**Boundary rule:** "This X" ranges use inclusive upper bound (`<= now`). "Last X" ranges use exclusive upper bound (`< interval.end`) because `Calendar.dateInterval.end` is the start of the next period. This prevents double-counting tasks completed exactly at a period boundary.

All calculations use `Calendar.current` for locale-aware week boundaries.

### 2. ReportDateRange Enum

**File:** `Transit/Transit/Reports/ReportDateRange.swift` (new)

A dedicated enum that serves double duty: drives the in-app menu picker and acts as the Shortcuts parameter type via `AppEnum`. Maps to `DateFilterHelpers.DateRange` for date calculation.

```swift
enum ReportDateRange: String, AppEnum, CaseIterable, Identifiable {
    case today = "today"
    case yesterday = "yesterday"
    case thisWeek = "this-week"
    case lastWeek = "last-week"
    case thisMonth = "this-month"
    case lastMonth = "last-month"
    case thisYear = "this-year"
    case lastYear = "last-year"

    nonisolated(unsafe) static var typeDisplayRepresentation: TypeDisplayRepresentation = "Date Range"

    nonisolated(unsafe) static var caseDisplayRepresentations: [ReportDateRange: DisplayRepresentation] = [
        .today: "Today",
        .yesterday: "Yesterday",
        .thisWeek: "This Week",
        .lastWeek: "Last Week",
        .thisMonth: "This Month",
        .lastMonth: "Last Month",
        .thisYear: "This Year",
        .lastYear: "Last Year",
    ]

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This Week"
        case .lastWeek: "Last Week"
        case .thisMonth: "This Month"
        case .lastMonth: "Last Month"
        case .thisYear: "This Year"
        case .lastYear: "Last Year"
        }
    }

    var dateRange: DateFilterHelpers.DateRange {
        switch self {
        case .today: .today
        case .yesterday: .yesterday
        case .thisWeek: .thisWeek
        case .lastWeek: .lastWeek
        case .thisMonth: .thisMonth
        case .lastMonth: .lastMonth
        case .thisYear: .thisYear
        case .lastYear: .lastYear
        }
    }
}
```

### 3. ReportData Model

**File:** `Transit/Transit/Reports/ReportData.swift` (new)

Plain structs representing the report structure. Not SwiftData models — these are transient, computed on demand.

```swift
struct ReportData {
    let dateRangeLabel: String
    let projectGroups: [ProjectGroup]
    let totalDone: Int
    let totalAbandoned: Int

    var totalTasks: Int { totalDone + totalAbandoned }
    var isEmpty: Bool { projectGroups.isEmpty }
}

struct ProjectGroup: Identifiable {
    let id: UUID              // project ID
    let projectName: String
    let tasks: [ReportTask]
    var doneCount: Int { tasks.filter { !$0.isAbandoned }.count }
    var abandonedCount: Int { tasks.filter { $0.isAbandoned }.count }
}

struct ReportTask: Identifiable {
    let id: UUID              // task ID
    let displayID: String     // e.g. "T-42" or "T-•"
    let name: String
    let isAbandoned: Bool
    let completionDate: Date
    let permanentDisplayId: Int?  // for sorting; not displayed directly
}
```

### 4. ReportLogic

**File:** `Transit/Transit/Reports/ReportLogic.swift` (new)

Static functions with no side effects, following the `DashboardLogic` pattern (enum with static methods, `now` parameter for testability). Operates on `[TransitTask]` model objects.

```swift
enum ReportLogic {
    static func buildReport(
        tasks: [TransitTask],
        dateRange: ReportDateRange,
        now: Date = .now
    ) -> ReportData
}
```

**Algorithm:**
1. Exclude tasks with nil `project` (orphan tasks, consistent with `DashboardLogic`)
2. Filter to terminal statuses (`.done`, `.abandoned`) with non-nil `completionDate`
3. Filter by `DateFilterHelpers.dateInRange(task.completionDate, range: dateRange.dateRange, now: now)`
4. Group by project (using project ID as key)
5. Sort groups alphabetically by project name (case-insensitive)
6. Sort tasks within each group by `completionDate` ascending, then `permanentDisplayId` ascending (nil sorts last), then `id` (UUID) as final tie-breaker
7. Compute summary counts
8. Return `ReportData`

### 5. ReportMarkdownFormatter

**File:** `Transit/Transit/Reports/ReportMarkdownFormatter.swift` (new)

Converts `ReportData` to a GFM Markdown string.

```swift
enum ReportMarkdownFormatter {
    static func format(_ data: ReportData) -> String
}
```

**Responsibilities:**
- Escape GFM metacharacters in user-generated content: `\`, `` ` ``, `*`, `_`, `~`, `[`, `]`, `#`, `<`, `>`, `|`
- Strip/normalize newlines in project names and task names
- Render abandoned tasks with `~~strikethrough~~ (Abandoned)`
- Per-project summary line: show both counts when both are non-zero (e.g., "3 done, 1 abandoned"); omit the zero count when only one type exists (e.g., "3 done" or "2 abandoned")
- Produce the template from requirement [2.8]
- Handle empty state ("No tasks completed or abandoned in this period.")

### 6. ReportView

**File:** `Transit/Transit/Views/Reports/ReportView.swift` (new)

Native SwiftUI view that renders `ReportData` directly (not by parsing Markdown).

```swift
struct ReportView: View {
    @Query(filter: #Predicate<TransitTask> {
        $0.statusRawValue == "done" || $0.statusRawValue == "abandoned"
    }) private var terminalTasks: [TransitTask]

    @State private var selectedRange: ReportDateRange = .thisWeek

    var body: some View {
        // Content
    }
}
```

**Layout:**
- **Toolbar:** Menu picker for date range, copy-to-clipboard button
- **Content:** ScrollView with:
  - Summary section (total counts)
  - Per-project sections with heading, per-project counts, and task list
  - Abandoned tasks shown with strikethrough styling and "(Abandoned)" label
  - Empty state when no tasks match
- **Styling:** Follow the app's existing visual patterns. Apply glass effects and theme-aware styling consistent with other pushed views (e.g., SettingsView)

**Copy button:** Generates Markdown via `ReportMarkdownFormatter.format()` and copies using platform-conditional code:
```swift
#if os(iOS)
UIPasteboard.general.string = markdown
#else
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(markdown, forType: .string)
#endif
```

**Accessibility identifiers:**
- `"report.dateRangePicker"` — date range menu picker
- `"report.copyButton"` — copy to clipboard button
- `"report.emptyState"` — empty state view

### 7. Navigation Integration

**File:** `Transit/Transit/Models/NavigationDestination.swift` (modify)

```swift
enum NavigationDestination: Hashable {
    case settings
    case projectEdit(Project)
    case report               // NEW
}
```

**File:** `Transit/Transit/TransitApp.swift` (modify)

Add destination case:
```swift
case .report:
    ReportView()
```

**File:** `Transit/Transit/Views/Dashboard/DashboardView.swift` (modify)

Add report button to toolbar, before the settings gear:
```swift
NavigationLink(value: NavigationDestination.report) {
    Label("Report", systemImage: "chart.bar.doc.horizontal")
}
```

### 8. GenerateReportIntent

**File:** `Transit/Transit/Intents/GenerateReportIntent.swift` (new)

User-facing intent with a native picker for date range selection. Since `ReportDateRange` conforms to `AppEnum`, Shortcuts presents a picker UI — no JSON parsing needed. Returns the Markdown report as a plain string.

```swift
struct GenerateReportIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Generate Report"
    nonisolated(unsafe) static var description = IntentDescription(
        "Generate a Markdown report of completed and abandoned tasks for a date range.",
        categoryName: "Reports"
    )
    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    @Parameter(title: "Date Range")
    var dateRange: ReportDateRange

    @Dependency
    private var taskService: TaskService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = GenerateReportIntent.execute(
            dateRange: dateRange,
            modelContext: taskService.modelContext
        )
        return .result(value: result)
    }

    @MainActor
    static func execute(dateRange: ReportDateRange, modelContext: ModelContext) -> String {
        // 1. Fetch terminal tasks via FetchDescriptor
        // 2. Build ReportData via ReportLogic.buildReport()
        // 3. Format as Markdown via ReportMarkdownFormatter.format()
        // 4. Return Markdown string
    }
}
```

No error handling needed — the picker constrains input to valid ranges, and `ReportLogic.buildReport()` always returns valid output (possibly empty).

### 9. TransitShortcuts Registration

**File:** `Transit/Transit/Intents/TransitShortcuts.swift` (modify)

Add `GenerateReportIntent` to the `appShortcuts` array so it appears in the Shortcuts app.

## Data Models

No new SwiftData models. The feature queries existing `TransitTask` and `Project` models. All report-specific types (`ReportData`, `ProjectGroup`, `ReportTask`) are transient structs computed on demand.

**Query strategy:** The `ReportView` uses `@Query` with a predicate filtering to terminal statuses. `ReportLogic.buildReport()` then performs in-memory date filtering and grouping. The `GenerateReportIntent` uses a `FetchDescriptor` with the same terminal-status predicate.

The predicate filters on `statusRawValue` (the stored string) rather than the computed `status` property, because `#Predicate` only works with stored properties.

## Error Handling

| Scenario | Component | Response |
|----------|-----------|----------|
| No tasks in range | ReportLogic | Returns `ReportData` with `isEmpty = true` |
| Task with nil completionDate | ReportLogic | Excluded from results (req [1.9]) |
| Task with nil project (orphan) | ReportLogic | Excluded from results |
| Task with provisional displayId | ReportLogic | Uses `DisplayID.formatted` ("T-•") |
| Markdown metacharacters in names | ReportMarkdownFormatter | Escaped before rendering |

No throwing errors in the report generation path — `ReportLogic.buildReport()` always returns a valid `ReportData` (possibly empty). The intent uses an `AppEnum` picker so invalid input is not possible.

## Testing Strategy

### Unit Tests

**ReportLogicTests** (`Transit/TransitTests/ReportLogicTests.swift`)

Tests for `ReportLogic.buildReport()` using in-memory SwiftData via `TestModelContainer`:

| Test | Validates |
|------|-----------|
| Tasks grouped by project | Req [1.5] |
| Projects sorted alphabetically (case-insensitive) | Req [1.6] |
| Tasks sorted by completionDate asc, displayId tie-break, UUID fallback | Req [1.7] |
| Only terminal tasks included | Req [1.1] |
| Nil completionDate excluded | Req [1.9] |
| Orphan tasks (nil project) excluded | DashboardLogic consistency |
| Date range filtering (one test per range) | Req [1.2], [1.4] |
| Boundary timestamps (midnight at period edges) | Req [1.4] |
| Empty result for no matching tasks | Req [1.8] |
| Provisional displayId uses DisplayID.formatted | Req [5.1] |

**ReportMarkdownFormatterTests** (`Transit/TransitTests/ReportMarkdownFormatterTests.swift`)

Tests for Markdown output:

| Test | Validates |
|------|-----------|
| Output matches template structure | Req [2.8] |
| Title includes date range label | Req [2.2] |
| Summary counts correct | Req [2.3], [2.7] |
| Per-project summary omits zero counts | Design: per-project line format |
| Abandoned tasks have strikethrough | Req [2.6] |
| Markdown metacharacters escaped (including backticks, pipes, angle brackets) | Req [2.7] |
| Newlines in names normalized | Req [2.7] |
| Empty state message | Req [1.8] |

**DateFilterHelpersTests** (`Transit/TransitTests/DateFilterHelpersTests.swift`)

Tests for new date range cases (extend existing test file):

| Test | Validates |
|------|-----------|
| Yesterday range boundaries (inclusive start, exclusive end) | Req [1.4] |
| Last week uses locale week start | Req [1.3] |
| Last week exclusive upper bound | Req [1.4] |
| Last month full calendar month | Req [1.4] |
| This year from Jan 1 to now | Req [1.4] |
| Last year full calendar year | Req [1.4] |
| Parse new tokens from JSON | Req [4.2] |
| Exact boundary timestamps (midnight) | Boundary rule |

**GenerateReportIntentTests** (`Transit/TransitTests/GenerateReportIntentTests.swift`)

| Test | Validates |
|------|-----------|
| Each date range returns non-empty Markdown for matching tasks | Req [4.3] |
| Empty date range returns empty-state Markdown | Req [1.8] |
| All 8 ReportDateRange cases produce valid output | Req [4.2] |

All test suites use `@Suite(.serialized)` for SwiftData tests and inject `now` for deterministic date assertions.

## File Summary

| File | Action | Component |
|------|--------|-----------|
| `Transit/Transit/Reports/ReportDateRange.swift` | New | Date range enum with labels and mapping |
| `Transit/Transit/Reports/ReportData.swift` | New | Transient data structs |
| `Transit/Transit/Reports/ReportLogic.swift` | New | Stateless query + grouping logic |
| `Transit/Transit/Reports/ReportMarkdownFormatter.swift` | New | GFM Markdown output |
| `Transit/Transit/Views/Reports/ReportView.swift` | New | Native SwiftUI report view |
| `Transit/Transit/Intents/GenerateReportIntent.swift` | New | Shortcuts App Intent |
| `Transit/Transit/Intents/Shared/Utilities/DateFilterHelpers.swift` | Modify | Add 5 new date range cases |
| `Transit/Transit/Intents/TransitShortcuts.swift` | Modify | Register GenerateReportIntent |
| `Transit/Transit/Models/NavigationDestination.swift` | Modify | Add `.report` case |
| `Transit/Transit/TransitApp.swift` | Modify | Handle `.report` navigation |
| `Transit/Transit/Views/Dashboard/DashboardView.swift` | Modify | Add toolbar report button |
| `Transit/TransitTests/ReportLogicTests.swift` | New | Logic tests |
| `Transit/TransitTests/ReportMarkdownFormatterTests.swift` | New | Formatter tests |
| `Transit/TransitTests/DateFilterHelpersTests.swift` | Modify | Add tests for new date range cases |
| `Transit/TransitTests/GenerateReportIntentTests.swift` | New | Intent tests |
