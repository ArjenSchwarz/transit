# Requirements: Add Comments (T-46)

## Introduction

Transit tasks currently have no mechanism for recording notes, progress updates, or agent activity. This feature adds a Comment entity to tasks, enabling both users and agents to leave timestamped, attributed comments. Comments serve as a lightweight activity log — append-only, not a conversation thread.

The feature spans the data model (new SwiftData entity), the UI (inline comments section in the task detail view, comment count on dashboard cards), a user-facing App Intent / Shortcut for adding comments, and a new "Your Name" setting for author attribution.

JSON-based App Intents for agent use are out of scope for this spec. Agent integration is provided via the MCP server (Hummingbird on localhost:3141).

---

## Requirements

### 1. Comment Data Model

**User Story:** As a developer, I want a structured Comment entity in the data model, so that comments are persisted, synced via CloudKit, and queryable.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL store comments as a `Comment` SwiftData entity with fields: `id` (UUID), `content` (String), `authorName` (String), `isAgent` (Bool), `creationDate` (Date), and an optional relationship to `TransitTask`
2. <a name="1.2"></a>The `TransitTask` entity SHALL have an optional to-many relationship to `Comment` with a `.cascade` delete rule, so that deleting a task removes all its comments
3. <a name="1.3"></a>The `Comment` relationship on `TransitTask` SHALL be optional to comply with CloudKit compatibility constraints
4. <a name="1.4"></a>The system SHALL include `Comment.self` in the SwiftData schema for both the app and test containers
5. <a name="1.5"></a>Comments SHALL sync across devices via CloudKit when sync is enabled, using the same mechanism as tasks and projects

### 2. User Display Name Setting

**User Story:** As a user, I want to set my display name in the app settings, so that my comments are attributed to me by name.

**Acceptance Criteria:**

1. <a name="2.1"></a>The Settings view SHALL include a "Your Name" text field in the General section on both iOS and macOS
2. <a name="2.2"></a>The display name SHALL be stored via `@AppStorage("userDisplayName")` and persist across app launches
3. <a name="2.3"></a>WHEN a user attempts to add a comment via the UI AND the display name setting is empty or whitespace-only, THEN the system SHALL prevent comment creation and display an actionable message directing the user to Settings to set their name
4. <a name="2.4"></a>The display name setting SHALL default to an empty string (no pre-populated value)

### 3. Adding Comments via UI

**User Story:** As a user, I want to add comments to a task from the task detail view, so that I can record notes and progress updates.

**Acceptance Criteria:**

1. <a name="3.1"></a>The TaskEditView SHALL display a "Comments" section below the existing task fields
2. <a name="3.2"></a>The comments section SHALL show all comments for the task in chronological order (oldest first, newest at bottom), with the comment's UUID as a secondary sort key for deterministic ordering
3. <a name="3.3"></a>Each comment SHALL display the author name, a relative timestamp, and the comment content
4. <a name="3.4"></a>The comments section SHALL include a text input area with a send button at the bottom
5. <a name="3.5"></a>WHEN the user taps the send button AND the input (after trimming whitespace) is non-empty AND the display name (after trimming whitespace) is set, THEN a new comment SHALL be created with the user's display name as the author and `isAgent` set to `false`
6. <a name="3.6"></a>WHEN a comment is successfully added, THEN the input field SHALL be cleared
7. <a name="3.7"></a>Comments SHALL be append-only — there is no edit capability
8. <a name="3.8"></a>The comment content field SHALL have no character limit
9. <a name="3.9"></a>WHEN no comments exist for a task, THEN the section SHALL display an empty state message (e.g. "No comments yet")

### 4. Agent Comment Distinction

**User Story:** As a user, I want to visually distinguish agent-authored comments from my own, so that I can quickly see which comments came from automated tools.

**Acceptance Criteria:**

1. <a name="4.1"></a>The system SHALL determine whether a comment is agent-authored by checking the `isAgent` field on the Comment entity
2. <a name="4.2"></a>Agent comments SHALL be displayed with a subtle visual distinction: a light purple background tint and an "Agent" badge next to the author name
3. <a name="4.3"></a>User comments SHALL display a circular avatar with the first letter of the author name; agent comments SHALL display a robot icon avatar
4. <a name="4.4"></a>The visual distinction SHALL be subtle and non-disruptive — both comment types use the same layout and sizing

### 5. Deleting Comments

**User Story:** As a user, I want to delete individual comments, so that I can remove outdated or incorrect information.

**Acceptance Criteria:**

1. <a name="5.1"></a>On iOS, the user SHALL be able to delete a comment by swiping left on the comment row
2. <a name="5.2"></a>On macOS, the user SHALL be able to delete a comment via a delete button that appears on hover
3. <a name="5.3"></a>WHEN a comment is deleted, THEN it SHALL be permanently removed from the data store
4. <a name="5.4"></a>There SHALL be no bulk "delete all comments" action — only individual deletion

### 6. Comment Count on Dashboard Cards

**User Story:** As a user, I want to see a comment count on task cards in the kanban dashboard, so that I can tell at a glance which tasks have activity.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN a task has one or more comments, THEN its card on the kanban dashboard SHALL display a comment icon with the count (e.g. a speech bubble icon followed by the number)
2. <a name="6.2"></a>WHEN a task has zero comments, THEN no comment indicator SHALL be shown on the card
3. <a name="6.3"></a>The comment count SHALL update when comments are added or deleted

### 7. App Intent: Add Comment (User-Facing)

**User Story:** As a user, I want a Shortcut for adding comments to tasks, so that I can quickly add notes without opening the full app.

**Acceptance Criteria:**

1. <a name="7.1"></a>The system SHALL provide a `Transit: Add Comment` App Intent with typed parameters: task identifier (String — accepts display ID like "42" or UUID), comment text (String), and author name (String)
2. <a name="7.2"></a>The intent SHALL be registered as a user-facing Shortcut, discoverable in the Shortcuts app and Spotlight
3. <a name="7.3"></a>WHEN the intent is executed with valid input, THEN a comment SHALL be created on the specified task with `isAgent` set to `true`
4. <a name="7.4"></a>WHEN the specified task is not found, THEN the intent SHALL throw an appropriate error
5. <a name="7.5"></a>The intent SHALL validate that comment text and author name are non-empty after trimming whitespace

### 8. MCP Tool: Add Comment

**User Story:** As an agent, I want an MCP tool for adding comments to tasks, so that I can record activity on tasks programmatically.

**Acceptance Criteria:**

1. <a name="8.1"></a>The MCP server SHALL expose a new `add_comment` tool
2. <a name="8.2"></a>The tool SHALL accept parameters: task identifier (`displayId` as Int or `taskId` as UUID string), `content` (String), and `authorName` (String)
3. <a name="8.3"></a>WHEN the tool is called with valid input, THEN a comment SHALL be created on the specified task with `isAgent` set to `true` and the tool SHALL return the comment details (id, authorName, content, creationDate)
4. <a name="8.4"></a>WHEN the specified task is not found, THEN the tool SHALL return an error with code `TASK_NOT_FOUND`
5. <a name="8.5"></a>The tool SHALL validate that `content` and `authorName` are non-empty after trimming whitespace, returning an `INVALID_INPUT` error otherwise
6. <a name="8.6"></a>The tool SHALL follow the existing MCP tool patterns in `MCPToolHandler.swift` for parameter parsing, error handling, and response encoding

### 9. MCP Tool: Comment on Status Update

**User Story:** As an agent, I want to optionally include a comment when updating a task's status via MCP, so that I can record why the status changed in a single call.

**Acceptance Criteria:**

1. <a name="9.1"></a>The `update_task_status` MCP tool SHALL accept optional `comment` and `authorName` fields in its parameters
2. <a name="9.2"></a>WHEN a `comment` field is present AND non-empty, THEN the tool SHALL create a comment on the task (with `isAgent` set to `true`) in addition to updating the status
3. <a name="9.3"></a>WHEN a `comment` field is present, THEN an `authorName` field SHALL also be required
4. <a name="9.4"></a>The status update and comment creation SHALL be atomic — both mutations SHALL be saved in the same `ModelContext.save()` call
5. <a name="9.5"></a>WHEN a `comment` field is absent or empty, THEN the tool SHALL behave identically to its current implementation
6. <a name="9.6"></a>The response SHALL include the comment details alongside the existing status update response fields

### 10. MCP Tool: Comments in Query Results

**User Story:** As an agent, I want task query results to include comment data, so that I can read task activity without a separate tool call.

**Acceptance Criteria:**

1. <a name="10.1"></a>The `query_tasks` MCP tool response SHALL include a `comments` array for each task
2. <a name="10.2"></a>Each comment in the array SHALL include `id`, `authorName`, `content`, `isAgent`, and `creationDate`
3. <a name="10.3"></a>Comments in the response SHALL be ordered chronologically (oldest first)
4. <a name="10.4"></a>WHEN a task has no comments, THEN the `comments` field SHALL be an empty array

### 11. Comment Service

**User Story:** As a developer, I want all comment business logic encapsulated in a dedicated service, so that the architecture remains consistent with the existing service layer pattern.

**Acceptance Criteria:**

1. <a name="11.1"></a>The system SHALL provide a `CommentService` class following the `@MainActor @Observable` pattern used by `TaskService` and `ProjectService`
2. <a name="11.2"></a>The service SHALL provide methods for: adding a comment to a task, deleting a comment, and fetching comments for a task
3. <a name="11.3"></a>The service SHALL validate that comment content and author name are non-empty after trimming whitespace before creation
4. <a name="11.4"></a>The service SHALL define a typed `Error` enum for domain-specific errors
5. <a name="11.5"></a>Comments SHALL be fetched by querying from the `Comment` side with a predicate on the task's UUID, not via the optional to-many relationship on `TransitTask`
