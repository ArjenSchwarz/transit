# MCP Task ID Filter — Implementation Explanation

## Beginner Level

### What Changed
Transit's MCP server lets external tools (like Claude Code) manage tasks programmatically. Before this change, if you wanted to look up a specific task like T-47, you had to fetch *all* tasks and search through them yourself. Now, you can ask `query_tasks` directly for a task by its display ID, and it returns richer details (description and metadata) than a normal listing.

### Why It Matters
When an AI agent is working on task T-47, it needs to quickly fetch that task's full details — description, metadata like git branch info, status, and type. Without this, the agent had to download everything and filter client-side, which is wasteful and means it never got description/metadata fields at all.

### Key Concepts
- **Display ID**: The human-readable task number (e.g., T-47). Internally tasks also have a UUID, but display IDs are what people and agents use.
- **MCP (Model Context Protocol)**: A standard way for AI tools to interact with external applications. Transit exposes an MCP server that AI agents can call.
- **Conjunctive filtering**: When you provide multiple filters (e.g., displayId + status), they combine with AND logic — the task must match *all* filters to be returned.

---

## Intermediate Level

### Changes Overview
Two production files changed, plus test infrastructure:

- **`MCPToolHandler.swift`**: Added `displayId` parameter to `query_tasks` tool schema and a fast-path handler (`handleDisplayIdLookup`) that uses `TaskService.findByDisplayID()` for predicate-based fetch instead of loading all tasks. Extracted inline filter logic into a `QueryFilters` struct. Added a `detailed` parameter to `taskToDict` that includes `description` and `metadata` fields.
- **`MCPToolHandlerTests.swift`**: 6 new tests for displayId scenarios, plus existing tests updated to handle the `JSONRPCResponse?` optional return type from `handle()`.
- **`QueryTasksIntentTests.swift`**: Fixed a pre-existing bug where `completionDate` was asserted as always present, but it's only set for completed tasks.

### Implementation Approach
The displayId path short-circuits before the full-table `FetchDescriptor<TransitTask>` fetch. This follows the existing pattern from `update_task_status` which already parses `displayId` via `args["displayId"] as? Int`.

Filter composition is handled by a `QueryFilters` struct with a `matches(_:)` method. The displayId lookup finds the task first, then applies the same filter check — if the task doesn't match the additional filters, an empty array is returned (not an error).

The `taskToDict` helper gained a `detailed: Bool` parameter (default `false`) that controls whether `description` and `metadata` are included. This keeps the standard listing payload compact while giving full details for single-task lookups.

### Trade-offs
- **Separate `get_task` tool vs. filter on `query_tasks`**: A dedicated tool would be more explicit, but adding a filter to the existing tool is simpler, avoids tool proliferation, and composes naturally with other filters.
- **Detailed fields only on displayId queries**: Including description/metadata on all queries would increase payload size when listing many tasks. The spec explicitly scopes detailed fields to displayId lookups.
- **`taskNotFound` → empty array (not error)**: This follows query semantics — a query that matches nothing returns empty results. Data integrity errors (`duplicateDisplayID`) still propagate as errors.

---

## Expert Level

### Technical Deep Dive
The `handleDisplayIdLookup` method uses typed error catching: `catch TaskService.Error.taskNotFound` returns `[]`, while the generic `catch` propagates other errors (including `duplicateDisplayID`, which indicates data corruption). This is a deliberate design choice from the spec — silent empty returns for expected "not found" cases, loud errors for integrity violations.

The `QueryFilters` struct is `private` to the file and `nonisolated` (no `@MainActor`), which is fine since it only reads raw string/UUID properties that are copied at construction time. The `matches(_:)` method accesses `task.statusRawValue`, `task.typeRawValue`, and `task.project?.id` — all stored/computed properties on `@Model` objects accessed from the `@MainActor` context of the handler.

The `as Any` cast on line 291 (`dict["description"] = task.taskDescription as Any`) handles the nil case by inserting `NSNull` into the dictionary, which `JSONSerialization` serializes as JSON `null`. This is intentional — the description key is always present in detailed responses, with `null` indicating "no description set".

### Architecture Impact
This change is additive and narrowly scoped. The `QueryFilters` extraction is a refactoring that consolidates previously inline filter logic — it doesn't change any behaviour for existing query paths. The `detailed` parameter on `taskToDict` is a boolean flag rather than a separate serialization function, keeping the serialization logic in one place.

The pattern established here (displayId early-return → filter check → detailed serialization) can be extended to a future `taskId` (UUID) filter with minimal changes.

### Potential Issues
- **NSNull serialization**: The `task.taskDescription as Any` cast produces `NSNull` when nil. If the JSON output is consumed by a client that doesn't handle `null` values, this could cause issues. However, JSON `null` is standard and expected per the spec.
- **`@MainActor` isolation on `QueryFilters`**: The struct accesses `@Model` properties. Under Swift 6's default `@MainActor` isolation, this works because `QueryFilters` is called from `@MainActor`-isolated methods. If `handleQueryTasks` were ever moved off the main actor, `QueryFilters.matches` would need adjustment. In practice this won't happen since SwiftData contexts are main-actor bound.

---

## Completeness Assessment

### Fully Implemented
- `displayId` parameter on `query_tasks` tool schema with updated tool description
- Predicate-based single-task lookup via `TaskService.findByDisplayID()`
- Detailed response fields (`description`, `metadata`) for displayId queries
- Conjunctive filter composition (displayId + status/type/projectId)
- Empty array return for not-found (not error)
- Existing query behaviour unchanged (no description/metadata without displayId)
- `taskNotFound` → empty array, `duplicateDisplayID` → error propagation
- 6 unit tests covering all specified scenarios

### Partially Implemented
None.

### Missing
None. All requirements from the smolspec are addressed.
