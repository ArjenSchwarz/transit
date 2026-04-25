# Specs Overview

| Name | Creation Date | Status | Summary |
|------|---------------|--------|---------|
| [Transit V1](#transit-v1) | 2026-02-09 | Done | Native Apple task tracker with kanban dashboard and CloudKit sync |
| [Themes V1](#themes-v1) | 2026-02-11 | No Tasks | Frosted Panels theme with light, dark, and universal modes |
| [Shortcuts-Friendly Intents](#shortcuts-friendly-intents) | 2026-02-11 | Done | Visual Shortcuts intents and date filtering for task queries |
| [MCP Server](#mcp-server) | 2026-02-12 | No Tasks | Embedded MCP server using Hummingbird for direct service access |
| [Intent Display ID Filter](#intent-display-id-filter) | 2026-02-13 | Done | Add displayId lookup to QueryTasksIntent for single-task queries |
| [MCP Task ID Filter](#mcp-task-id-filter) | 2026-02-13 | Done | Add displayId lookup to MCP query_tasks for single-task queries |
| [macOS Liquid Glass Forms](#macos-liquid-glass-forms) | 2026-02-13 | Done | Apply Liquid Glass Grid layout to all macOS form views |
| [T53 Alphabetical Projects](#t53-alphabetical-projects) | 2026-02-13 | No Tasks | Sort project lists alphabetically in all UI query declarations |
| [Bigger Description Field](#bigger-description-field) | 2026-02-14 | Done | Expand task description field using TextEditor on both platforms |
| [Add Comments](#add-comments) | 2026-02-15 | Done | Add timestamped, attributed comments to tasks for activity logging |
| [Type Filter](#type-filter) | 2026-02-16 | Done | Add task type filtering to the kanban dashboard |
| [Reports](#reports) | 2026-02-19 | Done | Generate reports of completed/abandoned tasks over date ranges |
| [Settings Background](#settings-background) | 2026-02-20 | Done | Add BoardBackground gradient to Settings view matching dashboard |
| [Get Projects MCP](#get-projects-mcp) | 2026-02-20 | Done | Add get_projects tool to MCP server for project discovery |
| [Text Filter](#text-filter) | 2026-02-21 | Done | Add text search filtering to dashboard and MCP query_tasks tool |
| [MCP Project Name Filter](#mcp-project-name-filter) | 2026-02-21 | Done | Add project name filtering to MCP query_tasks tool |
| [MCP Status Filter](#mcp-status-filter) | 2026-02-21 | Done | Multi-status, exclusion, and unfinished filters for MCP query_tasks |
| [Milestones](#milestones) | 2026-02-23 | Done | Group tasks under named releases or goals within projects |
| [Filter Redesign](#filter-redesign) | 2026-02-24 | Done | Replace single filter popover with separate per-type controls |
| [Search by Task Number](#search-by-task-number) | 2026-03-05 | Done | Extend dashboard search to match task display IDs |
| [Column Sort Order](#column-sort-order) | 2026-03-07 | Done | Add organized sort mode grouping by project, type, and ID |
| [Keyboard Shortcut New Task](#keyboard-shortcut-new-task) | 2026-03-09 | Done | Add Cmd+N and bare "t" shortcuts to open Add Task sheet |
| [License Acknowledgments](#license-acknowledgments) | 2026-03-09 | Done | Open-source license acknowledgments section in Settings |
| [macOS Settings Window](#macos-settings-window) | 2026-03-11 | Done | Dedicated macOS settings window via SwiftUI Settings scene |
| [Parse Comment Newlines](#parse-comment-newlines) | 2026-03-23 | Done | Fix literal \n in MCP comments by unescaping at input boundary |
| [Home Screen Quick Actions](#home-screen-quick-actions) | 2026-03-24 | Done | iOS Home Screen quick action to create a new task |
| [Sync Heartbeat](#sync-heartbeat) | 2026-03-28 | No Tasks | Periodic SwiftData write to force CloudKit sync on macOS |
| [Duplicate Display ID Cleanup](#duplicate-display-id-cleanup) | 2026-04-25 | Planned | Scan and reassign tasks/milestones sharing a permanentDisplayId |

---

## Transit V1

Native Apple task tracker with kanban dashboard and CloudKit sync.

- [decision_log.md](transit-v1/decision_log.md)
- [design.md](transit-v1/design.md)
- [implementation.md](transit-v1/implementation.md)
- [prerequisites.md](transit-v1/prerequisites.md)
- [requirements.md](transit-v1/requirements.md)
- [review-fixes-1.md](transit-v1/review-fixes-1.md)
- [review-overview-1.md](transit-v1/review-overview-1.md)
- [tasks.md](transit-v1/tasks.md)

## Themes V1

Frosted Panels theme with light, dark, and universal modes.

- [plan.md](themes-v1/plan.md)

## Shortcuts-Friendly Intents

Visual Shortcuts intents and date filtering for task queries.

- [decision_log.md](shortcuts-friendly-intents/decision_log.md)
- [design.md](shortcuts-friendly-intents/design.md)
- [implementation.md](shortcuts-friendly-intents/implementation.md)
- [requirements.md](shortcuts-friendly-intents/requirements.md)
- [review-fixes-1.md](shortcuts-friendly-intents/review-fixes-1.md)
- [review-overview-1.md](shortcuts-friendly-intents/review-overview-1.md)
- [tasks.md](shortcuts-friendly-intents/tasks.md)

## MCP Server

Embedded MCP server using Hummingbird for direct service access.

- [implementation.md](mcp-server/implementation.md)
- [plan.md](mcp-server/plan.md)
- [review-fixes-1.md](mcp-server/review-fixes-1.md)
- [review-overview-1.md](mcp-server/review-overview-1.md)

## Intent Display ID Filter

Add displayId lookup to QueryTasksIntent for single-task queries.

- [implementation.md](intent-displayid-filter/implementation.md)
- [smolspec.md](intent-displayid-filter/smolspec.md)
- [tasks.md](intent-displayid-filter/tasks.md)

## MCP Task ID Filter

Add displayId lookup to MCP query_tasks for single-task queries.

- [implementation.md](mcp-task-id-filter/implementation.md)
- [review-fixes-1.md](mcp-task-id-filter/review-fixes-1.md)
- [review-overview-1.md](mcp-task-id-filter/review-overview-1.md)
- [smolspec.md](mcp-task-id-filter/smolspec.md)
- [tasks.md](mcp-task-id-filter/tasks.md)

## macOS Liquid Glass Forms

Apply Liquid Glass Grid layout to all macOS form views.

- [smolspec.md](macos-liquid-glass-forms/smolspec.md)
- [tasks.md](macos-liquid-glass-forms/tasks.md)

## T53 Alphabetical Projects

Sort project lists alphabetically in all UI query declarations.

- [smolspec.md](t53-alphabetical-projects/smolspec.md)

## Bigger Description Field

Expand task description field using TextEditor on both platforms.

- [implementation.md](bigger-description-field/implementation.md)
- [smolspec.md](bigger-description-field/smolspec.md)
- [tasks.md](bigger-description-field/tasks.md)

## Add Comments

Add timestamped, attributed comments to tasks for activity logging.

- [decision_log.md](add-comments/decision_log.md)
- [design.md](add-comments/design.md)
- [implementation.md](add-comments/implementation.md)
- [requirements.md](add-comments/requirements.md)
- [review-fixes-1.md](add-comments/review-fixes-1.md)
- [review-overview-1.md](add-comments/review-overview-1.md)
- [tasks.md](add-comments/tasks.md)

## Type Filter

Add task type filtering to the kanban dashboard.

- [implementation.md](type-filter/implementation.md)
- [smolspec.md](type-filter/smolspec.md)
- [tasks.md](type-filter/tasks.md)

## Reports

Generate reports of completed/abandoned tasks over date ranges.

- [decision_log.md](reports/decision_log.md)
- [design.md](reports/design.md)
- [implementation.md](reports/implementation.md)
- [requirements.md](reports/requirements.md)
- [review-fixes-1.md](reports/review-fixes-1.md)
- [review-overview-1.md](reports/review-overview-1.md)
- [tasks.md](reports/tasks.md)

## Settings Background

Add BoardBackground gradient to Settings view matching dashboard.

- [implementation.md](settings-background/implementation.md)
- [smolspec.md](settings-background/smolspec.md)
- [tasks.md](settings-background/tasks.md)

## Get Projects MCP

Add get_projects tool to MCP server for project discovery.

- [implementation.md](get-projects-mcp/implementation.md)
- [review-overview-1.md](get-projects-mcp/review-overview-1.md)
- [smolspec.md](get-projects-mcp/smolspec.md)
- [tasks.md](get-projects-mcp/tasks.md)

## Text Filter

Add text search filtering to dashboard and MCP query_tasks tool.

- [implementation.md](text-filter/implementation.md)
- [review-fixes-1.md](text-filter/review-fixes-1.md)
- [review-overview-1.md](text-filter/review-overview-1.md)
- [smolspec.md](text-filter/smolspec.md)
- [tasks.md](text-filter/tasks.md)

## MCP Project Name Filter

Add project name filtering to MCP query_tasks tool.

- [implementation.md](mcp-project-name-filter/implementation.md)
- [smolspec.md](mcp-project-name-filter/smolspec.md)
- [tasks.md](mcp-project-name-filter/tasks.md)

## MCP Status Filter

Multi-status, exclusion, and unfinished filters for MCP query_tasks.

- [implementation.md](mcp-status-filter/implementation.md)
- [review-fixes-1.md](mcp-status-filter/review-fixes-1.md)
- [review-overview-1.md](mcp-status-filter/review-overview-1.md)
- [smolspec.md](mcp-status-filter/smolspec.md)
- [tasks.md](mcp-status-filter/tasks.md)

## Milestones

Group tasks under named releases or goals within projects.

- [decision_log.md](milestones/decision_log.md)
- [design.md](milestones/design.md)
- [implementation.md](milestones/implementation.md)
- [requirements.md](milestones/requirements.md)
- [tasks.md](milestones/tasks.md)

## Filter Redesign

Replace single filter popover with separate per-type controls.

- [decision_log.md](filter-redesign/decision_log.md)
- [design.md](filter-redesign/design.md)
- [implementation.md](filter-redesign/implementation.md)
- [requirements.md](filter-redesign/requirements.md)
- [tasks.md](filter-redesign/tasks.md)

## Search by Task Number

Extend dashboard search to match task display IDs.

- [implementation.md](search-by-task-number/implementation.md)
- [smolspec.md](search-by-task-number/smolspec.md)
- [tasks.md](search-by-task-number/tasks.md)

## Column Sort Order

Add organized sort mode grouping by project, type, and ID.

- [implementation.md](column-sort-order/implementation.md)
- [smolspec.md](column-sort-order/smolspec.md)
- [tasks.md](column-sort-order/tasks.md)

## Keyboard Shortcut New Task

Add Cmd+N and bare "t" shortcuts to open Add Task sheet.

- [implementation.md](keyboard-shortcut-new-task/implementation.md)
- [smolspec.md](keyboard-shortcut-new-task/smolspec.md)
- [tasks.md](keyboard-shortcut-new-task/tasks.md)

## License Acknowledgments

Open-source license acknowledgments section in Settings.

- [implementation.md](license-acknowledgments/implementation.md)
- [smolspec.md](license-acknowledgments/smolspec.md)
- [tasks.md](license-acknowledgments/tasks.md)

## macOS Settings Window

Dedicated macOS settings window via SwiftUI Settings scene.

- [decision_log.md](macos-settings-window/decision_log.md)
- [implementation.md](macos-settings-window/implementation.md)
- [sidebar-navigation-plan.md](macos-settings-window/sidebar-navigation-plan.md)
- [smolspec.md](macos-settings-window/smolspec.md)
- [tasks.md](macos-settings-window/tasks.md)

## Parse Comment Newlines

Fix literal \n in MCP comments by unescaping at input boundary.

- [implementation.md](parse-comment-newlines/implementation.md)
- [smolspec.md](parse-comment-newlines/smolspec.md)
- [tasks.md](parse-comment-newlines/tasks.md)

## Home Screen Quick Actions

iOS Home Screen quick action to create a new task.

- [implementation.md](home-screen-quick-actions/implementation.md)
- [smolspec.md](home-screen-quick-actions/smolspec.md)
- [tasks.md](home-screen-quick-actions/tasks.md)

## Sync Heartbeat

Periodic SwiftData write to force CloudKit sync on macOS.

- [implementation.md](sync-heartbeat/implementation.md)
- [plan.md](sync-heartbeat/plan.md)

## Duplicate Display ID Cleanup

Scan and reassign tasks/milestones sharing a permanentDisplayId.

- [decision_log.md](duplicate-displayid-cleanup/decision_log.md)
- [design.md](duplicate-displayid-cleanup/design.md)
- [requirements.md](duplicate-displayid-cleanup/requirements.md)
- [tasks.md](duplicate-displayid-cleanup/tasks.md)
