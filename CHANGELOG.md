# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Domain service implementations for `StatusEngine`, `DisplayIDAllocator`, `TaskService`, and `ProjectService` covering task lifecycle transitions, display ID allocation/retry, project lookup, and active task counting
- New unit test coverage for domain services with in-memory SwiftData test support, including property-based status transition invariants and allocator conflict/promotion scenarios
- Dashboard scaffolding entry point with a dedicated `DashboardView` under the new `Views/Dashboard` structure to establish the base app module layout
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
- Core data model primitives for Transit domain state: `TaskStatus`, `DashboardColumn`, `TaskType`, and `DisplayID`
- SwiftData model definitions for `Project` and `TransitTask` with CloudKit-compatible storage fields and optional relationships
- `Color` hex serialization helpers and `Date` helper for 48-hour window checks used by dashboard terminal-task filtering
- Unit test coverage for status/column behavior and display ID formatting

### Changed

- Updated `Color.hexString` conversion to match the current SDK `getRed` API behavior during platform color extraction
- Replaced template SwiftData sample app code with Transit-specific startup flow and minimal smoke tests for unit and UI targets
- Restricted all targets to iOS/iPadOS/macOS supported platforms (removed visionOS/xr platform settings) to align with V1 scope
- Swift language version set to 6.0 across all targets for strict concurrency checking
- Updated model helper implementations to work with Swift 6 default main-actor isolation while keeping enum/value helpers callable from nonisolated test and domain contexts
