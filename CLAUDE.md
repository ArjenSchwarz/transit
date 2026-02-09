# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Transit?

Transit is a native Apple task tracker (iOS 26 / iPadOS 26 / macOS 26) for a single user. It provides a kanban-style dashboard for tracking tasks across projects, with CLI integration via App Intents and a future path to MCP agent integration. It sits alongside Orbit (orchestrator), Starwave (spec workflow), and other project tools.

## Tech Stack

- **Swift 6.2**, **SwiftUI**, targeting **iOS/iPadOS/macOS 26 exclusively** — no backwards compatibility
- **CloudKit** (private database) for cross-device sync
- **App Intents** framework for CLI/automation integration via Shortcuts
- Liquid Glass design language throughout (`.glassEffect()`, `.materialBackground()`)

## Build & Development

No Xcode project exists yet. When the project is created:
- Use Xcode or `xcodebuild` for building
- If a `Makefile` is added, its commands take precedence for all development tooling

## Architecture Overview

### Data Model

Two entities with a one-to-many relationship:
- **Project** → has many **Tasks**. A Task belongs to exactly one Project.
- Tasks have a UUID (CloudKit record ID) and a separate `displayId` integer (T-1, T-42) for human-facing use, allocated via a CloudKit counter record with optimistic locking.

### Task Statuses (linear progression)

Idea → Planning → Spec → Ready for Implementation → In Progress → Ready for Review → Done / Abandoned

"Ready for Implementation" and "Ready for Review" are **agent handoff statuses** — they don't get their own kanban columns. They render within Spec and In Progress columns respectively, visually promoted to the top.

### Task Types (hardcoded)

Bug, Feature, Chore, Research, Documentation

### Kanban Dashboard (5 visual columns)

Idea | Planning | Spec | In Progress | Done/Abandoned

- Done/Abandoned is a combined column with a visual separator, showing only tasks from the last 48 hours (based on `completionDate`)
- Sort: `lastStatusChangeDate` descending within each column
- Cross-column drag changes status; no vertical reorder within columns

### Platform Layout

- **iPhone portrait**: segmented control, one column at a time (default: In Progress / "Active")
- **iPhone landscape**: three columns visible, swipeable
- **iPad/Mac**: all five columns visible

### App Intents (V1)

Three intents exposed as Shortcuts: `Transit: Create Task`, `Transit: Update Status`, `Transit: Query Tasks`. All accept/return structured JSON. Intents support both `projectId` (UUID, preferred) and `project` (name, fallback) for project references. Tasks are referenced by `displayId`.

Error responses use consistent structured format with error codes: `TASK_NOT_FOUND`, `PROJECT_NOT_FOUND`, `AMBIGUOUS_PROJECT`, `INVALID_STATUS`, `INVALID_TYPE`.

### Metadata

Free-form `[String: String]` on tasks. Reserved namespace prefixes by convention: `git.`, `ci.`, `agent.`.

### Sync

CloudKit private database, last-write-wins conflict resolution. Multiple writers (UI, CLI, future MCP) are possible but conflicts are low-stakes for single-user.

## Key Design Decisions

- No task dependencies, no priority field, no full status history in V1
- New tasks always start in Idea status
- Abandoned tasks restore to Idea (not previous status)
- Filter state is ephemeral (resets on launch)
- Navigation: single-screen with dashboard as root; Settings is a pushed view, not a tab
- Project picker uses native dropdown/menu (not chips or searchable list)

## Reference Files

- `docs/transit-design-doc.md` — full design document with data model, UI specs, intent schemas, and decision log
- `docs/transit-ui-mockup.jsx` — React-based interactive mockup of the UI layout (reference only, not for production; native implementation uses SwiftUI with actual Liquid Glass materials)
