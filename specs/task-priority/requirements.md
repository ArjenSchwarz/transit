# Requirements: Task Priority (T-1463)

## Introduction

Transit tasks currently have no way to express relative importance, so there is nothing on the board that signals what to focus on now versus what can wait. This feature adds a single `priority` field to every task with three values — low, medium, high — defaulting to medium. Priority is shown on board cards as a glyph (for non-default priorities), is filterable on the board, is shown on the task detail view, is editable in the app's create/edit screens, and is readable, settable, and filterable through the MCP server and App Intents.

## Value Format

Across the model, MCP, and App Intents, a priority value is one of the exact lowercase strings `low`, `medium`, or `high`. Matching is exact and case-sensitive (no trimming or case-folding), consistent with the existing task `type` handling.

## Non-Goals

- No priority levels beyond low / medium / high (no "urgent", "none", or numeric scale).
- Priority does not change task ordering or sorting on the board — filtering is the intended focus mechanism.
- No priority glyph on the board card for medium-priority tasks (the default majority); only low and high are marked.
- No priority-driven notifications, reminders, or escalation.
- No per-project or per-type default priority configuration; the default is always medium.
- No bulk / multi-select priority editing on the board.
- No history or audit trail of priority changes.
- No data migration or write-backfill pass for existing tasks; they read as medium via the model default and computed fallback (see Requirement 1, which makes this an explicit, testable behavior rather than an omission).
- Priority is not shown in generated reports of completed/abandoned tasks.
- The new field does not read, migrate, or relate to any informal `priority=` convention previously placed in a task's description or freeform metadata; the freeform metadata field is not a priority source of truth.

## Requirements

### 1. Priority on the task model (including existing tasks)

**User Story:** As a user, I want every task — including ones created before this feature — to carry a priority of low, medium, or high, so that I can distinguish what to focus on.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL associate every task with exactly one priority value from the set {low, medium, high}.  
2. <a name="1.2"></a>WHEN a task is created without an explicit priority, the system SHALL assign it medium priority.  
3. <a name="1.3"></a>The system SHALL treat any existing task that has no stored priority value as medium priority, WITHOUT performing a data migration or write to those tasks.  
4. <a name="1.4"></a>All priority reads — board display, detail view, filtering, and MCP/intent serialization — SHALL use the task's effective priority (medium when unset), so that filtering for medium includes tasks that have no stored priority value.  
5. <a name="1.5"></a>The system SHALL persist a task's priority so that it syncs across the user's devices.  

### 2. Priority glyph on the board card

**User Story:** As a user, I want each board card to show its priority as a glyph, so that I can see at a glance what to focus on.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN a task is high or low priority, the board card SHALL display a priority glyph that distinguishes the two levels by both symbol shape and color (not color alone).  
2. <a name="2.2"></a>WHEN a task is medium priority, the board card SHALL NOT display a priority glyph.  
3. <a name="2.3"></a>The priority glyph SHALL update to reflect the task's current priority whenever it changes, including appearing or disappearing as the priority crosses to or from medium.  
4. <a name="2.4"></a>The priority glyph SHALL expose a VoiceOver accessibility label naming the priority level (e.g. "High priority") and a stable accessibility identifier, consistent with existing card elements.  

### 3. Priority filter on the board

**User Story:** As a user, I want to filter the board by priority, so that I can narrow the board to the tasks that matter now.

**Acceptance Criteria:**

1. <a name="3.1"></a>The board's existing filter affordance SHALL offer a priority filter with low, medium, and high options.  
2. <a name="3.2"></a>WHEN one or more priorities are selected, the board SHALL display only tasks whose priority is among the selected values.  
3. <a name="3.3"></a>WHEN no priority is selected, the board SHALL display tasks of all priorities.  
4. <a name="3.4"></a>The priority filter SHALL combine with the existing project and type filters by intersection (a task must match every active filter dimension).  
5. <a name="3.5"></a>The priority filter selection SHALL be ephemeral, resetting on app launch, consistent with the existing filters.  
6. <a name="3.6"></a>The priority filter SHALL match the interaction pattern of the existing board type filter (multi-select toggle within the filter popover).  
7. <a name="3.7"></a>The priority filter control SHALL expose accessibility identifiers consistent with the existing filter controls so it is reachable in UI tests and by VoiceOver.  

### 4. In-app priority display and editing

**User Story:** As a user, I want to see and set a task's priority inside the app, so that I can manage focus without external tools.

**Acceptance Criteria:**

1. <a name="4.1"></a>The task creation screen SHALL provide a priority control defaulting to medium.  
2. <a name="4.2"></a>The task edit screen SHALL provide a priority control pre-set to the task's current priority and allowing selection of any of the three values.  
3. <a name="4.3"></a>WHEN the user changes priority on the edit screen and saves, the system SHALL persist the new priority.  
4. <a name="4.4"></a>The task detail screen SHALL display the task's current priority for all three levels (including medium).  

### 5. MCP server support

**User Story:** As an agent, I want to read, set, and filter by task priority through the MCP server, so that automation can manage focus.

**Acceptance Criteria:**

1. <a name="5.1"></a>The `create_task` tool SHALL accept an optional priority value and SHALL default to medium when it is omitted.  
2. <a name="5.2"></a>The `update_task` tool SHALL accept a priority value and apply it to the identified task; WHEN priority is omitted the task's priority SHALL be left unchanged, and priority SHALL NOT be clearable to an empty value.  
3. <a name="5.3"></a>The `query_tasks` tool SHALL include each task's priority in its result; this addition SHALL be backward compatible so existing clients can ignore the field.  
4. <a name="5.4"></a>The `query_tasks` tool SHALL support filtering by one or more priority values (multi-value, matching the existing `status` filter); WHEN no priority filter is supplied, results SHALL include all priorities.  
5. <a name="5.5"></a>WHEN an MCP tool receives a priority value outside {low, medium, high}, the system SHALL return a validation error and SHALL NOT create or modify any task.  

### 6. App Intents support

**User Story:** As a Shortcuts/CLI user, I want priority available in the task intents, so that automation through Shortcuts matches the MCP capability.

**Acceptance Criteria:**

1. <a name="6.1"></a>The create-task intent SHALL accept an optional priority value and SHALL default to medium when it is omitted.  
2. <a name="6.2"></a>The update-task intent SHALL accept a priority value and apply it; WHEN priority is omitted the task's priority SHALL be left unchanged, and priority SHALL NOT be clearable to an empty value.  
3. <a name="6.3"></a>The query-tasks intent SHALL include priority in returned task data and SHALL support filtering by a single priority value, matching the intent's existing single-value `status` and `type` filters. (Multi-value priority filtering is provided by the MCP `query_tasks` tool, AC 5.4.)  
4. <a name="6.4"></a>WHEN a task intent receives a priority value outside {low, medium, high}, the system SHALL return a JSON-encoded validation error consistent with the existing invalid-type handling, and SHALL NOT create or modify any task.  
