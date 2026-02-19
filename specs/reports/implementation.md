# Implementation Explanation: Report Functionality

## Beginner Level

### What Changed

Transit now has a **report feature** that lets you see what tasks you've completed or abandoned over a time period. You pick a date range (like "This Week" or "Last Month") and the app shows all your finished work, grouped by project.

There are two ways to use it:
1. **In the app**: A new "Report" button on the dashboard opens a dedicated report screen
2. **Via Shortcuts**: An automation action generates the same report as text you can pipe elsewhere

### Why It Matters

Before this feature, there was no way to look back and see what you accomplished. You'd have to manually scan through columns or filter tasks. Now you get a structured summary — useful for standups, weekly reviews, or just seeing your own progress.

### Key Concepts

- **Terminal tasks**: Tasks that are finished — either "Done" (completed successfully) or "Abandoned" (dropped). These are the only tasks that appear in reports.
- **Date range**: A time window like "This Week" or "Last Year". The report only shows tasks whose completion date falls within this window.
- **Markdown**: A text formatting language. The report generates Markdown so you can paste it into notes, docs, or chat and it looks formatted (headings, lists, strikethrough for abandoned tasks).
- **App Intent / Shortcuts**: Apple's automation framework. The report intent lets you generate reports from the Shortcuts app or command line without opening Transit.

---

## Intermediate Level

### Changes Overview

25 files changed across 5 commits, adding ~2900 lines. The feature introduces:

- **4 new source files** in `Transit/Transit/Reports/`: data model structs, date range enum, business logic, and markdown formatter
- **1 new view** in `Transit/Transit/Views/Reports/ReportView.swift`: native SwiftUI rendering
- **1 new intent** in `Transit/Transit/Intents/GenerateReportIntent.swift`: Shortcuts integration
- **5 modified files**: DateFilterHelpers (5 new date range cases), NavigationDestination (+`.report`), TransitApp (routing), DashboardView (toolbar button), TransitShortcuts (registration)
- **6 test files**: ~1100 lines of test coverage across logic, formatter, date ranges, intent, and helpers

### Implementation Approach

The architecture follows the existing Transit pattern of stateless logic enums:

1. **`ReportLogic.buildReport(tasks:dateRange:now:)`** — Pure function. Takes SwiftData task objects, filters to terminal tasks with valid `completionDate` in the selected range, groups by project, sorts alphabetically by project name, then by completionDate/displayId/UUID within each group. Returns a `ReportData` struct.

2. **`ReportMarkdownFormatter.format(_:)`** — Pure function. Takes `ReportData` and produces a GFM Markdown string. Handles escaping of 11 metacharacters, newline normalization, strikethrough for abandoned tasks, and per-project summary lines that omit zero counts.

3. **`ReportView`** — Uses `@Query` with a `#Predicate` filtering on `statusRawValue` to get terminal tasks from SwiftData. Calls `ReportLogic.buildReport()` inline in `body` so the report regenerates whenever the `@State selectedRange` changes. Copy button feeds the same `ReportData` through the Markdown formatter.

4. **`GenerateReportIntent`** — `AppIntent` with a native `ReportDateRange` picker parameter (no JSON parsing). Has a testable static `execute(dateRange:modelContext:)` method that fetches terminal tasks via `FetchDescriptor`, delegates to `ReportLogic` + `ReportMarkdownFormatter`, and returns plain text.

The `ReportDateRange` enum serves triple duty: drives the SwiftUI menu picker (`CaseIterable`), acts as the Shortcuts parameter type (`AppEnum`), and maps to `DateFilterHelpers.DateRange` for date calculation.

### Trade-offs

- **Separate `ReportDateRange` vs reusing `DateFilterHelpers.DateRange`**: The shared enum includes `.absolute(from:toDate:)` which isn't relevant for reports and lacks display labels. A dedicated enum keeps concerns separated at the cost of a thin mapping layer.

- **Native picker vs JSON input for the intent**: Existing Transit intents use JSON strings for CLI automation. The report intent uses a native `AppEnum` picker because it's user-facing in Shortcuts. This is inconsistent but the right UX choice — documented in Decision 12.

- **`@Query` in the view vs service method**: The view queries terminal tasks directly rather than going through `TaskService`. This is consistent with how `DashboardView` uses `@Query` and avoids adding a report-specific method to the service layer.

- **Two rendering paths**: The SwiftUI view renders from `ReportData` structs directly; the Markdown formatter produces text from the same data. This means two places that must stay in sync for display logic (e.g., summary text format), but avoids a third-party Markdown rendering dependency.

---

## Expert Level

### Technical Deep Dive

**Date boundary handling** is the most subtle aspect. `DateFilterHelpers` uses two helper methods:
- `dateInCurrentPeriod`: `date >= interval.start && date <= now` — inclusive on both ends. "This Week" includes right now.
- `dateInPreviousPeriod`: `date >= interval.start && date < interval.end` — exclusive upper bound. `Calendar.dateInterval.end` is the start of the next period, so `<` prevents double-counting a task completed at exactly midnight at a period boundary.

The `yesterday` case is hand-rolled (`startOfYesterday ..< startOfToday`) rather than using `dateInPreviousPeriod` with `.day`, because `Calendar.date(byAdding: .day, value: -1, to: now)` can land mid-day, and `dateInterval(of: .day, for:)` would then produce the correct interval anyway. Both approaches work; the explicit version is clearer.

**Sorting** uses a three-tier comparator: `completionDate` ascending, `permanentDisplayId` ascending (nil sorts last via explicit switch cases), then UUID string as final tie-breaker. The nil-last behavior ensures provisional tasks ("T-•") don't jump to the top of the list.

**Force unwraps** in `ReportLogic` (e.g., `$0.project!`, `task.completionDate!`) are safe because they follow immediately after a filter that guards against nil. The `Dictionary(grouping:)` on line 20 uses `$0.project!.id` which is guaranteed non-nil by the filter on line 13.

**GFM escaping** in the Markdown formatter handles 11 metacharacters in a specific order — backslash first to avoid double-escaping. Newlines (`\r\n`, `\r`, `\n`) are normalized to spaces before escaping, with `\r\n` first to prevent double-space artifacts.

### Architecture Impact

The feature is well-isolated. It adds no new SwiftData models, no new service classes, and no new dependencies. The only modification to existing services is making `TaskService.modelContext` internal (was private) so `GenerateReportIntent` can access it for its `FetchDescriptor`. This is a minor encapsulation loosening that's consistent with how the existing `QueryTasksIntent` already accesses the model context.

The `DateFilterHelpers` extension adds 5 new cases but the refactoring from a switch to a dictionary lookup for token parsing and the extraction of `dateInCurrentPeriod`/`dateInPreviousPeriod` helpers actually reduce the cyclomatic complexity of the existing code.

### Potential Issues

- **Performance**: `ReportLogic.buildReport()` does in-memory filtering and grouping on all terminal tasks. For a single-user app this is fine (unlikely to have thousands of terminal tasks), but if the dataset grew large, the `@Query` in `ReportView` fetches all terminal tasks on every body evaluation. A `FetchDescriptor` with a date predicate would be more efficient but `#Predicate` can't easily express the dynamic range logic.

- **`ReportView` body recomputation**: `ReportLogic.buildReport()` is called inside `body`. SwiftUI may call body multiple times per state change. The function is cheap (in-memory filtering/sorting), so this is acceptable. If it ever became expensive, memoization via `onChange(of: selectedRange)` with `@State` for the result would be the fix.

- **Clipboard feedback**: The "Copied" state uses `DispatchQueue.main.asyncAfter` for a 2-second reset. This works but `Task { try? await Task.sleep(for: .seconds(2)) }` would be more modern Swift Concurrency style. Both are fine for this use case.

## Completeness Assessment

### Fully Implemented
- All 8 date ranges with correct boundary behavior (req 1.2-1.4)
- Task filtering: terminal status, non-nil completionDate, project association (req 1.1, 1.9)
- Grouping by project with alphabetical sort (req 1.5-1.6)
- Task sorting with three-tier comparator (req 1.7)
- Empty state handling (req 1.8)
- Full Markdown template with GFM escaping (req 2.1-2.8)
- Dashboard toolbar button with NavigationStack push (req 3.1-3.2)
- Date range picker with default "This Week" (req 3.3, 3.7)
- Native SwiftUI rendering from structured data model (req 3.4)
- Copy-to-clipboard with platform-conditional code (req 3.5)
- Immediate regeneration on range change (req 3.6)
- App Intent with native picker and background execution (req 4.1-4.4)
- Provisional display ID handling (req 5.1)
- Test coverage for all logic paths, date ranges, formatting, and intent

### Partially Implemented
- None identified

### Missing
- None identified — all requirements from the spec are covered
