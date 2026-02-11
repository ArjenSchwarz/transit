# Transit

Native iOS/iPadOS/macOS task tracker for agentic work.

## What is Transit?

Transit is a personal kanban-style task tracker built for a single user across Apple devices. It provides a dashboard for tracking tasks as they move through defined stages, with CLI integration via App Intents and a future path to AI agent integration via MCP.

Transit sits alongside the existing tool ecosystem: [Orbit](https://github.com/ArjenSchwarz/orbit) (orchestrator), Starwave (spec workflow), and other project-specific utilities.

## Features

- **Kanban dashboard** with 5 columns: Idea, Planning, Spec, In Progress, Done/Abandoned
- **Cross-device sync** via CloudKit private database
- **CLI automation** through App Intents (Create Task, Update Status, Query Tasks) — accepts and returns structured JSON
- **Agent handoff statuses** (Ready for Implementation, Ready for Review) for AI/human workflow integration
- **Adaptive layout**: single column on iPhone portrait, multi-column on landscape/iPad/Mac
- **Drag and drop** between columns to change task status
- **Liquid Glass** design language throughout

## Requirements

- iOS 26 / iPadOS 26 / macOS 26
- Xcode 26
- Swift 6.2

No backwards compatibility — this targets the latest Apple platforms exclusively.

## Building

```bash
make build        # Build for both iOS and macOS
make build-ios    # Build for iOS Simulator only
make build-macos  # Build for macOS only
make test-quick   # Run unit tests on macOS (fast)
make test         # Run full test suite on iOS Simulator
make lint         # Run SwiftLint
```

## CLI Usage

Transit exposes three App Intents accessible via the Shortcuts app or `shortcuts run` on the command line:

- **Transit: Create Task** — create a task with project, name, type, and optional description/metadata
- **Transit: Update Status** — move a task to a new status by display ID (e.g., T-42)
- **Transit: Query Tasks** — filter tasks by project, status, and/or type

All intents accept a JSON string input and return a JSON string response, including structured error codes (`TASK_NOT_FOUND`, `PROJECT_NOT_FOUND`, `AMBIGUOUS_PROJECT`, `INVALID_STATUS`, `INVALID_TYPE`).

## Documentation

- `specs/transit-v1/` — requirements, design, architecture, tasks, and decision log
- `docs/transit-design-doc.md` — full design document
- `docs/agent-notes/` — implementation notes on architecture and technical constraints
- `CLAUDE.md` — guidance for Claude Code when working in this repository
