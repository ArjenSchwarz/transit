# Design: Milestones

## Overview

Milestones add a grouping layer between projects and tasks. A milestone belongs to a project, tasks optionally belong to a milestone, and milestones have their own display IDs (M-1, M-2) and lifecycle (Open/Done/Abandoned). The implementation follows existing patterns throughout — SwiftData model, service layer, MCP tools, App Intents, and cross-platform views.

---

## 1. Data Model

### 1.1 MilestoneStatus Enum

New file: `Models/MilestoneStatus.swift`

```swift
nonisolated enum MilestoneStatus: String, CaseIterable, Sendable, Equatable {
    case open
    case done
    case abandoned

    nonisolated var isTerminal: Bool {
        self == .done || self == .abandoned
    }

    nonisolated var displayName: String {
        switch self {
        case .open: "Open"
        case .done: "Done"
        case .abandoned: "Abandoned"
        }
    }
}
```

Marked `nonisolated` to opt out of default MainActor isolation, same pattern as `TaskType`. No `Codable` conformance (avoids MainActor isolation issues per technical constraints).

### 1.2 Milestone Model

New file: `Models/Milestone.swift`

```swift
@Model
final class Milestone {
    var id: UUID = UUID()
    var permanentDisplayId: Int?
    var name: String = ""
    var milestoneDescription: String?
    var statusRawValue: String = "open"
    var creationDate: Date = Date()
    var lastStatusChangeDate: Date = Date()
    var completionDate: Date?

    var project: Project?

    @Relationship(deleteRule: .nullify, inverse: \TransitTask.milestone)
    var tasks: [TransitTask]?

    var status: MilestoneStatus {
        get { MilestoneStatus(rawValue: statusRawValue) ?? .open }
        set { statusRawValue = newValue.rawValue }
    }

    var displayID: DisplayID {
        if let id = permanentDisplayId {
            return .permanent(id)
        }
        return .provisional
    }

    init(name: String, description: String? = nil, project: Project, displayID: DisplayID) {
        self.id = UUID()
        self.name = name
        self.milestoneDescription = description
        self.project = project
        self.creationDate = Date.now
        self.lastStatusChangeDate = Date.now
        self.statusRawValue = MilestoneStatus.open.rawValue

        switch displayID {
        case .permanent(let id):
            self.permanentDisplayId = id
        case .provisional:
            self.permanentDisplayId = nil
        }
    }
}
```

Follows `TransitTask` patterns: raw string for status, computed property for the enum, `DisplayID` for display formatting, optional relationships for CloudKit compatibility.

### 1.3 Relationship Changes

**TransitTask** — add:
```swift
var milestone: Milestone?
```

**Project** — add:
```swift
@Relationship(deleteRule: .cascade, inverse: \Milestone.project)
var milestones: [Milestone]?
```

Project uses `.cascade` for milestones (milestones are meaningless without their project). Milestone uses `.nullify` for tasks (tasks exist independently).

### 1.4 DisplayID Prefix Support

`DisplayID.formatted` currently hardcodes "T-". Add a new method alongside the existing property:

```swift
enum DisplayID: Equatable, Sendable {
    case permanent(Int)
    case provisional

    /// Existing property — preserved for backward compatibility. No call site changes needed.
    nonisolated var formatted: String {
        formatted(prefix: "T")
    }

    /// New method for milestone display IDs.
    nonisolated func formatted(prefix: String) -> String {
        switch self {
        case .permanent(let id): "\(prefix)-\(id)"
        case .provisional: "\(prefix)-\u{2022}"
        }
    }
}
```

Existing call sites continue using `.formatted`. Milestone code uses `.formatted(prefix: "M")`. No churn.

---

## 2. Service Layer

### 2.1 MilestoneService

New file: `Services/MilestoneService.swift`

`@MainActor @Observable` class following `TaskService` / `ProjectService` patterns.

```swift
@Observable
final class MilestoneService {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case invalidName
        case milestoneNotFound
        case duplicateName
        case projectRequired
        case projectMismatch
    }

    private let modelContext: ModelContext
    private let displayIDAllocator: DisplayIDAllocator

    init(modelContext: ModelContext, displayIDAllocator: DisplayIDAllocator) { ... }

    // MARK: - CRUD

    func createMilestone(
        name: String,
        description: String?,
        project: Project
    ) async throws -> Milestone

    func updateMilestone(
        _ milestone: Milestone,
        name: String?,
        description: String?
    ) throws

    func updateStatus(_ milestone: Milestone, to newStatus: MilestoneStatus) throws

    func deleteMilestone(_ milestone: Milestone) throws

    // MARK: - Assignment

    /// Central validation point for milestone assignment. Validates that the task
    /// has a project and that the milestone belongs to the same project.
    /// Pass nil to unassign.
    func setMilestone(_ milestone: Milestone?, on task: TransitTask) throws

    // MARK: - Promotion

    /// Finds milestones with provisional display IDs, allocates permanent IDs.
    /// Called from ConnectivityMonitor.onRestore and ScenePhaseModifier.
    func promoteProvisionalMilestones() async

    // MARK: - Lookup

    func findByID(_ id: UUID) throws -> Milestone
    func findByDisplayID(_ displayId: Int) throws -> Milestone
    func findByName(_ name: String, in project: Project) -> Milestone?
    func milestonesForProject(_ project: Project, status: MilestoneStatus? = nil) -> [Milestone]
    func milestoneNameExists(_ name: String, in project: Project, excluding: UUID? = nil) -> Bool
}
```

**Key behaviours:**

- `createMilestone`: validates name non-empty, checks uniqueness within project (case-insensitive), allocates display ID (provisional on failure), inserts into context, saves.
- `updateMilestone`: validates new name if provided, checks uniqueness excluding self. Wraps `modelContext.save()` with rollback on failure.
- `updateStatus`: updates `statusRawValue`, `lastStatusChangeDate`, sets/clears `completionDate` based on terminal status. **Throws on save failure with rollback** (same pattern as `TaskService.updateStatus`, per T-150 fix). No StatusEngine needed — the three-state lifecycle is simple enough to inline.
- `deleteMilestone`: shows confirmation of affected task count, deletes from context, saves. SwiftData handles nullifying task associations.
- `setMilestone(_:on:)`: validates `task.project != nil`, validates `milestone.project?.id == task.project?.id` (throws `.projectMismatch` on mismatch), sets `task.milestone`. All milestone assignment flows (views, MCP, intents) go through this method.
- `promoteProvisionalMilestones()`: queries milestones with `permanentDisplayId == nil`, allocates IDs via the dedicated allocator. Same pattern as `DisplayIDAllocator.promoteProvisionalTasks` but for milestones.
- Lookup methods use `FetchDescriptor` with `#Predicate` on the Milestone side (never traversing `Project.milestones` to-many), same pattern as `TaskService`.

**Known limitation:** Name uniqueness check in `createMilestone` has a TOCTOU window during the async display ID allocation. In a single-user app, concurrent creation of identically-named milestones in the same project is extremely unlikely. Acceptable tradeoff.

### 2.2 DisplayIDAllocator Changes

The `CloudKitCounterStore` (private class inside `DisplayIDAllocator.swift`) currently hardcodes the record name. Parameterise the internal store and expose a new convenience init:

```swift
// Internal change — CloudKitCounterStore accepts record name
private final class CloudKitCounterStore: DisplayIDAllocator.CounterStore {
    // ... parameterised init with recordName, keeping existing defaults
    init(database: CKDatabase, recordName: String = "global-counter") { ... }
}

// New public convenience init on DisplayIDAllocator
convenience init(
    container: CKContainer = .default(),
    counterRecordName: String = "global-counter",
    retryLimit: Int = 5
) {
    self.init(
        store: CloudKitCounterStore(
            database: container.privateCloudDatabase,
            recordName: counterRecordName
        ),
        retryLimit: retryLimit
    )
}
```

`CloudKitCounterStore` stays private — the record name is passed through the public convenience init. Create two allocator instances in `TransitApp.swift`:

```swift
let taskIDAllocator = DisplayIDAllocator()  // uses default "global-counter"
let milestoneIDAllocator = DisplayIDAllocator(counterRecordName: "milestone-counter")
```

The existing convenience init signature is preserved (backward compatible). The default `counterRecordName: "global-counter"` matches the current hardcoded value.

### 2.3 Milestone Promotion

`MilestoneService` owns promotion logic (Option B — keeps `DisplayIDAllocator` unaware of `Milestone`). The `promoteProvisionalMilestones()` method queries milestones with `permanentDisplayId == nil`, sorted by `creationDate`, and allocates permanent IDs via `allocateNextID()` on the dedicated milestone allocator instance. Same stop-on-first-failure pattern as the existing task promotion.

### 2.4 TaskService Changes

Add milestone clearing **before** project reassignment:

```swift
// Clear milestone BEFORE project change (after change, old project ID is lost)
if task.project?.id != newProject.id {
    task.milestone = nil
}
task.project = newProject
```

All milestone assignment goes through `MilestoneService.setMilestone(_:on:)` — views and MCP/intent handlers call that method, never set `task.milestone` directly.

### 2.5 App Entry Point Changes

`TransitApp.swift` needs:

1. Add `Milestone.self` to the production `Schema`
2. Create a second `DisplayIDAllocator` instance: `DisplayIDAllocator(counterRecordName: "milestone-counter")`
3. Create `MilestoneService` with `container.mainContext` and the milestone allocator
4. Inject `MilestoneService` into the environment via `.environment()`
5. Wire milestone promotion into existing triggers:
   - `ConnectivityMonitor.onRestore`: add `await milestoneService.promoteProvisionalMilestones()` after the existing task promotion call
   - `ScenePhaseModifier`: add `MilestoneService` as a parameter alongside the existing `DisplayIDAllocator`. Call `milestoneService.promoteProvisionalMilestones()` in both the `.task` modifier and the `.onChange(of: scenePhase)` handler, after task promotion

---

## 3. MCP Tools

### 3.1 New Tool: create_milestone

```json
{
    "name": "create_milestone",
    "description": "Create a new milestone within a project. At least one of 'project' or 'projectId' is required.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "name": { "type": "string", "description": "Milestone name (unique within project)" },
            "project": { "type": "string", "description": "Project name (case-insensitive)" },
            "projectId": { "type": "string", "description": "Project UUID (takes precedence over name)" },
            "description": { "type": "string", "description": "Optional description" }
        },
        "required": ["name"]
    }
}
```

Returns: `{ "milestoneId": "...", "displayId": 3, "name": "...", "status": "open", "project": "..." }`

### 3.2 New Tool: query_milestones

```json
{
    "name": "query_milestones",
    "description": "List milestones with optional filters. Returns all milestones if no filters specified.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "displayId": { "type": "integer", "description": "Look up a single milestone by display ID" },
            "project": { "type": "string", "description": "Filter by project name" },
            "projectId": { "type": "string", "description": "Filter by project UUID" },
            "status": {
                "type": "array",
                "items": { "type": "string", "enum": ["open", "done", "abandoned"] },
                "description": "Filter by status(es)"
            },
            "search": { "type": "string", "description": "Search milestone name and description (case-insensitive substring)" }
        }
    }
}
```

Returns array of milestone objects. Single-milestone lookup (by displayId) includes task list.

### 3.3 New Tool: update_milestone

```json
{
    "name": "update_milestone",
    "description": "Update a milestone's name, description, or status. Identify by displayId or milestoneId.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "displayId": { "type": "integer", "description": "Milestone display ID (e.g., 3 for M-3)" },
            "milestoneId": { "type": "string", "description": "Milestone UUID" },
            "name": { "type": "string", "description": "New name" },
            "description": { "type": "string", "description": "New description" },
            "status": { "type": "string", "enum": ["open", "done", "abandoned"], "description": "New status" }
        }
    }
}
```

Returns: `{ "milestoneId": "...", "displayId": 3, "name": "...", "status": "open", "previousStatus": "open", "project": "...", "projectId": "..." }`

### 3.4 New Tool: delete_milestone

```json
{
    "name": "delete_milestone",
    "description": "Delete a milestone. Tasks assigned to it lose their association but are not deleted. Identify by displayId or milestoneId.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "displayId": { "type": "integer", "description": "Milestone display ID (e.g., 3 for M-3)" },
            "milestoneId": { "type": "string", "description": "Milestone UUID" }
        }
    }
}
```

Returns: `{ "deleted": true, "milestoneId": "...", "displayId": 3, "name": "...", "affectedTasks": 5 }`

### 3.5 New Tool: update_task

```json
{
    "name": "update_task",
    "description": "Update a task's properties. Currently supports milestone assignment. Identify task by displayId or taskId.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "displayId": { "type": "integer", "description": "Task display ID (e.g., 42 for T-42)" },
            "taskId": { "type": "string", "description": "Task UUID" },
            "milestone": { "type": "string", "description": "Milestone name (within task's project). Set to null to unassign." },
            "milestoneDisplayId": { "type": "integer", "description": "Milestone display ID (e.g., 3 for M-3, takes precedence over name)" },
            "clearMilestone": { "type": "boolean", "description": "Set to true to remove milestone assignment" }
        }
    }
}
```

Returns the updated task object including milestone info. Uses `MilestoneService.setMilestone(_:on:)` for validation.

### 3.6 Modified Tool: create_task

Add optional parameters:
```json
"milestone": { "type": "string", "description": "Milestone name (within the task's project)" },
"milestoneDisplayId": { "type": "integer", "description": "Milestone display ID (e.g., 3 for M-3, takes precedence over name)" }
```

Task response includes milestone info when assigned: `"milestone": { "milestoneId": "...", "displayId": 3, "name": "v1.1" }`

### 3.7 Modified Tool: query_tasks

Add optional filter parameters:
```json
"milestone": { "type": "string", "description": "Filter by milestone name" },
"milestoneDisplayId": { "type": "integer", "description": "Filter by milestone display ID (e.g., 3 for M-3)" }
```

Task objects in responses include milestone when assigned:
```json
{
    "displayId": 42,
    "name": "Add milestones",
    "milestone": { "milestoneId": "...", "displayId": 3, "name": "v1.1" }
}
```

Provisional milestone display IDs are omitted from responses (same pattern as task display IDs).

### 3.8 Modified Tool: get_projects

Include milestones in each project's response:
```json
{
    "id": "...",
    "name": "Transit",
    "milestones": [
        { "milestoneId": "...", "displayId": 1, "name": "v1.0", "status": "done", "taskCount": 12 },
        { "milestoneId": "...", "displayId": 3, "name": "v1.1", "status": "open", "taskCount": 5 }
    ]
}
```

### 3.9 Milestone Response Object Shapes

**List/summary** (used in `query_milestones`, `get_projects`):
```json
{
    "milestoneId": "uuid",
    "displayId": 3,
    "name": "v1.0",
    "status": "open",
    "description": "First release",
    "projectId": "uuid",
    "projectName": "Transit",
    "taskCount": 5,
    "creationDate": "ISO8601",
    "lastStatusChangeDate": "ISO8601",
    "completionDate": null
}
```

**Detail** (single-milestone lookup via `query_milestones` with `displayId`):
```json
{
    "...all summary fields...",
    "tasks": [
        { "displayId": 42, "name": "Add milestones", "status": "in-progress", "type": "feature" }
    ]
}
```

### 3.10 MCPToolHandler Changes

- Add `MilestoneService` dependency to `MCPToolHandler.init`
- Add handler methods: `handleCreateMilestone`, `handleQueryMilestones`, `handleUpdateMilestone`, `handleDeleteMilestone`, `handleUpdateTask`
- Add `milestoneToDict` and `milestoneSummaryDict` helper methods
- Modify `handleCreateTask` to resolve and assign milestone via `MilestoneService.setMilestone`
- Modify `handleQueryTasks` to filter by milestone and include milestone in output
- Modify `handleGetProjects` to include milestone list per project
- Add all new tool definitions to `MCPToolDefinitions.all` array
- Add tool names to the dispatch switch in `handleToolCall`

---

## 4. App Intents

### 4.1 CreateMilestoneIntent

New file: `Intents/CreateMilestoneIntent.swift`

Follows `CreateTaskIntent` pattern: JSON string input, static `execute()` method, returns JSON with milestone details.

Input fields: `name` (required), `project` / `projectId` (one required), `description` (optional).

### 4.2 QueryMilestonesIntent

New file: `Intents/QueryMilestonesIntent.swift`

Follows `QueryTasksIntent` pattern. Filters: `displayId`, `project` / `projectId`, `status`.

### 4.3 UpdateMilestoneIntent

New file: `Intents/UpdateMilestoneIntent.swift`

Follows `UpdateStatusIntent` pattern. Identifies milestone by `displayId`, `milestoneId`, or `name` + `project`/`projectId`. Optional updates: `name`, `description`, `status`.

### 4.4 DeleteMilestoneIntent

New file: `Intents/DeleteMilestoneIntent.swift`

Identifies milestone by `displayId` or `milestoneId`. Returns confirmation with affected task count.

### 4.5 UpdateTaskIntent

New file: `Intents/UpdateTaskIntent.swift`

Identifies task by `displayId` or `taskId`. Supports updating milestone assignment (`milestone`, `milestoneDisplayId`, `clearMilestone`). Uses `MilestoneService.setMilestone(_:on:)`.

### 4.6 Modified Intents

- **CreateTaskIntent**: Add optional `milestone` / `milestoneDisplayId` fields to input parsing.
- **QueryTasksIntent**: Add optional `milestone` / `milestoneDisplayId` filter.
- **GenerateReportIntent**: No changes needed (report logic changes handle this).

### 4.7 Error Codes

Add to `IntentError`:
- `MILESTONE_NOT_FOUND`
- `DUPLICATE_MILESTONE_NAME`
- `MILESTONE_PROJECT_MISMATCH` (task and milestone belong to different projects)
- `INVALID_INPUT` (reused for `invalidName` and `projectRequired` from `MilestoneService.Error`)

---

## 5. UI Design

### 5.1 Dashboard — Milestone Filter

**FilterPopoverView** changes:

Add a "Milestones" section after the existing "Projects" section. Shows milestones as a selectable list with checkmarks (same pattern as project filter).

- When a project filter is active: show milestones from selected project(s) only
- When no project filter: show all open milestones across projects, plus any currently-selected milestones (even if no longer open) so they can be deselected
- When project filter changes: clear milestone selection
- State: `@State private var selectedMilestones: Set<UUID>` (ephemeral)
- Stale state: if a selected milestone is marked Done/Abandoned, it remains in the filter (tasks are still matched by UUID). The popover shows it with a visual indicator (dimmed or strikethrough) so the user can deselect it.

**DashboardView** filtering:

Add milestone predicate to the existing filter chain. Filter tasks where `task.milestone?.id` is in the selected set. Since `#Predicate` can't query optional relationships reliably, filter in-memory after the existing fetch.

### 5.2 Task Card — Milestone Badge

**TaskCardView** changes:

When `task.milestone` is non-nil, show a small badge below the type badge:

```swift
if let milestone = task.milestone {
    Text(milestone.name)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.fill.tertiary, in: Capsule())
}
```

### 5.3 Task Detail View

**TaskDetailView** changes:

Add a "Milestone" row in the metadata section showing `milestone.name (M-<id>)` or "None". Tapping navigates to a future milestone detail view, or does nothing for now.

### 5.4 Task Edit View

**TaskEditView** changes:

Add a milestone picker after the project picker. Uses a `Picker` with `.menu` style showing open milestones from the task's current project, plus a "None" option.

```swift
Picker("Milestone", selection: $selectedMilestone) {
    Text("None").tag(nil as Milestone?)
    ForEach(openMilestones) { milestone in
        Text(milestone.name).tag(milestone as Milestone?)
    }
}
```

When the project changes (existing project picker), reset `selectedMilestone` to nil and reload `openMilestones` for the new project.

### 5.5 Add Task Sheet

**AddTaskSheet** changes:

Add milestone picker after project picker, same pattern as TaskEditView. Filtered to open milestones for the selected project. Resets when project changes.

### 5.6 Settings — Milestone Management

Two approaches considered:

**Option A:** Milestones section within each project's edit view (ProjectEditView).
**Option B:** Separate milestone list in settings, grouped by project.

**Chosen: Option A** — milestones are project-scoped, so managing them within the project context is natural. Add a "Milestones" section to `ProjectEditView` (or a new `ProjectDetailView` if ProjectEditView is too crowded) showing the project's milestones with create/edit/delete capabilities.

Milestone deletion shows a confirmation alert stating how many tasks will lose their milestone assignment (e.g. "Delete milestone 'v1.0'? 5 tasks will be unassigned from this milestone.").

**New views:**

- `MilestoneListSection` — reusable section showing milestones for a project with add/status-change/delete actions
- `MilestoneEditView` — form for creating/editing a milestone (name, description). Follows `ProjectEditView` pattern with platform-specific layouts.

Navigation: Add `.milestoneEdit(Milestone?)` to `NavigationDestination` enum. Project detail pushes to milestone edit.

### 5.7 Share Text

Update `TransitTask.shareText(comments:)` to include milestone:

```swift
if let milestone {
    text += "Milestone: \(milestone.name) (\(milestone.displayID.formatted(prefix: "M")))\n"
}
```

---

## 6. Reports

### 6.1 ReportData Changes

Add milestone name to `ReportTask`:
```swift
struct ReportTask: Identifiable {
    // ... existing fields ...
    let milestoneName: String?  // New
}
```

Add milestone summary type:
```swift
struct ReportMilestone: Identifiable {
    let id: UUID
    let displayID: String
    let name: String
    let isAbandoned: Bool
    let taskCount: Int
}
```

Add milestones to `ProjectGroup`:
```swift
struct ProjectGroup: Identifiable {
    // ... existing fields ...
    let milestones: [ReportMilestone]  // New — completed milestones in this period
}
```

### 6.2 ReportLogic Changes

After filtering terminal tasks, also query milestones with `completionDate` in the date range. Group by project. Include in `ProjectGroup` before task rows.

### 6.3 ReportView Changes

In `projectSection`, render completed milestones before task rows:

```swift
ForEach(group.milestones) { milestone in
    milestoneRow(milestone)
}
if !group.milestones.isEmpty && !group.tasks.isEmpty {
    Divider()
}
ForEach(group.tasks) { task in
    taskRow(task)
}
```

### 6.4 ReportMarkdownFormatter Changes

Add milestone section before tasks in each project group:

```markdown
## Project Name

### Milestones
- M-3: v1.0 (Done) — 12 tasks
- M-5: Beta (Abandoned) — 3 tasks

### Tasks
- T-42: Feature: Add milestones [v1.0]
- T-43: Bug: Fix display ID
```

Task lines include `[milestone-name]` suffix when assigned.

---

## 7. Test Infrastructure

### 7.1 TestModelContainer and Schema Updates

Update **every** explicit `Schema(...)` in the codebase to include `Milestone.self`. This includes:

- `TestModelContainer.swift` (shared test container)
- `TransitApp.swift` (production schema)
- Any test files with inline schema definitions (e.g., `TaskServiceTests`, `TaskEntityTests`, `ProjectEntityTests`, `CommentServiceTests`, `ReportLogicTestHelpers`, `TaskCreationResultTests`, `TaskEntityQueryTests`)

Without this, tests crash at container creation with a missing model error since `TransitTask` now has a relationship to `Milestone`.

### 7.2 InMemoryCounterStore

Already generic — usable for milestone allocator tests without changes.

### 7.3 UI Test Seed Data

Update `seedBoardScenario()` in `TransitApp.swift` to create sample milestones for UI testing.

### 7.4 New Test Suites

- `MilestoneServiceTests` — CRUD, name uniqueness, status transitions, project scoping, `setMilestone` validation, project-mismatch errors
- `MilestoneStatusTests` — enum properties
- `MCPMilestoneToolTests` — create/query/update/delete milestone tools, update_task tool, error cases
- `CreateMilestoneIntentTests` — intent execution, error codes
- `QueryMilestonesIntentTests` — filter logic
- `UpdateMilestoneIntentTests` — status changes, renames
- `DeleteMilestoneIntentTests` — deletion, affected task count
- `ReportMilestoneTests` — milestone inclusion in reports

---

## 8. Migration

This is an add-only change compatible with CloudKit post-deployment migration:

- New `Milestone` model (new table)
- New `milestone` optional relationship on `TransitTask` (new column, nullable)
- New `milestones` relationship on `Project` (inverse, no schema change needed)
- New CloudKit counter record `milestone-counter` (created on first allocation)

No renames, deletions, or type changes. Existing data is unaffected.

---

## 9. Environment Injection

The app entry point (`TransitApp.swift`) wires up:

```
MilestoneService  ←  injected via .environment()
  ├── modelContext: container.mainContext
  └── displayIDAllocator: milestoneIDAllocator (separate instance)
```

Views access via `@Environment(MilestoneService.self)`.

MCP: `MCPToolHandler` receives `MilestoneService` in its initialiser.

App Intents: Use `@Dependency` injection, same as existing intents.
