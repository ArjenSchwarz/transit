# Requirements: Shortcuts-Friendly Intents

## Introduction

This feature enhances Transit's App Intents to provide a better experience for Shortcuts users while maintaining backward compatibility with existing JSON-based CLI integrations. The enhancement includes:

1. Adding date filtering capabilities to the existing CLI-oriented `QueryTasksIntent`
2. Creating a new visual task creation intent (`Transit: Add Task`) with Shortcuts UI elements (dropdowns, text fields)
3. Creating a new visual task search intent (`Transit: Find Tasks`) with comprehensive filtering options
4. Implementing the necessary AppEntity and AppEnum infrastructure to support dynamic dropdowns in Shortcuts

These changes enable both power users (via CLI/JSON) and casual users (via Shortcuts visual interface) to effectively integrate with Transit.

---

## Requirements

### 1. Date Filtering for Existing Query Intent

**User Story:** As a CLI automation user, I want to filter tasks by completion date and status change date, so that I can query specific time ranges programmatically.

**Acceptance Criteria:**

1. <a name="1.1"></a>The QueryTasksIntent SHALL accept an optional `completionDate` filter in the JSON input
2. <a name="1.2"></a>The QueryTasksIntent SHALL accept an optional `lastStatusChangeDate` filter in the JSON input
3. <a name="1.3"></a>The date filters SHALL support relative time ranges: "today", "this-week", "this-month"
4. <a name="1.4"></a>The date filters SHALL support absolute date ranges with `from` and `to` ISO 8601 date strings (YYYY-MM-DD)
5. <a name="1.5"></a>Absolute date strings (YYYY-MM-DD) SHALL be interpreted in the user's local timezone using Calendar.current
6. <a name="1.6"></a>WHEN both `from` and `to` are provided, the system SHALL include tasks where the date falls within the range (inclusive)
7. <a name="1.7"></a>WHEN only `from` is provided, the system SHALL include tasks with dates on or after that date
8. <a name="1.8"></a>WHEN only `to` is provided, the system SHALL include tasks with dates on or before that date
9. <a name="1.9"></a>WHEN a relative time range is provided, the system SHALL calculate the date range based on the current date/time in the user's local timezone
10. <a name="1.10"></a>The system SHALL return an error IF an invalid date format is provided
11. <a name="1.11"></a>The system SHALL maintain backward compatibility with existing QueryTasksIntent usage (no breaking changes)
12. <a name="1.12"></a>The updated parameter description SHALL document the new date filter options with examples

---

### 2. Visual Task Creation Intent

**User Story:** As a Shortcuts user, I want to create tasks using visual input fields and dropdowns, so that I can quickly add tasks without writing JSON.

**Acceptance Criteria:**

1. <a name="2.1"></a>The system SHALL provide an intent named "Transit: Add Task" visible in the Shortcuts app
2. <a name="2.2"></a>The intent SHALL include a text field parameter for task name (required)
3. <a name="2.3"></a>The intent SHALL include a text field parameter for task description (optional)
4. <a name="2.4"></a>The intent SHALL include a dropdown parameter for task type with values sourced from the TaskType enum
5. <a name="2.5"></a>The intent SHALL include a dropdown parameter for project selection populated from existing projects via ProjectEntity
6. <a name="2.6"></a>The intent SHALL throw an error with code `NO_PROJECTS` IF no projects exist in the database
7. <a name="2.7"></a>The error message SHALL instruct users to create a project in the app first
8. <a name="2.8"></a>The intent SHALL create all tasks with initial status "idea" (matching existing CLI behavior)
9. <a name="2.9"></a>The intent SHALL accept optional metadata as a string parameter in key=value format (comma-separated)
10. <a name="2.10"></a>The intent SHALL return a structured TaskCreationResult containing: taskId (UUID), displayId (integer, if allocated), status (TaskStatus raw value), projectId (UUID), projectName (String)
11. <a name="2.11"></a>The intent SHALL declare `supportedModes` including `.foreground` to open the Transit app after execution (allowing users to view the created task)
12. <a name="2.12"></a>The intent SHALL validate that the task name is non-empty
13. <a name="2.13"></a>The intent SHALL integrate with the existing TaskService for task creation

---

### 3. Visual Task Search Intent

**User Story:** As a Shortcuts user, I want to find tasks using visual filters and receive structured results, so that I can build automations that process task data.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL provide an intent named "Transit: Find Tasks" visible in the Shortcuts app
2. <a name="3.2"></a>The intent SHALL include an optional dropdown parameter for task type filter
3. <a name="3.3"></a>The intent SHALL include an optional dropdown parameter for project filter
4. <a name="3.4"></a>The intent SHALL include an optional dropdown parameter for task status filter
5. <a name="3.5"></a>The intent SHALL include an optional date filter parameter for completion date with options: today, this-week, this-month, custom-range
6. <a name="3.6"></a>The intent SHALL include an optional date filter parameter for last status change date with options: today, this-week, this-month, custom-range
7. <a name="3.7"></a>WHEN custom-range is selected, the intent SHALL conditionally display `from` and `to` date parameters using App Intents ParameterSummary with When clauses
8. <a name="3.8"></a>The intent SHALL return a value of type `[TaskEntity]` where TaskEntity conforms to AppEntity
9. <a name="3.9"></a>Each TaskEntity SHALL include properties: taskId (UUID), displayId (Int?), name (String), status (TaskStatus raw value), type (TaskType raw value), projectId (UUID), projectName (String), lastStatusChangeDate (Date), completionDate (Date?)
10. <a name="3.10"></a>The intent SHALL return an empty array WHEN no tasks match the filter criteria
11. <a name="3.11"></a>WHEN no filters are specified, the intent SHALL return all tasks up to the result limit
12. <a name="3.12"></a>The intent SHALL limit results to a maximum of 200 tasks to prevent performance issues
13. <a name="3.13"></a>The intent SHALL sort results by lastStatusChangeDate descending (most recently changed first)
14. <a name="3.14"></a>The intent SHALL apply all specified filters using AND logic (all conditions must match)
15. <a name="3.15"></a>The intent SHALL declare `supportedModes` as `.background` only to support background Shortcuts automation workflows without opening the app
16. <a name="3.16"></a>The intent SHALL integrate with the existing ModelContext for task queries

---

### 4. TaskEntity Definition

**User Story:** As a Shortcuts automation builder, I want task data returned as structured entities, so that I can access task properties directly in Shortcuts without parsing JSON.

**Acceptance Criteria:**

1. <a name="4.1"></a>The system SHALL provide a `TaskEntity` struct conforming to `AppEntity` protocol
2. <a name="4.2"></a>The `TaskEntity` SHALL include an `id` property of type String (UUID string representation)
3. <a name="4.3"></a>The `TaskEntity` SHALL include a `displayRepresentation` property showing the task name and type
4. <a name="4.4"></a>The `TaskEntity` SHALL include all properties specified in requirement 3.9
5. <a name="4.5"></a>The system SHALL provide a `TaskEntityQuery` conforming to `EntityQuery` that resolves tasks by UUID string
6. <a name="4.6"></a>The `TaskEntity` SHALL reference `TaskEntityQuery` as its `defaultQuery` to satisfy AppEntity protocol requirements
7. <a name="4.7"></a>The `TaskEntity` SHALL provide a static initializer from a TransitTask model object
8. <a name="4.8"></a>The TaskCreationResult struct SHALL include all properties specified in requirement 2.10
9. <a name="4.9"></a>Both TaskEntity and TaskCreationResult SHALL use standard Swift types (String, Int, Date) that Shortcuts can natively serialize

---

### 5. AppEntity and AppEnum Infrastructure

**User Story:** As a developer implementing Shortcuts-friendly intents, I want reusable entity and enum types, so that dropdowns are consistently populated and maintained.

**Acceptance Criteria:**

1. <a name="5.1"></a>The system SHALL provide a `ProjectEntity` type conforming to `AppEntity`
2. <a name="5.2"></a>The `ProjectEntity` SHALL include properties: id (UUID), name (String)
3. <a name="5.3"></a>The system SHALL provide a `ProjectEntityQuery` type conforming to `EntityQuery`
4. <a name="5.4"></a>The `ProjectEntityQuery` SHALL fetch available projects from the SwiftData ModelContext
5. <a name="5.5"></a>The `ProjectEntityQuery` SHALL return an empty array WHEN no projects exist
6. <a name="5.6"></a>The system SHALL extend `TaskStatus` enum to conform to `AppEnum`
7. <a name="5.7"></a>The `TaskStatus` AppEnum conformance SHALL provide human-readable display names for each status
8. <a name="5.8"></a>The system SHALL extend `TaskType` enum to conform to `AppEnum`
9. <a name="5.9"></a>The `TaskType` AppEnum conformance SHALL provide human-readable display names for each type
10. <a name="5.10"></a>All AppEnum static properties SHALL be marked `nonisolated` to avoid MainActor isolation conflicts
11. <a name="5.11"></a>The entities and enums SHALL be reusable across multiple intent implementations

---

### 6. Backward Compatibility

**User Story:** As a CLI automation user with existing integrations, I want my current workflows to continue working unchanged, so that I don't need to rewrite my scripts.

**Acceptance Criteria:**

1. <a name="6.1"></a>The existing `QueryTasksIntent` SHALL remain available with its current JSON-based interface
2. <a name="6.2"></a>The existing `CreateTaskIntent` SHALL remain available with its current JSON-based interface
3. <a name="6.3"></a>The existing `UpdateStatusIntent` SHALL remain available unchanged
4. <a name="6.4"></a>The existing intent names SHALL remain unchanged: "Transit: Query Tasks", "Transit: Create Task", "Transit: Update Status"
5. <a name="6.5"></a>All existing JSON input formats SHALL continue to be accepted
6. <a name="6.6"></a>All existing JSON output formats SHALL remain unchanged
7. <a name="6.7"></a>Adding date filtering to `QueryTasksIntent` SHALL NOT break existing queries that don't use date filters
8. <a name="6.8"></a>The system SHALL NOT deprecate or remove any existing intent functionality

---

### 7. Error Handling

**User Story:** As a Shortcuts user, I want clear error messages when something goes wrong, so that I can understand and fix the problem.

**Acceptance Criteria:**

1. <a name="7.1"></a>The JSON-based intents (QueryTasksIntent, CreateTaskIntent, UpdateStatusIntent) SHALL continue to return structured error objects as JSON strings (existing behavior)
2. <a name="7.2"></a>The visual intents (Add Task, Find Tasks) SHALL throw typed errors that Shortcuts can display natively
3. <a name="7.3"></a>The system SHALL provide a custom error type for visual intents conforming to `LocalizedError` protocol
4. <a name="7.4"></a>Visual intent errors SHALL include an error code enum value and localized description
5. <a name="7.5"></a>The system SHALL use error code `NO_PROJECTS` WHEN no projects exist for task creation
6. <a name="7.6"></a>The system SHALL use error code `INVALID_INPUT` WHEN required parameters are missing or invalid
7. <a name="7.7"></a>The system SHALL use error code `INVALID_DATE` WHEN date parameters are malformed
8. <a name="7.8"></a>The system SHALL use error code `PROJECT_NOT_FOUND` WHEN a selected project no longer exists
9. <a name="7.9"></a>Error messages SHALL provide actionable guidance (e.g., "Create a project in Transit first")
10. <a name="7.10"></a>The visual task search intent SHALL NOT throw errors for empty results (return empty array instead)

---

### 8. Date Filter Implementation Details

**User Story:** As a developer implementing date filtering, I want clear specifications for date range calculations, so that behavior is consistent across all intents.

**Acceptance Criteria:**

1. <a name="8.1"></a>"today" SHALL include tasks with dates from 00:00:00 to 23:59:59 of the current day in the user's local timezone
2. <a name="8.2"></a>"this-week" SHALL include tasks from the start of the current calendar week (as defined by Calendar.current's first weekday based on user locale) at 00:00:00 to the current moment
3. <a name="8.3"></a>"this-month" SHALL include tasks from the 1st of the current month at 00:00:00 to the current moment
4. <a name="8.4"></a>Absolute date ranges SHALL use ISO 8601 format (YYYY-MM-DD) and be interpreted in the user's local timezone
5. <a name="8.5"></a>Date comparisons SHALL use Calendar-based day-level comparisons (not precise timestamps) by normalizing dates to start-of-day
6. <a name="8.6"></a>WHEN comparing date ranges, the system SHALL use inclusive boundaries (date >= fromDate AND date <= toDate at the day level)
7. <a name="8.7"></a>The system SHALL use Calendar.current for all date calculations to respect user locale settings
8. <a name="8.8"></a>The system SHALL handle nil date values (tasks with no completion date or status change yet) by excluding them from date-filtered results
