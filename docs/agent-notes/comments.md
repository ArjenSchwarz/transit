# Comments Feature

## Data Model

`Comment` (`@Model`) — belongs to one `TransitTask` via optional `task` relationship.

Fields: `id` (UUID), `content` (String), `authorName` (String), `isAgent` (Bool), `creationDate` (Date), `task` (TransitTask?).

## Service Layer

`CommentService` (`@MainActor @Observable`) — CRUD for comments.

- `addComment(to:content:authorName:isAgent:save:)` — validates non-empty content/author, trims whitespace, resolves the task in the service's own `ModelContext` (to avoid cross-context relationship issues), inserts and optionally saves. `save: false` allows batching with other mutations.
- `deleteComment(_:)` — permanent delete.
- `fetchComments(for taskID:)` — queries from Comment side (predicate on `task?.id`), sorted by creationDate ascending.
- `commentCount(for taskID:)` — uses `fetchCount` for efficiency.
- `resolveTask(_:)` (private) — re-fetches a task in the service's context by UUID. Fast path via `registeredModel(for:)` when already in context.
- Error cases: `.emptyContent`, `.emptyAuthorName`, `.commentNotFound`, `.taskNotFound`.

### Cross-context gotcha (T-73)

The app uses a separate `ModelContext` for services (created in `TransitApp.init()`) vs `container.mainContext` used by `@Query` in views. When a view passes a task object from `@Query` to `CommentService.addComment()`, the task belongs to `mainContext` but the comment is inserted into the service's context. SwiftData does not immediately resolve cross-context relationships, so any fetch predicate on the relationship (`$0.task?.id`) will fail to find the newly inserted comment. The fix is to always resolve model objects in the service's own context before establishing relationships.

## Integration Points

### MCP (macOS only)

- `MCPToolHandler` has `commentService` dependency (passed in init).
- `add_comment` tool: resolves task by displayId or taskId, calls `addComment` with `isAgent: true`.
- `query_tasks` / display ID lookup: `taskToDict` includes a `comments` array in every task response.
- `MCPToolHandler` uses a `resolveTask(from:)` helper (returns `Result<TransitTask, String>`) shared by `update_task_status` and `add_comment`.

### App Intents

- `AddCommentIntent` — uses typed `@Parameter` fields (not JSON input). Uses `VisualIntentError` for throwable errors.
- Registered in `TransitShortcuts` and `AppDependencyManager`.
- `CommentService` registered with `AppDependencyManager` in `TransitApp.init()`.

## File Locations

- Model: `Transit/Transit/Models/Comment.swift`
- Service: `Transit/Transit/Services/CommentService.swift`
- Intent: `Transit/Transit/Intents/AddCommentIntent.swift`
- MCP handler: `Transit/Transit/MCP/MCPToolHandler.swift` (extension for add_comment)
- MCP definitions: `Transit/Transit/MCP/MCPToolDefinitions.swift`

## Structural Note

`MCPToolHandler.swift` was refactored to stay under SwiftLint's 400-line file limit and 250-line type body limit:
- Tool definitions extracted to `MCPToolDefinitions.swift`.
- `handleAddComment` and helper methods moved to a same-file extension.
- Helper methods (`resolveTask`, `textResult`, `errorResult`, `stringMetadata`, `taskToDict`) are non-private so the extension can access them (same-file private would also work in Swift, but the access level was broadened during refactoring).
