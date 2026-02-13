# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- macOS Liquid Glass form layout for all form/settings views using `Grid` + `FormRow` + `LiquidGlassSection` components, replacing standard `Form`/`List` on macOS while keeping iOS layouts unchanged
- `FormRow` reusable component (`Views/Shared/FormRow.swift`) — right-aligned label + content column in a `GridRow` with `.frame(maxWidth: .infinity, alignment: .leading)` for consistent left-alignment
- `LiquidGlassSection` reusable component (`Views/Shared/LiquidGlassSection.swift`) — `VStack` with headline title and `.glassEffect(.regular, in:)` background container
- Smolspec and task list for macOS Liquid Glass forms feature (`specs/macos-liquid-glass-forms/`)

### Changed

- Project lists are now alphabetically sorted by name in all views: settings, filter popover, add task picker, and edit task picker

- `TaskEditView` macOS layout uses `ScrollView` > `VStack` > `LiquidGlassSection` > `Grid` + `FormRow` for fields, with bottom-right Save button
- `TaskDetailView` macOS layout uses the same pattern for read-only detail display with glass sections for details, description, metadata, and actions
- `AddTaskSheet` macOS layout uses glass sections for task fields and type picker
- `ProjectEditView` macOS layout uses glass sections for project details and appearance (ColorPicker)
- `SettingsView` macOS layout replaces `List` with glass sections for appearance, MCP server, projects, and general settings
- `MetadataSection` now platform-adaptive: iOS wraps content in `Section("Metadata")` for Form/List compatibility; macOS emits bare content for caller to wrap in `LiquidGlassSection`

- `displayId` parameter on `QueryTasksIntent` for single-task lookup via `FetchDescriptor` predicate
- Detailed response fields (`description`, `metadata`) in `QueryTasksIntent` when querying by `displayId`
- 3 new `QueryTasksIntentTests` covering displayId lookup with detailed output, not-found returning empty array, and displayId with non-matching filter
- Smolspec and task list for App Intent displayId filter feature (`specs/intent-displayid-filter/`)
- `displayId` parameter on `query_tasks` MCP tool for single-task lookup via predicate-based fetch
- Detailed response fields (`description`, `metadata`) included when querying by `displayId`
- Conjunctive filter composition: `displayId` works alongside `status`, `type`, and `projectId` filters
- 6 new MCP tool handler tests covering displayId lookup, not-found, filter composition, and response field presence
- Smolspec and task list for MCP task ID filter feature (`specs/mcp-task-id-filter/`)
- `MCPTestHelpers` shared test utility with environment setup and JSON-RPC response decoding helpers, used by both `MCPToolHandlerTests` and `MCPToolHandlerDisplayIdTests`
- Embedded MCP server (macOS only) using Hummingbird HTTP framework, exposing `create_task`, `update_task_status`, and `query_tasks` tools via Streamable HTTP transport (JSON-RPC 2.0 over `POST /mcp`)
- MCP Settings section in Settings view (macOS) with enable toggle, port configuration, running status indicator, and copyable `claude mcp add` setup command
- `MCPTypes.swift` with full JSON-RPC 2.0 and MCP protocol Codable types
- `MCPToolHandler` bridging MCP tool calls to existing `TaskService` and `ProjectService`
- `MCPServer` managing Hummingbird lifecycle with localhost-only binding (127.0.0.1)
- `MCPSettings` observable class for per-machine UserDefaults-backed preferences (enabled, port)
- 17 unit tests for MCP tool handler covering all three tools, error cases, and protocol methods
- Network server and client entitlements for macOS App Sandbox
- Hummingbird 2.x as first external SPM dependency
- Implementation plan and agent notes for MCP server architecture

### Fixed

- MCP tool handler tests now handle optional `JSONRPCResponse?` return type from `handle()`, preventing compilation errors
- `QueryTasksIntentTests.responseContainsAllRequiredFields` no longer asserts `completionDate` key is present for tasks without a completion date
- MCP server `isRunning` state now correctly resets to `false` when the server fails to bind or stops unexpectedly, preventing the Settings UI from showing a stale "Running" status
- Removed unused `[weak self]` capture in `MCPServer.start()` detached task

### Fixed

- macOS toolbar background is now transparent, allowing the BoardBackground gradient to bleed through to the top of the window matching iOS Liquid Glass behaviour

### Added

- Share button on task detail view toolbar for copying task details as formatted markdown text (display ID, title, type, project, description, metadata)
- `TransitTask.shareText` computed property for generating shareable markdown representation
- `ShareTextTests` suite (8 tests) covering header formatting, provisional display IDs, project name, description inclusion/omission, metadata sorting, and full format validation

### Changed

- `DisplayID.formatted` marked `nonisolated` to allow use from non-MainActor contexts (e.g. `@Model` computed properties)

### Fixed

- `AddTaskSheet` build failure on macOS caused by `PersistentModel` (`Project`, `TransitTask`) being captured in a `@Sendable` `Task {}` closure. Replaced `Project` capture with UUID and explicitly discarded the `TransitTask` return value.
- `AddTaskSheet` task creation failing at runtime because `registeredModel(for:)` returns `nil` when the project was fetched by a different `ModelContext`. Changed `TaskService.createTask(projectID:)` to use `FetchDescriptor` with UUID predicate instead of `PersistentIdentifier` lookup.
- Claude Code Review workflow missing `pull-requests: write` permission, preventing the action from posting review comments on PRs

### Added

- Visual `AddTaskIntent` now supports optional metadata input as comma-separated `key=value` pairs (for example: `priority=high,source=shortcut`) and persists it on created tasks.
- Metadata-focused coverage for visual task creation:
  - `AddTaskIntentTests` now verifies valid metadata parsing and malformed metadata rejection.
  - `AddTaskIntentIntegrationTests` now verifies persisted metadata values end-to-end.
- `IntentCompatibilityAndDiscoverabilityTests` regression suite to lock Shortcuts discoverability and backward-compatibility contracts:
  - intent title stability for legacy and visual intents
  - shortcut provider registration count for all five intents
  - JSON output contract checks for `CreateTaskIntent`, `UpdateStatusIntent`, and non-date `QueryTasksIntent`
- Visual `FindTasksIntent` (`Transit: Find Tasks`) with optional Shortcuts filters for type, project, status, completion date, and last status change date
- Custom-range date filtering UI for `FindTasksIntent` via nested `ParameterSummary` `When` clauses, including conditional from/to date fields
- `FindTasksIntent` test coverage:
  - `FindTasksIntentTests` for AND-filter logic, custom date ranges, 200-result cap, sort order, empty results, and invalid range validation
  - `FindTasksIntentIntegrationTests` for end-to-end `TaskEntity` field mapping and empty-match behavior
- `FindTasksIntent` registration in `TransitShortcuts` with dedicated phrases and icon for Shortcuts discoverability
- Visual `AddTaskIntent` (`Transit: Add Task`) with native Shortcuts parameters for name, optional description, task type, and project selection
- `TaskCreationResult` shared intent return type (plus query support) carrying `taskId`, `displayId`, `status`, `projectId`, and `projectName` for structured Shortcuts output
- New automated coverage for visual task creation:
  - `TaskCreationResultTests` for mapping and data-integrity error handling
  - `AddTaskIntentTests` for validation, no-project handling, stale project selection, and task creation behavior
  - `AddTaskIntentIntegrationTests` for end-to-end persistence and query visibility
- Dedicated `QueryTasksIntentDateFilterTests` suite covering relative/absolute date filters, precedence rules, invalid date input handling, and legacy non-date query compatibility
- Orbit session data (variant comparison, consolidation reports, human-readable transcripts) tracked in git for documentation
- Shared Shortcuts intent infrastructure for `shortcuts-friendly-intents` phase 1:
  - `TaskStatus` and `TaskType` `AppEnum` conformances for reusable Shortcuts dropdown display values
  - `VisualIntentError` with `LocalizedError` messaging and stable visual-intent error codes
  - `ProjectEntity`/`ProjectEntityQuery` and `TaskEntity`/`TaskEntityQuery` for AppEntity-backed selection and lookup
  - `DateFilterHelpers` utility for relative/absolute date range parsing with inclusive boundary checks
  - New unit test coverage for all of the above shared intent components

### Changed

- Completed `shortcuts-friendly-intents` Integration and Verification phase tasks in `specs/shortcuts-friendly-intents/tasks.md` after running strict linting and full `TransitTests` verification.
- `TaskEntityQuery` now pre-sizes UUID sets and output arrays and uses iterative filtering to reduce transient allocations on entity resolution paths
- `QueryTasksIntent` now decodes typed JSON filters with codable date-range support for `completionDate` and `lastStatusChangeDate` (`relative` or `from`/`to`)
- Date-filter validation now rejects malformed date ranges with an `INVALID_INPUT` error before query execution
- Query filtering now runs in a single pass with reserved result capacity to reduce intermediate array allocations
- `DateFilterHelpers` now supports direct `relative`/`from`/`to` parsing in addition to dictionary-based parsing
- `CLAUDE.md` rewritten to reflect current architecture: added service layer, navigation pattern, theme system, SwiftData+CloudKit constraints, Swift 6 MainActor isolation gotchas, Liquid Glass constraints, and test infrastructure details; removed incorrect `.materialBackground()` reference
- `README.md` expanded from stub to full project documentation with features, requirements, build commands, CLI usage, and documentation pointers
- `.gitignore` updated to selectively allow `.orbit` directories while blocking cost/billing data, raw API logs, and working trees
- `QueryTasksIntent` now always includes a `completionDate` key in each task JSON object (`null` when absent) for a stable response schema
- `TestModelContainer.newContext()` now creates an isolated in-memory SwiftData container per context to prevent cross-suite data leakage in tests

### Added

- Frosted Panels theme system with four options: Follow System (default), Universal, Light, and Dark
- `AppTheme` and `ResolvedTheme` enums for theme preference storage and resolution
- `BoardBackground` view rendering layered radial gradients (indigo, pink, teal, purple) behind the kanban board, adapted per theme variant
- Theme picker in Settings → Appearance section
- Frosted glass panel backgrounds on kanban columns with rounded corners, material fills, and subtle borders per theme
- Top-edge accent stripe (2.5pt, project colour) on task cards replacing the full project-colour border
- Theme-aware card styling with adapted materials, borders, and shadows per variant

### Changed

- Task cards no longer use `.glassEffect(.regular)` and `.regularMaterial`; replaced with layered frosted materials on a colourful gradient background
- Column headers now have a divider separator below them

### Fixed

- Newly created projects now appear immediately in the settings list and project picker instead of waiting 10-30 seconds for SwiftData's background auto-save

### Changed

- Settings button moved from overflow menu (`.secondaryAction`) to always-visible toolbar placement (`.primaryAction`) with `ToolbarSpacer` separating it from filter/add buttons into its own Liquid Glass pill on macOS/iPad
- Navigation title display mode set to `.inline` so the title sits in the toolbar bar instead of taking a separate row on iOS
- Filter popover on iPhone now presents as a half-height bottom sheet with drag indicator instead of a full-screen takeover

### Changed

- Toolbar buttons in AddTaskSheet, TaskEditView, ProjectEditView, and TaskDetailView now use iOS 26 Liquid Glass styling: chevron.left icon for cancel/dismiss, checkmark icon with automatic `.glassProminent` for save/confirm actions
- ProjectEditView hides the system back button when editing (pushed navigation) to avoid duplicate chevrons
- TaskEditView status picker now shows human-readable display names instead of slugified raw values (e.g. "Ready for Implementation" instead of "ready-for-implementation")

### Added

- `TaskStatus.displayName` computed property with human-readable names for all statuses

### Fixed

- Saving a task edit now dismisses both the edit and detail sheets simultaneously, returning directly to the dashboard instead of briefly showing the detail view
- Drag-and-drop on iPhone now works for all columns (was only accepting drops on Planning and Done)
- `ColumnView` missing `.contentShape(.rect)` caused drop targets to not cover full column frame when containing Spacers or ScrollViews
- `KanbanBoardView` scroll behaviour changed from `.paging` to `.viewAligned` with `.scrollTargetLayout()` for column-by-column auto-scroll during drag operations
- `SingleColumnView` segmented control now accepts drops via ZStack overlay with per-segment drop targets, enabling cross-column drag on iPhone portrait
- Added `isTargeted` visual feedback (tint highlight) to column drop targets
- Added parameterized regression test verifying drops succeed for all 5 dashboard columns

### Added

- `IntentDescription` with category and result labels for all three App Intents (CreateTask, UpdateStatus, QueryTasks), visible in the Shortcuts gallery
- Parameter descriptions on each intent documenting required/optional JSON fields, valid enum values, and usage examples
- `TransitShortcuts` `AppShortcutsProvider` registering all intents with Siri phrases and icons for Shortcuts app discoverability

### Fixed

- Add missing `import SwiftData` in `ProjectEditView` that caused build failure
- Add explicit `modelContext.save()` in `TaskEditView` and `ProjectEditView` after direct property mutations to prevent data loss on app termination before SwiftData auto-save
- TaskDetailView now shows Abandon button for Done tasks (was hidden because `isTerminal` excluded both Done and Abandoned; spec [req 4.5] requires abandon from any status including Done)

### Added

- Implementation explanation document (`specs/transit-v1/implementation.md`) with beginner/intermediate/expert level explanations, requirement traceability, and completeness assessment

- UI tests (12 tests) covering navigation flows (settings push, back chevron), sheet presentation (add task, task detail, filter popover), empty states (dashboard, settings), default segment selection, filter badge updates, and abandoned task visibility
- Integration tests (12 tests) verifying end-to-end flows: intent-created tasks appear in dashboard columns, status updates via intent move tasks between columns, query intent returns filtered results, display ID counter increments across creates, and query response field validation
- UI test infrastructure: `--uitesting` launch argument for in-memory SwiftData storage, `--uitesting-seed-data` for test data seeding with sample tasks (including abandoned task)

- `DashboardView` with GeometryReader-based adaptive layout switching (single column vs kanban), column filtering/sorting, project filter, toolbar, and global empty state
- `TaskCardView` with `.glassEffect()`, project colour border, display ID, type badge, strikethrough for abandoned tasks, and `.draggable()` support
- `ColumnView` with header (name + count), done/abandoned separator, per-column empty state, and `.dropDestination()` for drag-and-drop
- `KanbanBoardView` multi-column horizontal scrolling board with paging and initial scroll target for iPhone landscape
- `SingleColumnView` with segmented control (short labels, task counts, default Active segment)
- `FilterPopoverView` with multi-select project checkboxes and Clear action
- Drag-and-drop between columns applying `DashboardColumn.primaryStatus` via `TaskService`
- Dashboard column filtering unit tests (10 tests: 48-hour cutoff, handoff sorting, done-before-abandoned, project filter, nil project exclusion)
- Drag-and-drop status mapping unit tests (10 tests: base status per column, Done not Abandoned, backward drag, completionDate handling)
- Agent notes for dashboard view architecture

- `StatusEngine` struct with `initializeNewTask` and `applyTransition` for centralised status transition logic with completionDate/lastStatusChangeDate side effects
- `DisplayIDAllocator` with CloudKit counter-based sequential ID allocation, optimistic locking, retry logic, and provisional ID fallback for offline support
- `TaskService` (`@MainActor @Observable`) for task creation, status updates, abandon, restore, and display ID lookup
- `ProjectService` (`@MainActor @Observable`) for project creation, case-insensitive name lookup with ambiguity detection, and active task counting
- `ProjectLookupError` enum (notFound, ambiguous, noIdentifier) for project resolution errors
- `IntentError` enum with 6 error codes (TASK_NOT_FOUND, PROJECT_NOT_FOUND, AMBIGUOUS_PROJECT, INVALID_STATUS, INVALID_TYPE, INVALID_INPUT) and JSON encoding via JSONSerialization
- `EmptyStateView` reusable component using `ContentUnavailableView`
- `ProjectColorDot` view (12x12 rounded square with project colour)
- `TypeBadge` capsule-shaped tinted badge for task type display
- `MetadataSection` view with read/edit modes for key-value metadata pairs
- `TaskType.tintColor` computed property with distinct colours per type
- `TestModelContainer` shared singleton for SwiftData test isolation with `cloudKitDatabase: .none`
- StatusEngine unit tests (12 tests including property-based transition invariants)
- DisplayIDAllocator tests (5 tests for provisional IDs and promotion sort order)
- TaskService tests (9 tests covering creation, status changes, abandon/restore, and lookups)
- ProjectService tests (10 tests covering creation, find by ID/name, ambiguity, and active count)
- IntentError tests (12 tests covering error codes, JSON structure, and special character escaping)
- Agent notes for services layer, shared components, SwiftData test container pattern, and test imports

- `TaskStatus` enum with column mapping, handoff detection, terminal state checks, and short labels for iPhone segmented control
- `DashboardColumn` enum with display names and primary status mapping for drag-and-drop
- `TaskType` enum (bug, feature, chore, research, documentation)
- `DisplayID` enum with formatted property (`T-42` for permanent, `T-•` for provisional)
- `Color+Codable` extension for hex string conversion using `Color.Resolved` (avoids UIColor/NSColor actor isolation in Swift 6)
- `Date+TransitHelpers` extension with 48-hour window computation for Done/Abandoned column filtering
- `Project` SwiftData model with optional relationship to tasks, CloudKit-compatible fields, and hex color storage
- `TransitTask` SwiftData model with computed status/type properties, DisplayID support, JSON-encoded metadata, and creationDate
- Unit tests for TaskStatus column mapping, isHandoff, isTerminal, shortLabel, DashboardColumn.primaryStatus, and raw values (19 tests)
- Unit tests for DisplayID formatting and equality (7 tests)
- Agent notes on Swift 6 default MainActor isolation constraints

- Design document (v0.3 draft) covering data model, UI specs, App Intents schemas, platform layouts, and decision log
- Interactive React-based UI mockup for layout and interaction reference
- CLAUDE.md with project architecture overview for Claude Code
- Claude Code project settings with SessionStart hook
- Requirements specification (20 sections in EARS format) covering data models, dashboard, views, App Intents, CloudKit sync, and empty states
- Code architecture design document covering module structure, protocols, data flow, SwiftData models, domain services, view hierarchy, and App Intents integration
- Decision log with 20 architectural decisions (optional relationships, creationDate field, openAppWhenRun, sync toggle, drag-to-column base status, and more)
- Implementation task list (50 tasks across 3 work streams and 10 phases) with dependencies and requirement traceability
- Prerequisites document for Xcode project setup and CloudKit configuration
- Agent notes on technical constraints (SwiftData+CloudKit, Liquid Glass, drag-and-drop, adaptive layout)
- Xcode project with multiplatform SwiftUI target (iOS 26, macOS 26), CloudKit entitlements, and background modes
- Makefile with build, test, lint, device deployment, and clean targets
- Testing strategy in CLAUDE.md (test-quick during development, full suite before pushing)
- Project directory structure matching design doc: Models/, Services/, Views/ (Dashboard, TaskDetail, AddTask, Settings, Shared), Intents/, Extensions/
- Minimal TransitApp entry point with NavigationStack and DashboardView as root
- SwiftLint configuration excluding DerivedData auto-generated files
- Agent notes documenting project structure and build workflow

### Changed

- Swift language version set to 6.0 across all targets for strict concurrency checking

### Removed

- Xcode template files (Item.swift, ContentView.swift) replaced with Transit-specific scaffolding
