# Implementation Explanation: Add Comments (T-46)

## Beginner Level

### What Changed

Transit tasks now support comments — timestamped notes that can be left by either the user or automated agents. Think of comments as a simple activity log on each task, like sticky notes on a kanban card.

The feature adds:
- A new **Comment** data entity that stores the text, who wrote it, when, and whether it came from an agent
- A **Comments section** inside the task detail view where you can read and write comments
- A **comment count badge** on dashboard task cards so you can see activity at a glance
- A **"Your Name" setting** in the app's Settings so your comments are attributed to you
- An **Add Comment Shortcut** so you can add comments via Siri or the Shortcuts app
- **MCP server tools** so automated agents (like Claude Code) can add comments and see them in query results

### Why It Matters

Without comments, tasks in Transit are static — you can only see the task name, status, and metadata. Comments add a lightweight way to record progress, decisions, or context. This is especially important for agent workflows: when an automated tool changes a task's status, it can now explain *why* alongside the change.

### Key Concepts

- **SwiftData entity**: A Swift class decorated with `@Model` that SwiftData automatically persists to disk and syncs via CloudKit. Like a database table row.
- **MCP (Model Context Protocol)**: A protocol that lets external AI agents call tools exposed by Transit's built-in HTTP server. Only runs on macOS.
- **App Intent**: An action exposed to Apple's Shortcuts app, allowing automation without opening the full app.
- **isAgent flag**: A boolean on each comment that records whether it was created by a person (false) or an automated tool (true). This drives visual styling — agent comments get a purple tint and robot icon.

---

## Intermediate Level

### Changes Overview

32 files changed across 5 layers: data model, service, UI, MCP integration, and App Intents. 7 new source files, 3 new test files, and modifications to 8 existing files.

**New source files:**
- `Comment.swift` — SwiftData `@Model` entity
- `CommentService.swift` — `@MainActor @Observable` service (CRUD + validation)
- `CommentsSection.swift` — Platform-specific UI (iOS `Section` / macOS `LiquidGlassSection`)
- `CommentRowView.swift` — Single comment display with agent/user distinction
- `AddCommentIntent.swift` — User-facing Shortcut with typed parameters
- `MCPToolDefinitions.swift` — Extracted from MCPToolHandler for SwiftLint compliance
- `MCPCommentTests.swift` — Dedicated MCP comment test suite

**Key modifications:**
- `TransitTask.swift` — Added `@Relationship(deleteRule: .cascade)` inverse to Comment
- `TaskService.swift` — Extended `updateStatus` with optional comment params for atomic operations
- `MCPToolHandler.swift` — New `add_comment` tool, comment-on-status-change, comments in query results
- `TransitApp.swift` — CommentService creation, environment injection, AppDependencyManager registration

### Implementation Approach

The architecture follows Transit's established patterns:

1. **Service layer**: `CommentService` encapsulates all comment logic, keeping views thin. It takes a `ModelContext` in its initializer and provides `addComment`, `deleteComment`, `fetchComments`, and `commentCount` methods. Validation (trimming whitespace, rejecting empty content/author) happens at the service level.

2. **Query from child side**: Per SwiftData/CloudKit constraints, `fetchComments(for:)` uses a `FetchDescriptor<Comment>` with a predicate on `$0.task?.id == taskID` rather than traversing the optional to-many relationship on `TransitTask`. This avoids the `#Predicate` limitation with optional collections.

3. **Atomic status + comment**: `TaskService.updateStatus` accepts optional `comment`, `commentAuthor`, and `commentService` parameters. When present, it calls `commentService.addComment(save: false)` before its own `modelContext.save()`, ensuring both mutations land in a single transaction.

4. **Platform-specific UI**: `CommentsSection` uses `#if os()` to provide iOS Form-compatible layout (with swipe-to-delete) and macOS LiquidGlassSection layout (with hover-to-delete). `CommentRowView` handles agent distinction via purple tint, robot icon avatar, and "Agent" badge.

5. **MCP integration**: Three MCP touchpoints — new `add_comment` tool, optional `comment`/`authorName` on `update_task_status`, and `comments` array in `query_tasks` responses. The handler was refactored to extract a shared `resolveTask(from:)` helper.

### Trade-offs

- **No edit capability**: Comments are append-only with individual delete. This simplifies the UI (no edit mode) and preserves the activity-log mental model, at the cost of needing delete + re-add to fix typos.
- **`isAgent` boolean vs. string comparison**: An explicit boolean field prevents display name changes from retroactively reclassifying user comments as agent comments (Decision 4).
- **Typed parameters on AddCommentIntent**: Unlike existing JSON-based intents, this uses typed `@Parameter` fields for a better Shortcuts experience. Agent-facing JSON intents are deferred to a separate spec (Decision 5).
- **Comment count via `fetchCount`**: Each `TaskCardView` calls `commentService.commentCount(for:)` in its body. This is efficient for a single-user app but won't reactively update while the dashboard is visible (acceptable since comments are added from the detail view).

---

## Expert Level

### Technical Deep Dive

**ModelContext sharing**: `CommentService` and `TaskService` share the same `ModelContext` instance (created in `TransitApp.init`). This is what makes atomic status + comment saves work — both services mutate models tracked by the same context, so a single `modelContext.save()` persists both.

**The `save: false` pattern**: `addComment(save: false)` inserts the Comment into the context without calling save. The caller (TaskService) is responsible for the save. This is important for atomicity (req 9.4) — if either mutation fails, neither is persisted. The test `addComment_saveFalse_doesNotPersistUntilExplicitSave` verifies this by rolling back the context.

**Whitespace validation boundary**: Validation happens at two levels. The MCP handler's `validateCommentArgs` trims and rejects whitespace-only comments before they reach the service, preventing a scenario where `StatusEngine.applyTransition` mutates the task in memory but the subsequent `addComment` throws, leaving unsaved dirty state. The service layer also trims independently as a defense-in-depth measure.

**CloudKit compatibility**: The `Comment` entity follows all CloudKit constraints — default values on all fields, optional relationship to parent, no `@Attribute(.unique)`, cascade delete rule. The schema is registered in both the app container and `TestModelContainer`.

**MCP tool definition extraction**: `MCPToolDefinitions.swift` was extracted from `MCPToolHandler.swift` to stay under SwiftLint's file/type body length limits. The definitions use a `nonisolated enum` since they're pure data with no actor-bound state.

### Architecture Impact

- **Environment chain**: `CommentService` is injected via `.environment(commentService)` in the SwiftUI hierarchy and registered with `AppDependencyManager` for App Intents. Any view or intent can access it.
- **MCPToolHandler dependency growth**: The handler now takes three services (task, project, comment). If more features follow this pattern, consider a service container or protocol.
- **Test isolation**: All test suites create independent `ModelContext` instances via `TestModelContainer.newContext()`, each backed by a uniquely named in-memory container. This prevents cross-suite data leakage.

### Potential Issues

- **Dashboard comment count staleness**: `TaskCardView` computes comment count on each render but isn't driven by `@Query`. The count will be correct when the view rebuilds (e.g., on navigation) but won't live-update if a comment is added via MCP while the dashboard is visible. Acceptable for V1.
- **No pagination**: Comments are fetched all at once. For tasks with very many comments, this could become slow. Not a concern for a single-user app in V1.
- **`fetchCount` per card**: Each visible task card makes a separate `fetchCount` call. For a dashboard with dozens of visible cards, this is many small queries. SwiftData handles these efficiently, but a denormalized count field could be added if profiling shows issues.

---

## Completeness Assessment

### Fully Implemented

All 11 requirement groups (45 individual acceptance criteria) are implemented:

| Requirement | Status |
|---|---|
| 1. Comment Data Model (1.1–1.5) | Complete |
| 2. User Display Name (2.1–2.4) | Complete |
| 3. Adding Comments via UI (3.1–3.9) | Complete |
| 4. Agent Comment Distinction (4.1–4.4) | Complete |
| 5. Deleting Comments (5.1–5.4) | Complete |
| 6. Comment Count on Cards (6.1–6.3) | Complete |
| 7. App Intent (7.1–7.5) | Complete |
| 8. MCP add_comment (8.1–8.6) | Complete |
| 9. MCP comment on status update (9.1–9.6) | Complete |
| 10. MCP comments in query results (10.1–10.4) | Complete |
| 11. Comment Service (11.1–11.5) | Complete |

### Test Coverage

- **CommentServiceTests**: 14 tests covering CRUD, validation, cascade delete, deferred save, isAgent preservation
- **TaskServiceTests**: 3 new tests for atomic status + comment, isAgent flag, backwards compatibility
- **MCPCommentTests**: 8 tests covering add_comment, update_task_status with comment, query_tasks with comments, whitespace edge case
- **AddCommentIntentTests**: 8 tests covering valid input, validation errors, isAgent defaults, identifier formats

### Spec Divergences

1. **Design spec**: `updateStatus` was specified with `@discardableResult` and `-> TransitTask` return. Implementation uses `Void` return since no caller needs the return value. Simpler without functional change.
2. **Design spec**: `AddCommentIntent` uses `VisualIntentError` instead of the design's `IntentError` type. `VisualIntentError` was introduced after the design was written and is the correct error type for user-facing intents with `LocalizedError` messaging.

Both divergences are improvements over the design and don't affect requirement satisfaction.
