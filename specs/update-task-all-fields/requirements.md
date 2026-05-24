# Requirements: Extend update_task to Support All Task Fields (T-650)

## Introduction

The `update_task` MCP tool and the `UpdateTaskIntent` App Intent currently only support updating a task's milestone assignment. Agents and CLI callers cannot rename a task, edit its description, change its type, or update its metadata without opening the app UI. This spec extends both surfaces to update every mutable task field in a single atomic call, while preserving the existing milestone behavior.

## Non-Goals

- Updating task status (already covered by `update_task_status`)
- Changing a task's project (deferred; cross-project moves have downstream display/milestone implications)
- Per-key metadata patching (full replacement only — see Decision 2)
- Updating multiple tasks in one call (batch updates)
- Visual `EditTaskIntent` (Shortcuts-friendly edit flow) — deferred to a separate ticket; this spec only updates the JSON-based `UpdateTaskIntent` and its MCP counterpart
- Tracking edit history or a "last modified" timestamp on tasks (the model has no such field)
- Renaming display IDs or task UUIDs
- Special handling for terminal-state tasks (Done / Abandoned) — they remain editable like any other task
- Enforcing length limits on `name`, `description`, or `metadata` keys/values — the underlying CloudKit constraints (~1 MB row) are surfaced as save errors

## Requirements

### 1. Name Update

**User Story:** As an agent, I want to rename a task via `update_task`, so that I can keep task names accurate as work evolves without opening the app.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN the request includes a `name` field of type string with a non-empty value after trimming leading/trailing whitespace, the system SHALL set the task's name to the trimmed value and persist the change.
2. <a name="1.2"></a>WHEN the request includes a `name` field of type string that is empty or contains only whitespace, the system SHALL return an error `"Task name cannot be empty"` and SHALL NOT modify any task field.
3. <a name="1.3"></a>WHEN the request includes a `name` field that is not a string (number, boolean, null, array, object), the system SHALL return an error `"name must be a string"` and SHALL NOT modify any task field.
4. <a name="1.4"></a>WHEN the request omits the `name` field, the system SHALL leave the task's name unchanged.

### 2. Description Update

**User Story:** As an agent, I want to edit or clear a task's description, so that I can keep notes and context current.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN the request includes a `description` field of type string with a non-empty value after trimming leading/trailing whitespace, the system SHALL set the task's description to the trimmed value and persist the change.
2. <a name="2.2"></a>WHEN the request includes a `description` field of type string that is empty or contains only whitespace, the system SHALL clear the task's stored description (set to nil) so that a subsequent fetch of the task returns no description value.
3. <a name="2.3"></a>WHEN the request includes a `description` field that is not a string (number, boolean, null, array, object), the system SHALL return an error `"description must be a string"` and SHALL NOT modify any task field.
4. <a name="2.4"></a>WHEN the request omits the `description` field, the system SHALL leave the task's description unchanged.

### 3. Type Update

**User Story:** As an agent, I want to reclassify a task's type, so that I can correct misclassifications (e.g., reclassify a bug as a chore).

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN the request includes a `type` field of type string whose value matches one of `bug`, `feature`, `chore`, `research`, `documentation` (exact lowercase match, no canonicalization), the system SHALL set the task's type to that value and persist the change.
2. <a name="3.2"></a>WHEN the request includes a `type` field of type string whose value does not match any valid `TaskType`, the system SHALL return an error of the form `"Invalid type: {value}. Must be one of: bug, feature, chore, research, documentation"` and SHALL NOT modify any task field.
3. <a name="3.3"></a>WHEN the request includes a `type` field that is not a string, the system SHALL return an error `"type must be a string"` and SHALL NOT modify any task field.
4. <a name="3.4"></a>WHEN the request omits the `type` field, the system SHALL leave the task's type unchanged.

### 4. Metadata Update (Full Replacement)

**User Story:** As an agent, I want to overwrite a task's metadata dictionary in one call, so that I can sync agent-side state to the task without read-modify-write per key.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN the request includes a `metadata` field of type object whose entries all have string values, the system SHALL replace the task's entire metadata dictionary with the provided entries and persist the change.
2. <a name="4.2"></a>WHEN the request includes a `metadata` field of type object that is empty (`{}`), the system SHALL clear the task's stored metadata so that a subsequent fetch returns no metadata.
3. <a name="4.3"></a>WHEN the request includes a `metadata` field that is not a JSON object (string, number, boolean, null, array), the system SHALL return an error `"metadata must be an object with string values"` and SHALL NOT modify any task field.
4. <a name="4.4"></a>WHEN the request includes a `metadata` object whose values contain any non-string entry (number, boolean, null, nested object, array), the system SHALL return an error `"metadata values must be strings"` and SHALL NOT modify any task field. This requires strict validation; the existing `IntentHelpers.stringMetadata` helper silently drops non-string values and SHALL NOT be reused for this enforcement.
5. <a name="4.5"></a>WHEN the request omits the `metadata` field, the system SHALL leave the task's metadata unchanged.

### 5. Atomic Multi-Field Updates

**User Story:** As an agent, I want multiple field updates in a single call to be all-or-nothing, so that a malformed value cannot leave the task in a partially updated state.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN the request includes multiple valid update fields (any combination of `name`, `description`, `type`, `metadata`, plus existing milestone fields), the system SHALL apply all changes and SHALL persist them in a single save operation.
2. <a name="5.2"></a>IF any one provided update field fails validation, THEN the system SHALL return an error describing one validation failure and SHALL leave every task field unchanged. The choice of which failure to surface when multiple fields are invalid is unspecified — callers SHALL NOT depend on a particular ordering, and the MCP tool and App Intent MAY surface different error messages for the same multi-field-invalid input (parity per [8.1](#8.1) covers successful response shape, not error-message text).
3. <a name="5.3"></a>IF the underlying save operation fails after validation succeeds (including CloudKit-size or other persistence-layer errors), THEN the system SHALL invoke `ModelContext.safeRollback()` to revert any in-memory mutations and SHALL return an error describing the save failure. All save-time failures route through this single path; there is no separate error code for size-limit failures.

### 6. Identifier-Only No-Op

**User Story:** As an agent, I want to call `update_task` with only an identifier and no update fields, so that I can echo current task state for validation without spurious writes.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN the request includes only a task identifier (`displayId` or `taskId`) and no field that semantically mutates the task — meaning the request omits `name`, `description`, `type`, `metadata`, `milestone`, `milestoneDisplayId`, and `clearMilestone` — the system SHALL resolve the task, SHALL NOT invoke a save operation, and SHALL return the current task JSON.
2. <a name="6.2"></a>An explicit clear request (`description: ""`, `description: "   "`, `metadata: {}`, `clearMilestone: true`) IS a mutation and SHALL trigger save, even when no other update fields are present.
3. <a name="6.3"></a>Unknown JSON fields not defined by this tool's schema SHALL be silently ignored. The presence of unknown fields SHALL NOT tip a request from the no-op path in [6.1](#6.1) to the save path; conversely, the presence of a known mutating field SHALL always trigger save, regardless of any unknown fields alongside it.

### 7. Backward Compatibility with Milestone Fields

**User Story:** As an agent already using `update_task` for milestone assignment, I want existing milestone behavior to keep working, so that my current scripts and prompts do not break.

**Acceptance Criteria:**

1. <a name="7.1"></a>The system SHALL continue to accept `milestone`, `milestoneDisplayId`, and `clearMilestone` with the same semantics as before this change.
2. <a name="7.2"></a>WHEN the request combines milestone fields with name, description, type, or metadata updates, the system SHALL validate every field before applying any change and SHALL persist the combined result in a single save.

### 8. Parity Between MCP Tool and App Intent

**User Story:** As a user invoking the feature via either Claude Code (MCP) or Apple Shortcuts (App Intent), I want both surfaces to accept the same input shape and apply the same rules, so that I can switch between them without surprise.

**Acceptance Criteria:**

1. <a name="8.1"></a>The MCP `update_task` tool and the `UpdateTaskIntent` App Intent SHALL accept the same JSON input shape, apply the same validation rules, and return responses carrying the same field values and the same field-omission semantics (representation format may differ — JSON string vs `IntentResult` — but the data SHALL be equivalent).
2. <a name="8.2"></a>The MCP tool definition (`tools/list`) input schema SHALL describe every supported input field (`name`, `description`, `type`, `metadata`, plus existing milestone and identifier fields), and the prose description for each field SHALL document non-obvious behavior — including that `description: ""` clears the description and `metadata: {}` clears all metadata. The `UpdateTaskIntent` `Input` parameter's `description` SHALL contain the same field documentation.

### 9. Response Shape

**User Story:** As a caller, I want the post-update response to reflect the updated task fully, so that I do not need a follow-up `query_tasks` call to confirm the change.

**Acceptance Criteria:**

1. <a name="9.1"></a>The response JSON SHALL use the detailed task shape, computed purely from the task's post-update model state (not from which fields the request touched). It SHALL include `taskId`, `name`, `type`, `status`, `displayId` (when allocated), `projectId`, `projectName`, `description` (when non-nil and non-empty), `metadata` (when non-empty), and `milestone` summary (when assigned). Fields whose post-update value is empty/nil SHALL be omitted from the response — they SHALL NOT appear as `""`, `null`, or `{}`. The response SHALL NOT include `comments`, `creationDate`, `lastStatusChangeDate`, or `completionDate`.
