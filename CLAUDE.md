# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Transit?

Transit is a native Apple task tracker (iOS 26 / iPadOS 26 / macOS 26) for a single user. It provides a kanban-style dashboard for tracking tasks across projects, with CLI integration via App Intents and a future path to MCP agent integration. It sits alongside Orbit (orchestrator), Starwave (spec workflow), and other project tools.

## Tech Stack

- **Swift 6.2**, **SwiftUI**, targeting **iOS/iPadOS/macOS 26 exclusively** — no backwards compatibility
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** — every type is `@MainActor` by default (see gotchas below)
- **SwiftData** with **CloudKit** (private database) for cross-device sync
- **App Intents** framework for CLI/automation integration via Shortcuts
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

Two SwiftData entities with a one-to-many relationship:
- **Project** → has many **Tasks**. A Task belongs to exactly one Project.
- Tasks have a UUID (CloudKit record ID) and a separate `displayId` integer (T-1, T-42) for human-facing use, allocated via a CloudKit counter record with optimistic locking.

### Task Statuses (linear progression)

Idea → Planning → Spec → Ready for Implementation → In Progress → Ready for Review → Done / Abandoned

"Ready for Implementation" and "Ready for Review" are **agent handoff statuses** — they don't get their own kanban columns. They render within Spec and In Progress columns respectively, visually promoted to the top with an orange "Handoff" badge.

### Kanban Dashboard (5 visual columns)

Idea | Planning | Spec | In Progress | Done/Abandoned

- Done/Abandoned is a combined column with a visual separator, showing only tasks from the last 48 hours (based on `completionDate`)
- Sort: `lastStatusChangeDate` descending within each column
- Cross-column drag changes status; no vertical reorder within columns

### Platform Layout

- **iPhone portrait**: segmented control, one column at a time (default: In Progress / "Active")
- **iPhone landscape**: three columns visible, swipeable
- **iPad/Mac**: all five columns visible

### Service Layer

All business logic lives in `Services/`, not in views:

- **StatusEngine** — pure logic for status transitions with `completionDate`/`lastStatusChangeDate` side effects
- **DisplayIDAllocator** — CloudKit counter with optimistic locking, provisional ID fallback when offline
- **TaskService** (`@MainActor @Observable`) — task CRUD, status changes, abandon/restore. Typed `Error` enum.
- **ProjectService** (`@MainActor @Observable`) — project CRUD, case-insensitive name lookup with ambiguity detection
- **SyncManager** — CloudKit sync preference via UserDefaults; toggle takes effect on next launch
- **ConnectivityMonitor** — NWPathMonitor wrapper, triggers display ID promotion on connectivity restore

### Navigation

Single `NavigationStack` at app root in `TransitApp.swift`. `NavigationDestination` enum (`.settings`, `.projectEdit(Project)`) for type-safe routing. Settings is pushed, not a sheet or tab.

### App Intents

Three intents exposed as Shortcuts: `Transit: Create Task`, `Transit: Update Status`, `Transit: Query Tasks`. All accept/return structured JSON via a single `@Parameter(title: "Input") var input: String`. Error responses are JSON-encoded in the return string (not thrown) so CLI callers get parseable output.

Error codes: `TASK_NOT_FOUND`, `PROJECT_NOT_FOUND`, `AMBIGUOUS_PROJECT`, `INVALID_STATUS`, `INVALID_TYPE`.

### Theme System

Frosted Panels theme with four options: Follow System (default), Universal, Light, Dark. `BoardBackground` renders layered radial gradients behind the kanban board; columns and cards use frosted glass materials adapted per theme variant.

## Key Technical Constraints

### SwiftData + CloudKit

- All relationships **must be optional** for CloudKit compatibility
- No `@Attribute(.unique)` with CloudKit
- Delete rules: `.cascade` or `.nullify` only
- Post-deployment migration is add-only (no renames, deletions, or type changes)
- `#Predicate` cannot query optional to-many relationships — query from the child side or filter in-memory

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
- **TestModelContainer** singleton (`TransitTests/TestModelContainer.swift`) — shared in-memory container with `cloudKitDatabase: .none` and explicit `Schema`. All three properties (schema, in-memory, no CloudKit) are required to avoid conflicts.
- Each test gets a fresh `ModelContext` via `TestModelContainer.newContext()`
- SwiftData test suites must use `@Suite(.serialized)` to prevent concurrent access issues
- UI tests use `--uitesting` launch argument for in-memory storage and `--uitesting-seed-data` for deterministic test data

## Key Design Decisions

- No task dependencies, no priority field, no full status history in V1
- New tasks always start in Idea status
- Abandoned tasks restore to Idea (not previous status)
- Filter state is ephemeral (resets on launch)
- Project picker uses native dropdown/menu (not chips or searchable list)
- Free-form `[String: String]` metadata on tasks with reserved namespace prefixes: `git.`, `ci.`, `agent.`

## Reference Files

- `specs/transit-v1/` — requirements, design, tasks, decision log, and implementation notes
- `docs/transit-design-doc.md` — full design document with data model, UI specs, intent schemas
- `docs/transit-ui-mockup.jsx` — React-based interactive mockup (reference only, not production)
- `docs/agent-notes/` — implementation notes on architecture, constraints, and patterns
