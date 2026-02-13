# Implementation Explanation: Intent DisplayId Filter

## Beginner Level

### What Changed
Transit tasks have human-readable IDs like T-42. Before this change, the `QueryTasksIntent` (used by Shortcuts and CLI tools) could only search tasks by filters like status or type — there was no way to look up a specific task by its display ID. The MCP server already supported this, but the App Intent didn't.

This change adds a `displayId` field to the query input. When you pass `{"displayId": 42}`, the intent finds that specific task and returns extra detail (description and metadata) that isn't included in normal list queries.

### Why It Matters
CLI callers (like the `transit` MCP integration) need to fetch a single task's full details. Without this, they'd have to query all tasks and filter client-side, missing the description and metadata fields entirely.

### Key Concepts
- **App Intent**: A Swift framework that exposes app functionality to Shortcuts and Siri. `QueryTasksIntent` is one of Transit's three intents.
- **displayId**: A human-facing sequential integer (T-1, T-42) distinct from the internal UUID. Stored as `permanentDisplayId` on the model.
- **FetchDescriptor**: SwiftData's way of querying the database with a typed predicate — like a SQL WHERE clause but type-safe.

---

## Intermediate Level

### Changes Overview
Two files modified, plus spec docs and changelog:
- `QueryTasksIntent.swift` — Added `displayId: Int?` to the private `QueryFilters` Codable struct, an early-return lookup path in `execute()`, and a `detailed: Bool` parameter on `taskToDict()`
- `QueryTasksIntentTests.swift` — Three new tests covering the happy path (detailed output), not-found (empty array), and filter composition (displayId + status filter)

### Implementation Approach
The implementation follows the same pattern as the existing MCP handler but with one deliberate difference: it uses `FetchDescriptor` directly on the `modelContext` instead of going through `TaskService.findByDisplayID()`. This avoids adding a `TaskService` dependency to the intent's testable `execute()` method, which currently only takes `ProjectService` and `ModelContext`.

The key design choice is reusing `applyFilters()` on the single-task result. Rather than adding separate filter logic for the displayId path, the found task is wrapped in a `[task]` array and passed through the existing filter pipeline. This means `displayId` composes naturally with all other filters (status, type, projectId, date ranges) with zero new filter code.

The `taskToDict` function gained a `detailed: Bool = false` parameter. When true, it includes `description` (always, even if nil) and `metadata` (only if non-empty). The default `false` keeps the existing list response format unchanged.

### Trade-offs
- **Direct fetch vs TaskService**: Using `FetchDescriptor` directly is a pragmatic choice — the intent doesn't own a `TaskService` and this is a read-only lookup. The trade-off is a small duplication of the predicate logic, but it avoids changing the `execute()` signature and all existing tests.
- **Empty array vs error for not-found**: Returning `[]` instead of a `TASK_NOT_FOUND` error matches MCP handler behavior and is better for programmatic callers that can check array length.

---

## Expert Level

### Technical Deep Dive
The `FetchDescriptor` uses `#Predicate { $0.permanentDisplayId == displayId }` with `fetchLimit = 1`. Since `permanentDisplayId` is an `Int?` on the model, the predicate correctly handles the nil case — tasks with provisional IDs (nil `permanentDisplayId`) won't match.

The `(try? modelContext.fetch(descriptor)) ?? []` pattern silently swallows fetch errors, returning empty results. This is consistent with the existing full-task fetch on line 123 and is acceptable for a read-only query where the only realistic failure is a corrupted store.

The `detailed` flag adds `task.taskDescription as Any` — casting to `Any` preserves the `nil` as `NSNull`, which `JSONSerialization` encodes as JSON `null`. This means the `description` key is always present in detailed responses (even when nil), providing a stable schema for callers. Metadata uses the opposite convention — omitted when empty — matching the MCP handler exactly.

### Architecture Impact
This change keeps `QueryTasksIntent` self-contained. It doesn't introduce new dependencies or change the existing `execute()` contract. The `detailed` flag on `taskToDict` is a minimal extension that could support other detailed views in the future, though no such use is planned.

The approach creates a minor divergence: the MCP handler routes through `TaskService.findByDisplayID()` while the intent queries SwiftData directly. Both produce identical results for the same input, but if `findByDisplayID()` ever gains validation logic (e.g., rejecting negative IDs), the intent path wouldn't benefit. Given the spec explicitly states non-positive IDs simply return `[]`, this is acceptable.

### Potential Issues
- **`permanentDisplayId` index**: There's no explicit index on `permanentDisplayId`. For small-to-medium task counts (single-user app), this is fine. If performance became a concern, adding a SwiftData index annotation would help.
- **Concurrent display ID assignment**: If a task's `permanentDisplayId` is being promoted from provisional at the same moment a query arrives, the fetch might miss it. This is a pre-existing race condition in the display ID system, not introduced by this change.

---

## Completeness Assessment

### Fully Implemented
- All 6 requirements from the smolspec are met
- All 7 tasks from the task list are completed and verified
- Detailed output format matches MCP handler exactly
- Filter composition works with all existing filter types
- `@Parameter` description updated with displayId documentation
- 3 new tests covering core scenarios

### Partially Implemented
- None identified

### Missing
- None identified
