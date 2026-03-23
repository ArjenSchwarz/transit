# Transit

Native iOS/iPadOS/macOS task tracker for agentic work.

## What is Transit?

Transit is a personal kanban-style task tracker built for a single user across Apple devices. It provides a dashboard for tracking tasks as they move through defined stages, with CLI integration via App Intents and AI agent integration via a built-in MCP server.

Transit sits alongside the existing tool ecosystem: [Orbit](https://github.com/ArjenSchwarz/orbit) (orchestrator), Starwave (spec workflow), and other project-specific utilities.

## Features

- **Kanban dashboard** with 5 columns: Idea, Planning, Spec, In Progress, Done/Abandoned
- **Milestones** — group tasks within a project, track milestone status (open/done/abandoned)
- **Comments** — threaded comments on tasks with agent/human distinction
- **Reports** — generate summary reports of completed/abandoned tasks by date range
- **Cross-device sync** via CloudKit private database
- **CLI automation** through App Intents — create tasks, update statuses, manage milestones, add comments, generate reports
- **MCP server** (macOS) — HTTP JSON-RPC server for AI agent integration with 10 tools
- **Agent handoff statuses** (Ready for Implementation, Ready for Review) for AI/human workflow integration
- **Adaptive layout**: single column on iPhone portrait, multi-column on landscape/iPad/Mac
- **Drag and drop** between columns to change task status
- **Search and filter** — by project, type, milestone, status, and text (including display ID matching)
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
make install      # Build and install on device
make archive      # Create xcarchive for distribution
make upload       # Archive and upload to App Store Connect
```

## CLI Usage

Transit exposes App Intents accessible via the Shortcuts app or `shortcuts run` on the command line:

- **Transit: Create Task** — create a task with project, name, type, and optional description/metadata/milestone
- **Transit: Update Status** — move a task to a new status by display ID (e.g., T-42), with optional comment
- **Transit: Query Tasks** — filter tasks by project, status, type, milestone, and/or search text
- **Transit: Create Milestone** — create a milestone within a project
- **Transit: Query Milestones** — list milestones with optional filters
- **Transit: Update Milestone** — update milestone name, description, or status
- **Transit: Delete Milestone** — delete a milestone (task associations are cleared)
- **Transit: Add Comment** — add a comment to a task
- **Transit: Generate Report** — produce a markdown report of completed tasks

All intents accept a JSON string input and return a JSON string response, including structured error codes (`TASK_NOT_FOUND`, `PROJECT_NOT_FOUND`, `AMBIGUOUS_PROJECT`, `INVALID_STATUS`, `INVALID_TYPE`, `INVALID_INPUT`, `MILESTONE_NOT_FOUND`, `DUPLICATE_MILESTONE_NAME`, `MILESTONE_PROJECT_MISMATCH`, `INTERNAL_ERROR`).

## MCP Server (macOS)

Transit includes a built-in MCP server on macOS for AI agent integration. Enable it in Settings and configure the port (default: 3141). The server exposes 10 tools over HTTP JSON-RPC 2.0:

`create_task`, `update_task_status`, `query_tasks`, `update_task`, `add_comment`, `get_projects`, `create_milestone`, `query_milestones`, `update_milestone`, `delete_milestone`

## Documentation

- `specs/transit-v1/` — requirements, design, architecture, tasks, and decision log
- `docs/transit-design-doc.md` — full design document
- `docs/agent-notes/` — implementation notes on architecture and technical constraints
- `CLAUDE.md` — guidance for Claude Code when working in this repository
