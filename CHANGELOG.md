# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
