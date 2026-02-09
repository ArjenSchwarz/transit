# Requirements: Transit V1

## Introduction

Transit V1 is a native Apple task tracker for a single user across iOS 26, iPadOS 26, and macOS 26. It provides a kanban-style dashboard for tracking tasks through defined stages, with CloudKit sync between devices and CLI integration via App Intents. The app uses Liquid Glass design throughout and supports offline task creation.

This document defines the requirements for the complete V1 implementation. The design document (`docs/transit-design-doc.md`) is the authoritative source for visual design, interaction patterns, and architectural decisions. These requirements formalize the "what" in testable acceptance criteria.

---

### 1. Project Data Model

**User Story:** As a user, I want to create and manage projects so that I can group related tasks together.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL store Project records with the following fields: id (UUID), name (String, required), description (String, required), gitRepo (String, optional), color (Color, required)
2. <a name="1.2"></a>The system SHALL use the Project's UUID as the CloudKit record identifier
3. <a name="1.3"></a>The system SHALL enforce that every Project has a name, description, and color
4. <a name="1.4"></a>The system SHALL allow the user to create a project by providing a name, description, optional git repo URL, and a color selected via a color picker
5. <a name="1.5"></a>The system SHALL allow the user to edit a project's name, description, git repo URL, and color
6. <a name="1.6"></a>The system SHALL NOT support project deletion in V1

---

### 2. Task Data Model

**User Story:** As a user, I want to create and track tasks with structured metadata so that I can see my work status at a glance.

**Acceptance Criteria:**

1. <a name="2.1"></a>The system SHALL store Task records with the following fields: id (UUID), displayId (Integer), name (String, required), description (String, optional), status (Enum), type (Enum), lastStatusChangeDate (Date), completionDate (Date, optional), metadata ([String: String], optional)
2. <a name="2.2"></a>The system SHALL use the Task's UUID as the CloudKit record identifier
3. <a name="2.3"></a>Each Task SHALL belong to exactly one Project
4. <a name="2.4"></a>The system SHALL allow tasks to be moved between projects via the detail view edit mode
5. <a name="2.5"></a>The system SHALL support the following task types as a hardcoded set: bug, feature, chore, research, documentation
6. <a name="2.6"></a>The system SHALL store metadata as free-form string key-value pairs with no schema enforcement
7. <a name="2.7"></a>The system SHALL NOT support task deletion in V1 — tasks can only be abandoned

---

### 3. Task Display ID Allocation

**User Story:** As a user, I want human-readable task IDs (e.g., T-42) so that I can reference tasks in conversation, CLI commands, and git commits.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL allocate display IDs from a single counter record in CloudKit using optimistic locking
2. <a name="3.2"></a>Display IDs SHALL be sequential integers, globally scoped across all projects
3. <a name="3.3"></a>Display IDs MAY have gaps due to sync conflicts
4. <a name="3.4"></a>WHEN a task is created offline, the system SHALL assign a provisional local ID
5. <a name="3.5"></a>WHEN an offline-created task syncs for the first time, the system SHALL replace the provisional ID with a permanent display ID allocated from the counter record
6. <a name="3.6"></a>The system SHALL format permanent display IDs as "T-{number}" (e.g., T-1, T-42) in all UI surfaces
7. <a name="3.7"></a>Provisional display IDs SHALL render as "T-•" with a secondary/dimmed text style to indicate the ID is pending sync
8. <a name="3.8"></a>WHEN optimistic locking fails during display ID allocation, the system SHALL retry the allocation

---

### 4. Task Status Progression

**User Story:** As a user, I want tasks to move through defined stages so that I can track work from idea to completion.

**Acceptance Criteria:**

1. <a name="4.1"></a>The system SHALL support the following statuses in this order: Idea, Planning, Spec, Ready for Implementation, In Progress, Ready for Review, Done, Abandoned
2. <a name="4.2"></a>WHEN a task's status changes, the system SHALL update `lastStatusChangeDate` to the current timestamp
3. <a name="4.3"></a>WHEN a task's status changes to Done, the system SHALL set `completionDate` to the current timestamp (per [7.2](#7.2))
4. <a name="4.4"></a>WHEN a task's status changes to Abandoned, the system SHALL set `completionDate` to the current timestamp (per [11.4](#11.4))
5. <a name="4.5"></a>The system SHALL allow tasks to be abandoned from any status, including Done, via the detail view
6. <a name="4.6"></a>WHEN an abandoned task is restored, the system SHALL set its status to Idea and clear its `completionDate` (per [11.5](#11.5))
7. <a name="4.7"></a>New tasks created via the UI SHALL always start in Idea status (per [10.3](#10.3))
8. <a name="4.8"></a>WHEN a Done or Abandoned task's status changes to a non-terminal status (via drag or detail view), the system SHALL clear its `completionDate`

---

### 5. Dashboard — Kanban Board

**User Story:** As a user, I want a kanban dashboard showing all active tasks across projects so that I can see my workload at a glance.

**Acceptance Criteria:**

1. <a name="5.1"></a>The dashboard SHALL be the root view, displayed on every app launch
2. <a name="5.2"></a>The dashboard SHALL display five visual columns: Idea, Planning, Spec, In Progress, Done / Abandoned
3. <a name="5.3"></a>Tasks with "Ready for Implementation" status SHALL render within the Spec column, visually promoted above other Spec tasks with a distinct highlight or badge indicating they require human attention
4. <a name="5.4"></a>Tasks with "Ready for Review" status SHALL render within the In Progress column, visually promoted above other In Progress tasks with a distinct highlight or badge indicating they require human attention
5. <a name="5.5"></a>The Done / Abandoned column SHALL display a visual separator between done and abandoned tasks
6. <a name="5.6"></a>The Done / Abandoned column SHALL only show tasks with a `completionDate` within the last 48 hours based on device-local time
7. <a name="5.7"></a>Abandoned tasks SHALL render at 50% opacity with strikethrough on the task name
8. <a name="5.8"></a>Tasks within each column SHALL be sorted by `lastStatusChangeDate` descending (most recent first)
9. <a name="5.9"></a>Each column header SHALL display the column name and the count of tasks in that column, including tasks with agent handoff statuses nested within that column (per [5.3](#5.3), [5.4](#5.4), [9.4](#9.4))

---

### 6. Dashboard — Task Cards

**User Story:** As a user, I want task cards that show key information at a glance so that I can quickly assess task context without opening details.

**Acceptance Criteria:**

1. <a name="6.1"></a>Each task card SHALL display: project name (secondary text), task name, display ID (right-aligned), and type (as a tinted badge)
2. <a name="6.2"></a>Each task card SHALL have a 1.5pt border tinted with the owning project's assigned color
3. <a name="6.3"></a>Task cards SHALL use `.glassEffect()` materials for their background
4. <a name="6.4"></a>WHEN the user taps a task card, the system SHALL open the detail view for that task

---

### 7. Dashboard — Drag and Drop

**User Story:** As a user, I want to drag tasks between columns to change their status so that I can quickly update task progress.

**Acceptance Criteria:**

1. <a name="7.1"></a>The system SHALL allow the user to drag a task card horizontally between any columns to change its status, including backward transitions (e.g., In Progress to Planning)
2. <a name="7.2"></a>WHEN a task is dragged to the Done / Abandoned column, the system SHALL set its status to Done and record the completion date (per [4.3](#4.3))
3. <a name="7.3"></a>The system SHALL NOT support vertical drag-to-reorder within columns
4. <a name="7.4"></a>The system SHALL NOT allow setting status to Abandoned via drag-and-drop — abandoning is only available via the detail view (per [11.4](#11.4))
5. <a name="7.5"></a>WHEN a Done or Abandoned task is dragged to a non-terminal column, the system SHALL set the new status and clear the `completionDate` (per [4.8](#4.8))

---

### 8. Dashboard — Navigation Bar

**User Story:** As a user, I want quick access to filtering, task creation, and settings from the dashboard.

**Acceptance Criteria:**

1. <a name="8.1"></a>The navigation bar SHALL display the app title "Transit" on the left
2. <a name="8.2"></a>The navigation bar SHALL display filter, add (+), and settings (gear icon) buttons on the right, in that order
3. <a name="8.3"></a>On iOS 26, the filter and add (+) buttons SHALL be grouped in one pill container, and the settings (gear) button SHALL be in a separate pill container (standard toolbar item grouping)

---

### 9. Project Filter

**User Story:** As a user, I want to filter the dashboard by project so that I can focus on specific areas of work.

**Acceptance Criteria:**

1. <a name="9.1"></a>WHEN the user taps the filter button, the system SHALL present a popover listing all projects with checkboxes
2. <a name="9.2"></a>The system SHALL support selecting multiple projects simultaneously (OR logic — show tasks from any selected project)
3. <a name="9.3"></a>WHEN a filter is active, the filter button SHALL display the count of selected projects
4. <a name="9.4"></a>The filter SHALL apply to all columns including task counts in column headers (per [5.9](#5.9)) and the iPhone segmented control
5. <a name="9.5"></a>The popover SHALL include a "Clear" action that resets the filter to show all projects
6. <a name="9.6"></a>Filter state SHALL be ephemeral — it SHALL reset on app launch

---

### 10. Add Task

**User Story:** As a user, I want to quickly create new tasks from the dashboard so that I can capture ideas without friction.

**Acceptance Criteria:**

1. <a name="10.1"></a>WHEN the user taps the add (+) button and at least one project exists, the system SHALL present a task creation sheet
2. <a name="10.2"></a>The creation sheet SHALL include: project picker (dropdown with color dot and name), name (text field, required), description (multiline text field, optional), type (selection from the fixed type list)
3. <a name="10.3"></a>The system SHALL NOT include a status picker on the creation sheet — new tasks always start in Idea (per [4.7](#4.7))
4. <a name="10.4"></a>On iPhone, the creation sheet SHALL present as a bottom sheet with drag handle
5. <a name="10.5"></a>On iPad and Mac, the creation sheet SHALL present as a centered modal
6. <a name="10.6"></a>The system SHALL validate that a task name is provided before allowing creation
7. <a name="10.7"></a>WHEN the user taps the add (+) button and no projects exist, the system SHALL display a message directing the user to create a project first via Settings

---

### 11. Task Detail View

**User Story:** As a user, I want to view and edit task details so that I can update task information and manage task lifecycle.

**Acceptance Criteria:**

1. <a name="11.1"></a>The detail view SHALL display: display ID, name, type (tinted badge), current status, project assignment (with color dot), description, and metadata key-value pairs in a grouped section
2. <a name="11.2"></a>The detail view SHALL include Edit and Abandon buttons
3. <a name="11.3"></a>WHEN the user activates edit mode, the following fields SHALL be editable: name, description, type, project assignment (via dropdown picker), and status (via status picker)
4. <a name="11.4"></a>WHEN the user taps Abandon, the system SHALL set the task status to Abandoned and record the completion date (per [4.4](#4.4))
5. <a name="11.5"></a>WHEN viewing an abandoned task, the system SHALL display a Restore button instead of Abandon (per [4.6](#4.6))
6. <a name="11.6"></a>On iPhone, the detail view SHALL present as a bottom sheet
7. <a name="11.7"></a>On iPad and Mac, the detail view SHALL present as a centered modal
8. <a name="11.8"></a>WHEN the user edits metadata in edit mode, the system SHALL allow adding new key-value pairs, editing existing values, and removing existing pairs
9. <a name="11.9"></a>WHEN status is changed via the status picker, the system SHALL apply the same side effects as any other status change (per [4.2](#4.2), [4.3](#4.3), [4.4](#4.4), [4.8](#4.8))

---

### 12. Settings View

**User Story:** As a user, I want to manage projects and app settings so that I can configure Transit to my needs.

**Acceptance Criteria:**

1. <a name="12.1"></a>WHEN the user taps the settings (gear) button, the system SHALL push a settings view onto the navigation stack
2. <a name="12.2"></a>The settings view SHALL display a chevron-only back button (no label text) to return to the dashboard
3. <a name="12.3"></a>The settings view SHALL include a "Projects" section listing all projects with: color swatch (rounded square with initial), project name, and active task count (where "active" means all tasks not in Done or Abandoned status)
4. <a name="12.4"></a>WHEN the user taps a project row, the system SHALL navigate to a project detail/edit view
5. <a name="12.5"></a>The Projects section SHALL include a "+" button in the section header to create new projects
6. <a name="12.6"></a>The settings view SHALL include a "General" section with: About Transit (version number) and iCloud Sync toggle
7. <a name="12.7"></a>The iCloud Sync toggle SHALL enable or disable CloudKit synchronisation (per [15.4](#15.4))
8. <a name="12.8"></a>The settings view SHALL use a standard iOS grouped list layout
9. <a name="12.9"></a>WHEN re-enabling CloudKit sync after it was disabled, the system SHALL trigger a full sync of local and remote changes

---

### 13. Platform-Adaptive Layout

**User Story:** As a user, I want the dashboard to adapt to my device so that it uses screen space effectively on iPhone, iPad, and Mac.

**Acceptance Criteria:**

1. <a name="13.1"></a>On iPhone in portrait orientation, the system SHALL display a segmented control below the navigation bar showing five status categories with task counts, with one column visible at a time
2. <a name="13.2"></a>The iPhone segmented control SHALL use short labels: Idea, Plan, Spec, Active, Done
3. <a name="13.3"></a>The iPhone default segment on launch SHALL be "Active" (In Progress)
4. <a name="13.4"></a>On iPhone in landscape orientation, the system SHALL display three columns visible at a time with horizontal swipe to reveal additional columns
5. <a name="13.5"></a>The iPhone landscape default columns on launch SHALL be Planning, Spec, In Progress
6. <a name="13.6"></a>On iPad and Mac, the number of visible columns SHALL adapt to the available window width — all five columns when space permits, fewer columns with horizontal scrolling when the window is narrowed
7. <a name="13.7"></a>WHEN the available width is narrow enough to fit only a single column (e.g., iPad Split View at minimum width), the system SHALL fall back to the iPhone portrait layout with a segmented control

---

### 14. Visual Design — Liquid Glass

**User Story:** As a user, I want a modern, native Apple aesthetic so that Transit feels at home on iOS 26.

**Acceptance Criteria:**

1. <a name="14.1"></a>The app SHALL target iOS 26, iPadOS 26, and macOS 26 exclusively with no fallback styling for older OS versions
2. <a name="14.2"></a>Card backgrounds SHALL use `.glassEffect()` / `UIGlassEffect` materials
3. <a name="14.3"></a>Column headers, segmented controls, and popovers SHALL use glass materials
4. <a name="14.4"></a>The app SHALL use SF Pro (system font) throughout: large title weight for screen headers, semibold for column headers, regular for card content
5. <a name="14.5"></a>The app SHALL support both light mode (system grouped background) and dark mode (true black background using `Color.black`)

---

### 15. CloudKit Sync

**User Story:** As a user, I want my tasks and projects to sync seamlessly across all my Apple devices so that I always see current data.

**Acceptance Criteria:**

1. <a name="15.1"></a>The system SHALL store Project and Task records in a CloudKit private database
2. <a name="15.2"></a>The system SHALL sync records automatically via CloudKit push notifications and on app foreground
3. <a name="15.3"></a>The system SHALL use CloudKit's default last-write-wins conflict resolution
4. <a name="15.4"></a>The system SHALL provide a toggle in Settings to enable or disable CloudKit sync (per [12.7](#12.7))
5. <a name="15.5"></a>The system SHALL support creating tasks while offline, assigning provisional local display IDs (per [3.4](#3.4) and [3.5](#3.5))
6. <a name="15.6"></a>WHEN the dashboard is visible and remote changes are received, the system SHALL update the displayed tasks to reflect the current state

---

### 16. App Intent — Create Task

**User Story:** As a CLI user or automation script, I want to create tasks programmatically so that I can integrate Transit into my development workflow.

**Acceptance Criteria:**

1. <a name="16.1"></a>The system SHALL expose a "Transit: Create Task" App Intent accessible via Shortcuts
2. <a name="16.2"></a>The intent SHALL accept JSON input with fields: projectId (UUID, preferred), project (String name, fallback), name (String, required), description (String, optional), type (String, required), metadata (object, optional)
3. <a name="16.3"></a>WHEN both `projectId` and `project` are provided, the system SHALL use `projectId`
4. <a name="16.4"></a>WHEN only `project` (name) is provided and multiple projects match, the system SHALL return an `AMBIGUOUS_PROJECT` error
5. <a name="16.5"></a>The intent SHALL always create tasks in Idea status and return JSON output with fields: taskId (UUID), displayId (Integer), status ("idea")
6. <a name="16.6"></a>WHEN a required field is missing or input JSON is malformed, the intent SHALL return an `INVALID_INPUT` error with a hint describing the expected format
7. <a name="16.7"></a>WHEN the project cannot be found, the intent SHALL return a `PROJECT_NOT_FOUND` error
8. <a name="16.8"></a>WHEN the type value is not recognised, the intent SHALL return an `INVALID_TYPE` error

---

### 17. App Intent — Update Task Status

**User Story:** As a CLI user or automation script, I want to update task status programmatically so that agents and CI pipelines can advance tasks through the workflow.

**Acceptance Criteria:**

1. <a name="17.1"></a>The system SHALL expose a "Transit: Update Status" App Intent accessible via Shortcuts
2. <a name="17.2"></a>The intent SHALL accept JSON input with fields: task object containing displayId (Integer — the numeric value, not the "T-" prefixed string), status (String)
3. <a name="17.3"></a>Valid status values SHALL be: idea, planning, spec, ready-for-implementation, in-progress, ready-for-review, done, abandoned
4. <a name="17.4"></a>The intent SHALL return JSON output with fields: displayId (Integer), previousStatus (String), status (String)
5. <a name="17.5"></a>WHEN the task cannot be found, the intent SHALL return a `TASK_NOT_FOUND` error with a hint containing the provided displayId
6. <a name="17.6"></a>WHEN the status value is not recognised, the intent SHALL return an `INVALID_STATUS` error

---

### 18. App Intent — Query Tasks

**User Story:** As a CLI user or automation script, I want to query tasks by filter criteria so that I can retrieve task status programmatically.

**Acceptance Criteria:**

1. <a name="18.1"></a>The system SHALL expose a "Transit: Query Tasks" App Intent accessible via Shortcuts
2. <a name="18.2"></a>The intent SHALL accept JSON input with optional filter fields: status (String), projectId (UUID), type (String)
3. <a name="18.3"></a>WHEN no filters are provided, the intent SHALL return all tasks
4. <a name="18.4"></a>The intent SHALL return a JSON array of task objects, each containing: taskId, displayId, name, status, type, projectId, projectName, completionDate, lastStatusChangeDate
5. <a name="18.5"></a>WHEN the project cannot be found, the intent SHALL return a `PROJECT_NOT_FOUND` error

---

### 19. App Intent — Error Handling

**User Story:** As a CLI user or automation script, I want consistent, structured error responses so that I can handle failures programmatically.

**Acceptance Criteria:**

1. <a name="19.1"></a>All intent error responses SHALL use the structure: `{"error": "<CODE>", "hint": "<message>"}`
2. <a name="19.2"></a>The system SHALL support the following error codes: TASK_NOT_FOUND, PROJECT_NOT_FOUND, AMBIGUOUS_PROJECT, INVALID_STATUS, INVALID_TYPE, INVALID_INPUT
3. <a name="19.3"></a>Error hints SHALL include the failing input value and a description of the expected input format

---

### 20. Empty States

**User Story:** As a new user, I want clear guidance when the app has no data so that I know how to get started.

**Acceptance Criteria:**

1. <a name="20.1"></a>WHEN the dashboard has no tasks across all columns, the system SHALL display an empty state message indicating no tasks exist
2. <a name="20.2"></a>WHEN a single column has no tasks, the column SHALL display an empty state message (e.g., "No tasks in Planning")
3. <a name="20.3"></a>WHEN no projects exist and the user taps the add (+) button, the system SHALL display a message directing the user to create a project first via Settings (per [10.7](#10.7))
4. <a name="20.4"></a>WHEN no projects exist, the Settings view Projects section SHALL display a prompt encouraging the user to create their first project
