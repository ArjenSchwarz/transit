# Implementation Explanation: Shortcuts-Friendly Intents

## Beginner Level

### What Changed

Transit is a task-tracking app for Apple platforms. Before this change, the only way to automate it was through a CLI-like interface that required writing raw JSON strings — fine for scripts, but unusable in Apple's Shortcuts app where regular users expect visual dropdown menus and text fields.

This feature adds two things:

1. **Visual intents** — new Shortcuts actions ("Add Task" and "Find Tasks") with proper UI elements. When you add these in Shortcuts, you see text fields for the task name, dropdown menus for project and type, and date pickers for filtering. No JSON required.

2. **Date filtering** — the existing CLI query command can now filter tasks by when they were completed or last changed. You can say "show me tasks completed today" or "tasks changed this week."

The old CLI commands continue working exactly as before. Nothing breaks for existing users.

### Why It Matters

Without this change, Transit's Shortcuts integration was effectively developer-only. The JSON-based interface is powerful but hostile to non-technical users. With visual intents, anyone building a Shortcut can add Transit actions using the same familiar dropdowns they see in other Shortcuts-enabled apps. Date filtering enables time-based automation workflows like "show me what I finished this week" or "what tasks changed today."

### Key Concepts

- **App Intent**: A way for iOS/macOS apps to expose actions to Shortcuts and Siri. Think of it as registering a command that the system can present to users.
- **AppEntity / AppEnum**: Swift types that tell Shortcuts how to display data. An `AppEntity` (like `ProjectEntity`) becomes a dropdown menu populated with real data. An `AppEnum` (like `TaskType`) becomes a fixed list of choices.
- **JSON-based intent vs Visual intent**: The JSON intents accept a single string parameter containing JSON. Visual intents use native Shortcuts parameters (text fields, dropdowns, date pickers) that the Shortcuts app renders natively.

---

## Intermediate Level

### Changes Overview

39 files changed across 5 commits. The implementation breaks down into:

**Shared infrastructure** (8 new files):
- `ProjectEntity` / `ProjectEntityQuery` — `AppEntity` + `EntityQuery` for project dropdown
- `TaskEntity` / `TaskEntityQuery` — `AppEntity` + `EntityQuery` for task results
- `TaskStatusAppEnum` / `TaskTypeAppEnum` — `AppEnum` extensions on existing enums
- `TaskCreationResult` — Return type for AddTaskIntent
- `DateFilterHelpers` — Shared date range calculation logic

**Visual intents** (3 new files):
- `AddTaskIntent` — Shortcuts-native task creation
- `FindTasksIntent` — Shortcuts-native task search with filters
- `VisualIntentError` — `LocalizedError` conforming error type

**Enhanced existing code** (1 modified file):
- `QueryTasksIntent` — Added date filtering to JSON interface

**Tests** (19 new files, 2 modified):
- Covering entities, enums, both visual intents, date filtering, backward compatibility, and integration flows

### Implementation Approach

**Dual-interface strategy**: Rather than modifying the existing JSON intents to add visual UI (which would break CLI users), new visual intents were created alongside them. Both share infrastructure through the `Shared/` directory.

**Static `execute` methods**: Both `AddTaskIntent` and `FindTasksIntent` use a static `execute(input:...)` pattern that takes a plain struct `Input` and explicit service/context dependencies. The `perform()` method (called by Shortcuts at runtime) delegates to `execute()`. This makes tests trivial — no need to instantiate the intent or mock `@Dependency` resolution.

**ParameterSummary with `When` clauses**: `FindTasksIntent` uses conditional parameter visibility. Date picker fields for custom ranges only appear when the user selects "Custom Range" from the dropdown. This is implemented via App Intents' `When(\.$completionDateFilter, .equalTo, .customRange)` syntax.

**Fetch-then-filter pattern**: `FindTasksIntent` and `TaskEntityQuery` fetch all tasks from SwiftData, then filter in memory. This works around SwiftData `#Predicate` limitations (can't do array membership checks like `allowedStatuses.contains(task.status)`). The 200-result limit caps performance impact.

**Date filtering shared via `DateFilterHelpers`**: Both `QueryTasksIntent` (JSON) and `FindTasksIntent` (visual) use the same `parseDateFilter` and `dateInRange` functions. The JSON intent parses date filter objects from the JSON, the visual intent maps `DateFilterOption` enum values to the same date ranges.

### Trade-offs

- **Two separate intents vs. one flexible intent**: Separate visual and JSON intents mean some duplication in parameter handling. But mixing native Shortcuts UI with JSON fallback in a single intent isn't well-supported by the App Intents framework, and it would complicate the parameter summary.
- **`compactMap` over `try/throw` in entity queries**: `TaskEntityQuery` uses `compactMap` with `try?` when converting tasks to entities. This silently drops tasks with nil projects rather than failing the entire query. The decision prioritizes CloudKit resilience — orphaned tasks from sync conflicts shouldn't break queries.
- **Fetch-all-then-filter vs. predicate-based**: Less efficient, but avoids SwiftData predicate limitations and keeps the filter logic testable in pure Swift.

---

## Expert Level

### Technical Deep Dive

**MainActor isolation**: The project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, meaning every type is `@MainActor` by default. `AppEnum` static properties (`typeDisplayRepresentation`, `caseDisplayRepresentations`) must be marked `nonisolated` to avoid isolation conflicts — the App Intents framework accesses these from non-main-actor contexts during parameter resolution.

**`LocalizedStringResource` comparison pitfall**: A static string literal like `"Idea"` creates a `LocalizedStringResource` with key `"Idea"`. String interpolation `"\(variable)"` creates one with key `"%@"` and a format argument. They render identically but are not equal under `==`. Tests must use `String(localized: resource)` to compare rendered values.

**Test isolation with shared `TestModelContainer`**: The in-memory SwiftData container is a process-wide singleton. `ModelContext` is just a view into the shared store — creating a "new context" doesn't isolate data. Every test must scope queries by a unique project (UUID-prefixed names) and filter results to avoid cross-suite contamination. Tests using `displayId` for lookups are particularly fragile since `findByDisplayID` searches the entire store.

**Date range semantics**: "today" normalizes to `startOfDay...endOfDay` using `Calendar.current`. "this-week" uses `Calendar.current.dateInterval(of: .weekOfYear, for:)` which respects the user's locale-specific first day of week. Absolute dates are parsed with `DateFormatter(dateFormat: "yyyy-MM-dd")` using `Calendar.current` and `TimeZone.current` to ensure locale-consistent interpretation.

**200-result limit**: `FindTasksIntent` caps results at 200. This is a pragmatic limit — Shortcuts serializes the entire result array through IPC to the Shortcuts process. Large result sets cause performance degradation and potential timeout.

### Architecture Impact

The shared entity/enum infrastructure establishes patterns for future visual intents. If "Transit: Update Status" gets a visual counterpart, it would reuse `TaskEntity`, `TaskStatusAppEnum`, and `VisualIntentError` directly.

The `TransitShortcuts` provider registers all 5 intents with the system. The `AppShortcutsProvider` includes `AppShortcut` entries with phrases for Siri integration, using `.systemEntity` for the phrases parameter.

The `DateFilterHelpers` utility creates a clean separation between date range semantics and the intent layer. Adding new relative ranges (e.g., "last-7-days") requires only a new case in the enum and range calculation — no changes to either intent.

### Potential Issues

- **SwiftData predicate limitations may worsen**: If more complex filters are needed (e.g., text search), the fetch-then-filter pattern will become a bottleneck. At that point, a migration to raw `NSPredicate` or custom `FetchDescriptor` predicates may be necessary.
- **`DateFilterOption.customRange` UX**: The conditional parameter display using `When` clauses works in Shortcuts but may not render correctly in all Siri Suggestions or Spotlight contexts. This is a known limitation of App Intents conditional summaries.
- **Orphan task handling**: `TaskEntity.from(_:)` throws when `task.project` is nil. `TaskEntityQuery` catches this with `compactMap(try?)`, silently dropping orphans. This is correct for query results but means CloudKit sync issues could cause tasks to "disappear" from Shortcuts results without any error indication.

---

## Completeness Assessment

### Fully Implemented
- All 8 requirement sections from the spec are addressed
- Date filtering for both JSON and visual interfaces
- Complete AppEntity/AppEnum infrastructure
- Visual task creation (AddTaskIntent) with all specified parameters
- Visual task search (FindTasksIntent) with all filter options and conditional UI
- Backward compatibility for all existing JSON intents
- Error handling with VisualIntentError for visual intents
- TransitShortcuts provider registering all 5 intents
- Test coverage across all new components

### Not Applicable / Deferred
- UI tests for Shortcuts integration (would require running the Shortcuts app, out of scope for unit tests)
- Siri phrase testing (requires on-device testing)

### No Gaps Identified
All requirements from the spec have corresponding implementation and test coverage. The design decisions documented in the decision log (21 decisions) are consistently reflected in the implementation.
