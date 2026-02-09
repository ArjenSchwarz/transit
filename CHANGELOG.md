# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

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
