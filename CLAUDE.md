# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Transit?

Transit is a native Apple task tracker (iOS 26 / iPadOS 26 / macOS 26) for a single user. It provides a kanban-style dashboard for tracking tasks across projects, with CLI integration via App Intents and agent integration via a built-in MCP server (macOS). It sits alongside Orbit (orchestrator), Starwave (spec workflow), and other project tools.

## Tech Stack

- **Swift 6.2**, **SwiftUI**, targeting **iOS/iPadOS/macOS 26 exclusively** — no backwards compatibility
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** — every type is `@MainActor` by default (see gotchas below)
- **SwiftData** with **CloudKit** (private database) for cross-device sync
- **App Intents** framework for CLI/automation integration via Shortcuts
- **MCP server** (macOS only) — HTTP-based JSON-RPC server using Hummingbird, configurable port (default 3141)
- **Liquid Glass** design language: `.glassEffect()`, `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)`
- **Xcode File System Sync** enabled — Xcode auto-discovers files from disk, no need to edit pbxproj

## Build and Test Commands

Use the Makefile for all development tasks:

```bash
make build        # Build for both iOS and macOS
make build-ios    # Build for iOS Simulator only
make build-macos  # Build for macOS only
make test-quick   # Run unit tests on macOS (fast, no simulator)
make test         # Run full test suite on iOS Simulator
make test-ui      # Run UI tests only
make lint         # Run SwiftLint
make lint-fix     # Run SwiftLint with auto-fix
make clean        # Clean build artifacts
make install      # Build and install Debug on device
make run          # Build, install, and launch Debug on device
make archive      # Create xcarchive for iOS distribution
make upload       # Archive and upload to App Store Connect
```

To run a single test class or method:
```bash
xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TransitTests/StatusEngineTests test
```

### When to Run Which Tests

- **During development**: Use `make test-quick` — runs unit tests on macOS without the simulator, fast feedback loop
- **Before pushing (pre-push-review)**: Use `make test` and `make test-ui` — runs the full test suite on iOS Simulator
- **For commits**: No tests required — lint only (`make lint`)

## Architecture Overview

### Data Model

Four SwiftData entities:
- **Project** → has many **Tasks** and many **Milestones**
- **TransitTask** → belongs to one Project, optionally belongs to one Milestone, has many Comments
- **Milestone** → belongs to one Project, has many Tasks. Statuses: open / done / abandoned
- **Comment** → belongs to one Task. Has `authorName`, `isAgent` flag, and `content`

Both tasks and milestones have a UUID and a separate `permanentDisplayId` integer for human-facing use (T-1, M-3), allocated via CloudKit counter records with optimistic locking and provisional fallback when offline.

### Task Statuses (linear progression)

Idea → Planning → Spec → Ready for Implementation → In Progress → Ready for Review → Done / Abandoned

"Ready for Implementation" and "Ready for Review" are **agent handoff statuses** — they don't get their own kanban columns. They render within Spec and In Progress columns respectively, visually promoted to the top with an orange "Handoff" badge.

### Task Types

bug, feature, chore, research, documentation

### Kanban Dashboard (5 visual columns)

Idea | Planning | Spec | In Progress | Done/Abandoned

- Done/Abandoned is a combined column with a visual separator, showing only tasks from the last 48 hours (based on `completionDate`)
- Sort: `lastStatusChangeDate` descending within each column, with a toggle for "Organized" sort
- Cross-column drag changes status; no vertical reorder within columns
- Search bar supports name, description, and display ID matching (e.g. "T-42")
- Filter menus for project, type, and milestone

### Platform Layout

- **iPhone portrait**: segmented control, one column at a time (default: In Progress / "Active")
- **iPhone landscape**: three columns visible, swipeable
- **iPad/Mac**: all five columns visible

### Service Layer

All business logic lives in `Services/`, not in views:

- **StatusEngine** — pure logic for status transitions with `completionDate`/`lastStatusChangeDate` side effects
- **DisplayIDAllocator** — CloudKit counter with optimistic locking, provisional ID fallback when offline. Separate instances for tasks and milestones (different counter records).
- **TaskService** (`@MainActor @Observable`) — task CRUD, status changes, abandon/restore. Typed `Error` enum.
- **ProjectService** (`@MainActor @Observable`) — project CRUD, case-insensitive name lookup with ambiguity detection
- **MilestoneService** (`@MainActor @Observable`) — milestone CRUD, status changes, task assignment validation (project match), name uniqueness within project
- **CommentService** (`@MainActor @Observable`) — comment CRUD on tasks, resolves task references across contexts
- **SyncManager** — CloudKit sync preference via UserDefaults; toggle takes effect on next launch
- **ConnectivityMonitor** — NWPathMonitor wrapper, triggers display ID promotion for both tasks and milestones on connectivity restore

### Navigation

Single `NavigationStack` at app root in `TransitApp.swift`. `NavigationDestination` enum for type-safe routing: `.settings`, `.projectCreate`, `.projectEdit(Project)`, `.milestoneEdit(project:milestone:)`, `.report`, `.acknowledgments`, `.licenseText`.

On iOS, settings is pushed onto the root NavigationStack. On macOS, settings opens in a dedicated `Window` scene (Cmd+Comma) with sidebar navigation for sub-sections.

### App Intents

Intents exposed as Shortcuts, each accepting/returning structured JSON via `@Parameter(title: "Input") var input: String`:

- **CreateTaskIntent** — create task with optional milestone assignment
- **UpdateStatusIntent** — move task to new status with optional comment
- **QueryTasksIntent** — filter by project/status/type/milestone/search/date range
- **UpdateTaskIntent** — update task properties (milestone assignment)
- **CreateMilestoneIntent** — create milestone within a project
- **QueryMilestonesIntent** — filter milestones
- **UpdateMilestoneIntent** — update milestone name/description/status
- **DeleteMilestoneIntent** — delete milestone (nullifies task associations)
- **AddCommentIntent** — add comment to a task
- **GenerateReportIntent** — generate markdown report of completed/abandoned tasks

Error responses are JSON-encoded in the return string (not thrown) so CLI callers get parseable output. Error codes: `TASK_NOT_FOUND`, `PROJECT_NOT_FOUND`, `AMBIGUOUS_PROJECT`, `INVALID_STATUS`, `INVALID_TYPE`, `INVALID_INPUT`, `MILESTONE_NOT_FOUND`, `DUPLICATE_MILESTONE_NAME`, `MILESTONE_PROJECT_MISMATCH`, `INTERNAL_ERROR`.

**Visual intents** (in `Intents/Visual/`) use native App Intent entities and queries for Shortcuts UI integration: `AddTaskIntent`, `FindTasksIntent`.

Shared intent infrastructure lives in `Intents/Shared/`: entities (`ProjectEntity`, `TaskEntity`), app enums (`TaskStatusAppEnum`, `TaskTypeAppEnum`), and `IntentHelpers` for common JSON encoding and task-to-dict conversion.

### MCP Server (macOS only)

HTTP-based JSON-RPC 2.0 server using **Hummingbird**, gated behind `#if os(macOS)`. Configured via `MCPSettings` (UserDefaults-backed toggle and port). Exposes 10 tools:

`create_task`, `update_task_status`, `query_tasks`, `update_task`, `add_comment`, `get_projects`, `create_milestone`, `query_milestones`, `update_milestone`, `delete_milestone`

Key implementation files:
- `MCP/MCPServer.swift` — Hummingbird router, lifecycle management
- `MCP/MCPToolHandler.swift` — dispatches `tools/call` to service layer
- `MCP/MCPToolDefinitions.swift` — tool schemas with input validation
- `MCP/MCPTypes.swift` — JSON-RPC request/response types
- `MCP/MCPHelperTypes.swift` — query filter logic (`MCPQueryFilters`)

The MCP server reuses the same service instances as the UI (shared `mainContext`), so changes from MCP calls appear immediately in the app.

### Reports

`Reports/` contains logic for generating summary reports of completed/abandoned tasks within a date range:

- **ReportLogic** — filters terminal tasks/milestones by date range, groups by project
- **ReportData** / **ReportDateRange** — value types for report structure and date range options
- **ReportMarkdownFormatter** — renders report data as markdown

The in-app report view lives at `Views/Reports/ReportView.swift`.

Reports are also exposed via `GenerateReportIntent` for CLI/automation use.

### Theme System

Frosted Panels theme with four options: Follow System (default), Universal, Light, Dark. `BoardBackground` renders layered radial gradients behind the kanban board; columns and cards use frosted glass materials adapted per theme variant. Resolved theme is propagated via `@Environment(\.resolvedTheme)`.

## Key Technical Constraints

### SwiftData + CloudKit

- All relationships **must be optional** for CloudKit compatibility
- No `@Attribute(.unique)` with CloudKit
- Delete rules: `.cascade` or `.nullify` only
- Post-deployment migration is add-only (no renames, deletions, or type changes)
- `#Predicate` cannot query optional to-many relationships — query from the child side or filter in-memory

### SwiftData Save/Rollback Pattern

Services follow a consistent pattern: mutate in memory, then `save()`, rolling back on failure via `modelContext.safeRollback()` (extension in `Extensions/ModelContext+SafeRollback.swift`). For creation operations, the object is deleted on save failure instead of rolling back, because `safeRollback()` does not re-fault `@Model` properties reliably (see T-452).

### Swift 6 Default MainActor Isolation

- Every type is `@MainActor` by default. `@Model` classes are the exception — they follow standard isolation.
- `Codable` conformance on enums triggers `@MainActor` isolation. Avoid `Codable` on pure data enums unless needed.
- Color extensions using `UIColor`/`NSColor` become `@MainActor` isolated. Use `Color.resolve(in: EnvironmentValues())` instead.
- `@Model` inits should take raw stored types (`colorHex: String`), not SwiftUI types (`Color`).
- Test files must explicitly `import Foundation` and use `@MainActor` annotation.

### Liquid Glass

- Primary modifier: `.glassEffect(_:in:isEnabled:)` with variants `.regular`, `.clear`, `.identity`
- There is **no** `.materialBackground()` modifier
- Use `GlassEffectContainer` for grouping multiple glass elements
- Glass is for the navigation/control layer only, not for content

## Test Infrastructure

- **Swift Testing** framework (not XCTest) for unit tests
- **TestModelContainer** singleton (`TransitTests/TestModelContainer.swift`) — shared in-memory container with `cloudKitDatabase: .none` and explicit `Schema` including all four models. All three properties (schema, in-memory, no CloudKit) are required to avoid conflicts.
- Each test gets a fresh `ModelContext` via `TestModelContainer.newContext()`
- SwiftData test suites must use `@Suite(.serialized)` to prevent concurrent access issues
- UI tests use `TRANSIT_UI_TEST_SCENARIO` environment variable (`empty` or `board`) for deterministic seeded data
- MCP tool handler tests use `MCPTestHelpers.swift` for common setup patterns

## Key Design Decisions

- No task dependencies, no priority field, no full status history in V1
- New tasks always start in Idea status
- Abandoned tasks restore to Idea (not previous status)
- Filter state is ephemeral (resets on launch)
- Project picker uses native dropdown/menu (not chips or searchable list)
- Free-form `[String: String]` metadata on tasks with reserved namespace prefixes: `git.`, `ci.`, `agent.`
- Milestones are scoped to a project; names must be unique within a project (case-insensitive)
- Milestone assignment validates project match — task and milestone must belong to the same project
- Comments have an `isAgent` flag to distinguish human vs agent-authored comments
- MCP `update_task_status` supports atomic status change + comment in a single operation

## Reference Files

- `specs/transit-v1/` — requirements, design, tasks, decision log, and implementation notes
- `docs/transit-design-doc.md` — full design document with data model, UI specs, intent schemas
- `docs/transit-ui-mockup.jsx` — React-based interactive mockup (reference only, not production)
- `docs/agent-notes/` — implementation notes on architecture, constraints, and patterns
