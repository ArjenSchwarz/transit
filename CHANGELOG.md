# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

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
