# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- UpdateStatusIntent for CLI/Shortcuts status updates with JSON input parsing, displayId lookup, status validation, and transition via TaskService
- QueryTasksIntent for CLI/Shortcuts task queries with optional filters (status, projectId, type), SwiftData predicate building, and JSON array response
- TaskService.queryTasks method for filtered task queries from intents
- Comprehensive test suites for CreateTaskIntent, UpdateStatusIntent, and QueryTasksIntent covering happy paths and error cases
- App Intents foundation: IntentError enum with JSON encoding for structured error responses (TASK_NOT_FOUND, PROJECT_NOT_FOUND, AMBIGUOUS_PROJECT, INVALID_STATUS, INVALID_TYPE, INVALID_INPUT)
- CreateTaskIntent for CLI/Shortcuts task creation with JSON input parsing, project resolution (by UUID or name), type validation, and task creation in Idea status
- TransitServices singleton for sharing TaskService and ProjectService instances with App Intents
- ProjectService.findProjectForIntent method for intent-specific project lookup with Result<Project, IntentError> return type
- IntentError comprehensive test suite covering all error codes, JSON structure validation, and special character escaping
- App integration: TransitApp entry point with CloudKit-enabled ModelContainer, service instantiation and environment injection, connectivity monitoring with NWPathMonitor, provisional task promotion triggers (app launch, foreground, connectivity restore)
- Settings UI: SettingsView with Projects section (color swatch, name, active task count, add button) and General section (About, iCloud Sync toggle), ProjectEditView for creating and editing projects with color picker
- Task management UI: AddTaskSheet for creating tasks with validation, TaskDetailView for viewing task details with Abandon/Restore actions, TaskEditView for editing all task fields including status and metadata
- Dashboard UI components: TaskCardView with glass effect and project color border, ColumnView with header and done/abandoned separator, KanbanBoardView for multi-column layout, SingleColumnView with segmented control, FilterPopoverView for project filtering, and DashboardView with adaptive layout switching
- Drag-and-drop support between columns with status mapping and completionDate handling
- Unit tests for dashboard column filtering, 48-hour cutoff, sorting logic, project filter, and drag-and-drop status transitions
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

### Changed

- Swift language version set to 6.0 across all targets for strict concurrency checking
