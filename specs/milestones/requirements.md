# Requirements: Milestones

## Introduction

Milestones group tasks within a project under a named release or goal (e.g. "v1.0", "Beta"). They provide a way to scope the dashboard, track progress toward a release, and give agents context about what work belongs together. Milestones are project-scoped, have their own display IDs (M-1, M-2), and follow a simple open/done/abandoned lifecycle.

This feature adds milestones to the data model, services, UI, MCP tools, App Intents, and reports.

---

### 1. Milestone Data Model

**User Story:** As a user, I want to create milestones within a project so that I can group related tasks under a release or goal.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL store Milestone records with the following fields: id (UUID), permanentDisplayId (Integer, optional), name (String, required), description (String, optional), statusRawValue (String), creationDate (Date), lastStatusChangeDate (Date), completionDate (Date, optional)
2. <a name="1.2"></a>The system SHALL use the Milestone's UUID as the CloudKit record identifier
3. <a name="1.3"></a>Each Milestone SHALL belong to exactly one Project (optional relationship for CloudKit compatibility)
4. <a name="1.4"></a>Milestone names SHALL be unique within a project (case-insensitive, enforced in the service layer)
5. <a name="1.5"></a>The system SHALL format milestone display IDs as "M-{number}" (e.g., M-1, M-12) in all UI surfaces
6. <a name="1.6"></a>Provisional milestone display IDs SHALL render as "M-•" with a secondary/dimmed text style

---

### 2. Milestone Display ID Allocation

**User Story:** As a user, I want human-readable milestone IDs (e.g., M-3) so that I can reference milestones in conversation and CLI commands.

**Acceptance Criteria:**

1. <a name="2.1"></a>The system SHALL allocate milestone display IDs from a separate counter record in CloudKit, independent of the task counter
2. <a name="2.2"></a>Milestone display IDs SHALL be sequential integers, globally scoped across all projects
3. <a name="2.3"></a>The system SHALL reuse the existing `DisplayIDAllocator` mechanism with a distinct counter record type for milestones
4. <a name="2.4"></a>WHEN a milestone is created offline, the system SHALL assign a provisional local ID
5. <a name="2.5"></a>WHEN an offline-created milestone syncs, the system SHALL replace the provisional ID with a permanent display ID

---

### 3. Milestone Status Lifecycle

**User Story:** As a user, I want to mark milestones as done or abandoned so that I can track which releases are complete.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL support three milestone statuses: Open, Done, Abandoned
2. <a name="3.2"></a>New milestones SHALL always start in Open status
3. <a name="3.3"></a>WHEN a milestone's status changes, the system SHALL update `lastStatusChangeDate`
4. <a name="3.4"></a>WHEN a milestone's status changes to Done or Abandoned, the system SHALL set `completionDate`
5. <a name="3.5"></a>WHEN a Done or Abandoned milestone is reopened (set to Open), the system SHALL clear `completionDate`
6. <a name="3.6"></a>Changing a milestone's status SHALL NOT affect the status of its assigned tasks

---

### 4. Task–Milestone Assignment

**User Story:** As a user, I want to assign tasks to a milestone so that I can see which work belongs to a release.

**Acceptance Criteria:**

1. <a name="4.1"></a>Each Task SHALL optionally belong to at most one Milestone
2. <a name="4.2"></a>The Task–Milestone relationship SHALL use `.nullify` delete rule (deleting a milestone removes the association, not the tasks)
3. <a name="4.3"></a>A Task's milestone SHALL belong to the same project as the task
4. <a name="4.4"></a>WHEN a task's project changes, the system SHALL clear its milestone assignment
5. <a name="4.5"></a>Tasks without a project SHALL NOT be assignable to a milestone

---

### 5. Dashboard — Milestone Filter

**User Story:** As a user, I want to filter the dashboard by milestone so that I can focus on work for a specific release.

**Acceptance Criteria:**

1. <a name="5.1"></a>The filter popover SHALL include a milestone filter section
2. <a name="5.2"></a>The milestone filter SHALL show milestones from the currently selected project filter, or all open milestones if no project is filtered
3. <a name="5.3"></a>WHEN a milestone filter is active, the dashboard SHALL only show tasks assigned to the selected milestone(s)
4. <a name="5.4"></a>The milestone filter state SHALL be ephemeral (resets on launch)
5. <a name="5.5"></a>WHEN the project filter changes, the milestone filter SHALL reset

---

### 6. Task Card — Milestone Badge

**User Story:** As a user, I want to see which milestone a task belongs to at a glance on the kanban board.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN a task is assigned to a milestone, the task card SHALL display the milestone name as a badge
2. <a name="6.2"></a>The milestone badge SHALL be visually distinct from the type badge (secondary style, smaller)

---

### 7. Task Detail & Edit — Milestone

**User Story:** As a user, I want to view and change a task's milestone assignment from the task detail view.

**Acceptance Criteria:**

1. <a name="7.1"></a>The task detail view SHALL display the assigned milestone name and display ID, or "None" if unassigned
2. <a name="7.2"></a>The task edit view SHALL include a milestone picker showing open milestones from the task's project
3. <a name="7.3"></a>The milestone picker SHALL include a "None" option to unassign the task from its milestone
4. <a name="7.4"></a>WHEN the task's project is changed in the edit view, the milestone picker SHALL reset to "None"

---

### 8. Add Task — Milestone

**User Story:** As a user, I want to optionally assign a milestone when creating a task.

**Acceptance Criteria:**

1. <a name="8.1"></a>The add task sheet SHALL include an optional milestone picker
2. <a name="8.2"></a>The milestone picker SHALL show open milestones for the selected project
3. <a name="8.3"></a>WHEN the project selection changes in the add task sheet, the milestone picker SHALL reset

---

### 9. Settings — Milestone Management

**User Story:** As a user, I want to create, edit, and manage milestones from the settings area.

**Acceptance Criteria:**

1. <a name="9.1"></a>The settings view SHALL include a milestone management section within each project's detail or as a navigable list
2. <a name="9.2"></a>The user SHALL be able to create a new milestone by providing a name and optional description
3. <a name="9.3"></a>The user SHALL be able to edit a milestone's name and description
4. <a name="9.4"></a>The user SHALL be able to change a milestone's status (Open, Done, Abandoned)
5. <a name="9.5"></a>The user SHALL be able to delete a milestone (tasks lose their association per [4.2](#4.2))

---

### 10. Reports — Milestone Inclusion

**User Story:** As a user, I want reports to show milestone information so that I can see progress per release.

**Acceptance Criteria:**

1. <a name="10.1"></a>Report task rows SHALL include the milestone name when the task is assigned to one
2. <a name="10.2"></a>The report markdown output SHALL include milestone names in task lines
3. <a name="10.3"></a>WHEN milestones were completed (Done or Abandoned) within the report's date range, the report SHALL list them at the top of their project's section, before task rows
4. <a name="10.4"></a>Completed milestone entries SHALL show the milestone display ID, name, status (Done or Abandoned), and count of assigned tasks

---

### 11. Share Text — Milestone Inclusion

**User Story:** As a user, I want shared task text to include milestone information.

**Acceptance Criteria:**

1. <a name="11.1"></a>WHEN a task is assigned to a milestone, the share text SHALL include "Milestone: {name} ({display ID})"

---

### 12. MCP Tools — Milestone Support

**User Story:** As an agent, I want MCP tools to create, query, and manage milestones so that I can organise work programmatically.

**Acceptance Criteria:**

1. <a name="12.1"></a>The MCP server SHALL expose a `create_milestone` tool accepting: name (required), project (by name or ID, required), description (optional)
2. <a name="12.2"></a>The MCP server SHALL expose a `query_milestones` tool accepting: project (optional filter), status (optional filter), search (optional text search)
3. <a name="12.3"></a>The MCP server SHALL expose an `update_milestone` tool accepting: milestone identifier (displayId or UUID), and optional fields: name, description, status
4. <a name="12.4"></a>The MCP server SHALL expose a `delete_milestone` tool accepting: milestone identifier (displayId or UUID). SHALL return the count of affected tasks.
5. <a name="12.5"></a>The MCP server SHALL expose an `update_task` tool accepting: task identifier (displayId or UUID), and optional milestone assignment (by name, display ID, or clear)
6. <a name="12.6"></a>The `create_task` tool SHALL accept an optional `milestone` parameter (by name or display ID) to assign at creation
7. <a name="12.7"></a>The `query_tasks` tool SHALL accept an optional `milestone` parameter to filter tasks by milestone
8. <a name="12.8"></a>Task objects returned by MCP tools SHALL include milestone information (UUID, name, and display ID) when assigned
9. <a name="12.9"></a>The `get_projects` response SHALL include milestones for each project

---

### 13. App Intents — Milestone Support

**User Story:** As a user, I want Shortcuts/CLI commands for milestone management.

**Acceptance Criteria:**

1. <a name="13.1"></a>The system SHALL provide a `Transit: Create Milestone` intent accepting JSON with: name (required), project (required), description (optional)
2. <a name="13.2"></a>The system SHALL provide a `Transit: Query Milestones` intent accepting JSON with optional project, status, and search filters
3. <a name="13.3"></a>The system SHALL provide a `Transit: Update Milestone` intent accepting JSON with: milestone identifier (displayId, UUID, or name+project), and optional name, description, status fields
4. <a name="13.4"></a>The system SHALL provide a `Transit: Delete Milestone` intent accepting JSON with: milestone identifier (displayId or UUID). SHALL return the count of affected tasks.
5. <a name="13.5"></a>The system SHALL provide a `Transit: Update Task` intent accepting JSON with: task identifier (displayId or UUID), and optional milestone assignment
6. <a name="13.6"></a>The `Transit: Create Task` intent SHALL accept an optional `milestone` parameter
7. <a name="13.7"></a>The `Transit: Query Tasks` intent SHALL accept an optional `milestone` filter parameter
8. <a name="13.8"></a>Milestone operations SHALL use the same JSON input/output pattern and error codes as existing intents
9. <a name="13.9"></a>Error codes SHALL include: `MILESTONE_NOT_FOUND`, `DUPLICATE_MILESTONE_NAME`, `MILESTONE_PROJECT_MISMATCH`
