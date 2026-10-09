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
- **MCP server** (macOS) — HTTP JSON-RPC server for AI agent integration with 17 normal tools
- **Agent handoff statuses** (Ready for Implementation, Ready for Review) for AI/human workflow integration
- **Adaptive layout**: width-based multi-column Kanban on iPhone/iPad/Mac, with a segmented single-column fallback only when one column fits
- **Drag and drop** between columns to change task status
- **Search and filter** — by project, type, milestone, status, and text (including display ID matching)
- **Liquid Glass** design language throughout

## Requirements

- iOS 26 / iPadOS 26 / macOS 26
- Xcode 27
- Swift 6.4

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
- **Transit: Update Task** — update task properties (description, metadata, milestone assignment)
- **Transit: Create Milestone** — create a milestone within a project
- **Transit: Query Milestones** — list milestones with optional filters
- **Transit: Update Milestone** — update milestone name, description, or status
- **Transit: Delete Milestone** — delete a milestone (task associations are cleared)
- **Transit: Add Comment** — add a comment to a task
- **Transit: Generate Report** — produce a markdown report of completed tasks

All intents accept a JSON string input and return a JSON string response, including structured error codes (`TASK_NOT_FOUND`, `PROJECT_NOT_FOUND`, `AMBIGUOUS_PROJECT`, `INVALID_STATUS`, `INVALID_TYPE`, `INVALID_INPUT`, `MILESTONE_NOT_FOUND`, `DUPLICATE_MILESTONE_NAME`, `AMBIGUOUS_MILESTONE`, `MILESTONE_PROJECT_MISMATCH`, `INTERNAL_ERROR`).

## MCP Server (macOS)

Transit includes a built-in MCP server on macOS for AI agent integration. Enable it in Settings and configure the port (default: 3141). The server exposes 17 normal tools over latest-only MCP `2026-07-28` HTTP JSON-RPC 2.0:

`create_task`, `update_task_status`, `query_tasks`, `update_task`, `add_comment`, `get_projects`, `create_project`, `create_milestone`, `query_milestones`, `update_milestone`, `delete_milestone`, `query_project_summaries`, `mutate_tasks`, `preview_task_consolidation`, `consolidate_tasks`, `preview_task_consolidation_undo`, `undo_task_consolidation`

**Breaking transport change:** Older MCP clients using `initialize`, session negotiation, GET streams or JSON-RPC wire arrays are unsupported. Requests require the modern headers and `_meta` fields described in the [MCP result contract](docs/mcp-result-contract.md). Missing required metadata returns an explanatory HTTP 400 protocol error; an otherwise valid modern `initialize` request returns HTTP 404 / JSON-RPC method-not-found. Actual installed-client compatibility remains unverified.

`mutate_tasks` accepts one application batch of 1–50 task updates, status updates or comments, with saved-only advisory previews and ordered per-item outcomes. See the [batch mutation contract](docs/mcp-write-contract.md#application-batch-task-mutations) for stopping, replay and recovery rules.

Consolidation previews review one survivor and one to five same-project candidates while retaining originals and comments. Apply requires the exact retained review and explicit preservation acknowledgment; whole undo requires matching current saved evidence. Native task details show read-only saved history. See the [consolidation workflow](docs/mcp-write-contract.md#reviewed-task-consolidation).

The ten standalone write tools require an `idempotencyKey`. Task/milestone updates and milestone deletion also require the target's current `expectedRevision`. Read a revision before updating, and retry an interrupted request with the same key and arguments. Responses use structured saved-record outcomes; see the [MCP write contract](docs/mcp-write-contract.md) for examples, seven-day replay retention, conflicts, and local-store limits. See the [MCP result contract](docs/mcp-result-contract.md) for structuredContent, modern request headers and recovery. See the [bounded read contract](docs/mcp-read-contract.md) for saved capture freshness, policy, deadlines and retry guidance. See the [portfolio contract](docs/mcp-portfolio-contract.md) for project summaries and task queries over the same frozen snapshot. Actual installed-client compatibility is deferred to post-merge MacBook validation and remains unverified. App Intent inputs are unchanged.

## Documentation

- `specs/transit-v1/` — requirements, design, architecture, tasks, and decision log
- `docs/transit-design-doc.md` — full design document
- `docs/agent-notes/` — implementation notes on architecture and technical constraints
- `CLAUDE.md` — guidance for Claude Code when working in this repository

## Debug and Release coexistence

See [environment setup](docs/environments.md) for separate app identities, local stores and defaults, the dedicated Debug iCloud opt-in, and MCP defaults (Debug 3142, Release 3141). The existing Release CloudKit Development dataset is preserved.
