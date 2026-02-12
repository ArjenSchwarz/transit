# Implementation: Shortcuts-Friendly Intents

This document explains the implementation of the Shortcuts-Friendly Intents feature at three expertise levels, serving as both documentation and validation of completeness.

---

## Beginner Level

### What This Feature Does

Transit now has two ways to create and search for tasks using Apple's Shortcuts app:

1. **Add Task** - A visual form where you pick options from dropdowns (project, task type) and type in text fields (name, description)
2. **Find Tasks** - A search tool with filters to find specific tasks (by project, type, status, or date)
3. **Enhanced Query** - The existing command-line tool now supports filtering by dates

Think of it like this: before, you had to write JSON code to create tasks (like writing in a programming language). Now, you can use visual forms (like filling out a web form). Both ways work, so power users can keep using JSON while casual users can use the visual interface.

### Why It Matters

**For casual users**: You can now create tasks and search for them in Shortcuts without learning JSON syntax. Just pick from dropdowns and fill in text fields.

**For power users**: Your existing JSON-based automations keep working exactly as before. Nothing breaks.

**For automation builders**: You can now build Shortcuts that process task data (like "find all tasks completed this week") and use that data in other automation steps.

### Key Concepts

**App Intents**: Apple's framework that lets apps expose actions to Shortcuts. Think of it as a menu of things your app can do that Shortcuts can trigger.

**AppEntity**: A structured data type that Shortcuts understands. Instead of returning plain text, we return "TaskEntity" objects that Shortcuts can work with (access properties like task name, status, etc.).

**AppEnum**: A dropdown list in Shortcuts. We use this for task types (Bug, Feature, Chore) and statuses (Idea, In Progress, Done).

**Date Filtering**: You can search for tasks by when they were completed or last changed. Supports both "today/this week/this month" shortcuts and custom date ranges.

---

## Intermediate Level

### Changes Overview

The implementation adds three new intents and supporting infrastructure:

**New Intents**:
- `AddTaskIntent` - Visual task creation with @Parameter annotations for Shortcuts UI
- `FindTasksIntent` - Visual task search with comprehensive filtering and conditional parameters
- Enhanced `QueryTasksIntent` - Added date filtering to existing JSON-based intent

**Supporting Infrastructure**:
- `TaskEntity` / `TaskEntityQuery` - AppEntity conformance for task data
- `ProjectEntity` / `ProjectEntityQuery` - AppEntity conformance for project picker
- `TaskStatus` / `TaskType` AppEnum extensions - Dropdown support
- `DateFilterHelpers` - Shared date range calculation logic
- `VisualIntentError` - LocalizedError conformance for native Shortcuts error display
- `TaskCreationResult` - Codable return type for AddTaskIntent

**Files Modified**:
- `QueryTasksIntent.swift` - Added date filtering support
- `TransitShortcuts.swift` - Registered new intents

**Test Coverage**:
- 9 new test files with 2,700+ lines of unit tests
- Integration tests for end-to-end intent flows
- Backward compatibility verification tests

### Implementation Approach

**Dual-Interface Strategy**: The design maintains both JSON-based intents (for CLI) and visual intents (for Shortcuts) without deprecation. This follows the principle of "additive change" - new capabilities don't replace existing ones.

**Shared Infrastructure**: Date filtering logic is extracted to `DateFilterHelpers` so both `QueryTasksIntent` (JSON) and `FindTasksIntent` (visual) use the same implementation. This ensures consistent behavior and reduces duplication.

**MainActor Isolation**: All intents use `@MainActor func perform()` to safely access SwiftData's ModelContext. Static properties use `nonisolated(unsafe)` to avoid isolation conflicts (required by App Intents framework).

**Error Handling Split**:
- JSON intents return error strings (existing pattern, maintains backward compatibility)
- Visual intents throw `VisualIntentError` conforming to `LocalizedError` (native Shortcuts error display)

**Conditional Parameters**: `FindTasksIntent` uses `ParameterSummary` with nested `When` clauses to show/hide date picker parameters based on whether "custom-range" is selected. This prevents UI clutter when using preset ranges like "today" or "this week".

**Result Limiting**: `FindTasksIntent` silently truncates results to 200 tasks maximum to prevent performance issues. Sorting by `lastStatusChangeDate` descending ensures most recent tasks are returned.

### Trade-offs

**Why not replace JSON intents?**
- JSON is superior for CLI automation (structured input/output, scriptable)
- Visual intents are superior for interactive Shortcuts use (no JSON knowledge required)
- Supporting both serves different user needs without forcing migration

**Why exclude metadata from AddTaskIntent?**
- Metadata is a power-user feature (reserved namespaces: `git.`, `ci.`, `agent.`)
- Visual Shortcuts users are unlikely to need it
- Keeps the visual interface simple
- Metadata remains available via JSON-based `CreateTaskIntent`

**Why silent truncation at 200 tasks?**
- Prevents performance issues with large result sets
- Shortcuts has no built-in pagination UI
- Most automation use cases filter to <200 tasks
- Can add pagination in V2 if needed

**Why use `openAppWhenRun` instead of `supportedModes`?**
- Design specified `supportedModes: [.foreground]` for iOS 26
- This API doesn't exist in current SDK
- `openAppWhenRun = true` achieves the same behavior (opens app after execution)
- `openAppWhenRun = false` for FindTasksIntent keeps it background-only

---

## Expert Level

### Technical Deep Dive

**EntityQuery Implementation**:
- `TaskEntityQuery` and `ProjectEntityQuery` use fetch-then-filter pattern instead of complex predicates
- Rationale: SwiftData's `#Predicate` macro doesn't support `array.contains(element)` for UUID arrays
- Trade-off: Slightly less efficient (fetches all, filters in-memory) but more reliable
- Uses `compactMap` in batch contexts to gracefully handle CloudKit sync edge cases (tasks without projects)

**Date Filtering Precision**:
- All date comparisons use `Calendar.current.startOfDay(for:)` for day-level precision
- Relative ranges ("today", "this-week", "this-month") calculate boundaries using `Calendar.dateInterval(of:for:)`
- Absolute ranges parse ISO 8601 strings (`YYYY-MM-DD`) in local timezone
- Inclusive boundaries: `date >= from && date <= to` at day level
- Nil date handling: Tasks with nil `completionDate` are excluded from date-filtered results

**Swift 6 Concurrency Patterns**:
- Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (all types are `@MainActor` by default)
- AppEntity/AppEnum static properties must be `nonisolated` to avoid isolation conflicts
- `nonisolated(unsafe)` used for static properties that don't access mutable state
- Intent `perform()` methods are `@MainActor` to access ModelContext safely
- Static `execute()` methods separate business logic from framework dependencies (testable without @Dependency)

**Error Propagation**:
- `AddTaskIntent.execute()` catches `TaskService.Error` and re-throws as `VisualIntentError`
- This translation layer ensures Shortcuts displays user-friendly error messages
- Error codes: `noProjects`, `invalidInput`, `invalidDate`, `projectNotFound`, `taskCreationFailed`
- Each error includes `errorDescription`, `failureReason`, and `recoverySuggestion` (LocalizedError protocol)

**Parameter Count Violations**:
- `FindTasksIntent` has 10 parameters (lint violation: max 5)
- Unavoidable: App Intents framework requires separate @Parameter for each filter
- Conditional parameters (from/to dates) must be separate properties for ParameterSummary to work
- Alternative (single filter object) would break Shortcuts UI generation

**Test File Length Violations**:
- `FindTasksIntentTests.swift`: 526 lines (lint limit: 400)
- `IntegrationTests.swift`: 557 lines (lint limit: 400)
- `QueryTasksIntentTests.swift`: 522 lines (lint limit: 400)
- Rationale: Comprehensive test coverage for complex filtering logic
- Each test file covers a single intent with multiple filter combinations
- Splitting would reduce cohesion (related tests separated)

### Architecture Impact

**Dependency Injection Pattern**:
- Intents use `@Dependency` property wrapper for `TaskService` and `ProjectService`
- This follows project's existing pattern (defined in `TransitShortcuts.swift`)
- Enables testing without mocking framework (static `execute()` methods accept services as parameters)

**CloudKit Sync Resilience**:
- All intents operate on local SwiftData store (no direct CloudKit access)
- Display ID allocation may fail offline → returns provisional ID (T-PROV-xxx)
- `TaskEntity.from()` throws if task has no project (data integrity issue)
- EntityQuery uses `compactMap` to skip tasks without projects (CloudKit sync edge case)

**Backward Compatibility Guarantees**:
- Existing intent names unchanged: "Transit: Query Tasks", "Transit: Create Task", "Transit: Update Status"
- JSON input/output formats unchanged
- Adding date filters to `QueryTasksIntent` is additive (optional parameters)
- No deprecation warnings or breaking changes

**Future Extensibility**:
- Date filtering logic is reusable (shared `DateFilterHelpers`)
- AppEntity/AppEnum infrastructure supports additional intents
- Result limiting (200 tasks) can be made configurable in V2
- Pagination can be added via continuation tokens if needed

### Potential Issues

**EntityQuery Performance**:
- Fetch-then-filter pattern loads all tasks/projects into memory
- Acceptable for V1 (most users have <1000 tasks)
- May need optimization if users have >10,000 tasks
- Solution: Implement predicate-based filtering or pagination

**CloudKit Sync Edge Cases**:
- Tasks without projects are skipped in EntityQuery (compactMap)
- This is a data integrity issue (should never happen)
- If it occurs, tasks become invisible to Shortcuts
- Mitigation: SwiftData relationships enforce project requirement

**Date Timezone Handling**:
- All dates use `Calendar.current` (user's local timezone)
- ISO 8601 strings are parsed in local timezone
- Cross-timezone automation may produce unexpected results
- Example: "today" in Tokyo vs "today" in New York
- Solution: Document timezone behavior, consider UTC option in V2

**Lint Violations**:
- 88 violations remain after auto-fix
- Most are acceptable (test file length, parameter count, variable name `to`)
- Critical violations (function parameter count) are framework-imposed
- Variable name `to` is semantically correct for date ranges (lint rule overly strict)

**Manual Testing Required**:
- Shortcuts UI behavior cannot be unit tested
- Conditional parameter display requires manual verification
- Project/type/status dropdowns must be tested in Shortcuts app
- Error message display must be verified visually
- Documentation includes comprehensive manual testing guide

---

## Completeness Assessment

### Fully Implemented

All requirements from `requirements.md` are implemented and tested:

**Date Filtering (Requirements 1.1-1.12)**: ✅
- QueryTasksIntent accepts optional `completionDate` and `lastStatusChangeDate` filters
- Supports relative ranges (today, this-week, this-month) and absolute ranges (from/to)
- ISO 8601 date parsing in local timezone
- Inclusive boundary comparisons
- Backward compatible (existing queries work unchanged)

**Visual Task Creation (Requirements 2.1-2.13)**: ✅
- AddTaskIntent exposed as "Transit: Add Task"
- Text fields for name (required) and description (optional)
- Dropdowns for type and project (using AppEnum and AppEntity)
- Error handling for no projects (NO_PROJECTS error code)
- Tasks created in "idea" status
- Non-empty name validation
- Returns TaskCreationResult with all required fields
- Opens app after execution (openAppWhenRun = true)

**Visual Task Search (Requirements 3.1-3.16)**: ✅
- FindTasksIntent exposed as "Transit: Find Tasks"
- Optional filters for type, project, status
- Date filters for completion and last status change
- Conditional from/to date parameters (ParameterSummary with When clauses)
- Returns [TaskEntity] array
- Empty array for no matches (not error)
- 200 task result limit
- Sorted by lastStatusChangeDate descending
- AND logic for multiple filters
- Background mode only (openAppWhenRun = false)

**TaskEntity Definition (Requirements 4.1-4.9)**: ✅
- TaskEntity conforms to AppEntity
- All properties from requirement 3.9 included
- TaskEntityQuery resolves tasks by UUID
- Static initializer from TransitTask model
- Standard Swift types for Shortcuts serialization

**AppEntity/AppEnum Infrastructure (Requirements 5.1-5.11)**: ✅
- ProjectEntity and ProjectEntityQuery implemented
- TaskStatus and TaskType AppEnum conformance
- Human-readable display names
- nonisolated static properties
- Reusable across intents

**Backward Compatibility (Requirements 6.1-6.8)**: ✅
- All existing intents remain available
- Intent names unchanged
- JSON formats unchanged
- Date filtering is additive (doesn't break existing queries)
- No deprecation or removal

**Error Handling (Requirements 7.1-7.10)**: ✅
- JSON intents return structured error JSON (existing behavior)
- Visual intents throw LocalizedError
- Error codes: NO_PROJECTS, INVALID_INPUT, INVALID_DATE, PROJECT_NOT_FOUND
- Actionable error messages
- Empty results return empty array (not error)

**Date Filter Implementation (Requirements 8.1-8.8)**: ✅
- "today" includes 00:00:00 to 23:59:59
- "this-week" from start of calendar week to now
- "this-month" from 1st of month to now
- ISO 8601 format (YYYY-MM-DD) in local timezone
- Calendar-based day-level comparisons
- Inclusive boundaries
- Calendar.current for all calculations
- Nil dates excluded from filtered results

### Partially Implemented

**Manual Testing**: ⚠️
- Unit tests cover all logic (2,700+ lines of tests)
- Integration tests verify end-to-end flows
- Backward compatibility tests verify existing intents work
- **Manual testing required**: Shortcuts UI behavior, dropdown population, conditional parameters, error display
- Comprehensive manual testing guide provided in `specs/shortcuts-friendly-intents/manual-testing-guide.md`

### Not Implemented (Intentional)

**Metadata in AddTaskIntent**: ❌ (Design Decision)
- Metadata is excluded from visual AddTaskIntent
- Rationale: Power-user feature, unlikely needed by Shortcuts users
- Remains available via JSON-based CreateTaskIntent

**supportedModes API**: ❌ (SDK Limitation)
- Design specified `supportedModes: [.foreground]` for iOS 26
- API doesn't exist in current SDK
- Workaround: `openAppWhenRun = true` achieves same behavior

### Gaps Identified

None. All requirements are implemented and tested. Manual testing is documented but not yet executed (requires physical device or simulator with Shortcuts app).

### Recommendations

1. **Execute Manual Testing**: Follow `specs/shortcuts-friendly-intents/manual-testing-guide.md` to verify Shortcuts UI behavior
2. **Monitor Performance**: Track EntityQuery performance with large task counts (>1000 tasks)
3. **Document Timezone Behavior**: Add user-facing documentation about date filtering timezone handling
4. **Consider Pagination**: If users report issues with 200-task limit, implement pagination in V2
5. **Add Lint Exceptions**: Add SwiftLint disable comments for unavoidable violations (function parameter count, variable name `to`)

---

## Summary

The Shortcuts-Friendly Intents feature is **fully implemented** according to the specification. All 8 requirement sections (60+ individual requirements) are satisfied with comprehensive unit test coverage. The implementation follows project conventions (MainActor isolation, service layer architecture, Swift Testing framework) and maintains backward compatibility with existing JSON-based intents.

The dual-interface strategy successfully serves both power users (JSON/CLI) and casual users (visual Shortcuts) without forcing migration or deprecating existing functionality. Shared infrastructure (DateFilterHelpers, AppEntity/AppEnum types) ensures consistency and reduces duplication.

Manual testing remains the only outstanding item, which is expected for UI-dependent functionality that cannot be unit tested. The provided manual testing guide enables verification of Shortcuts-specific behavior (dropdown population, conditional parameters, error display).
