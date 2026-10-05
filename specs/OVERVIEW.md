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
| [Duplicate Display ID Cleanup](#duplicate-display-id-cleanup) | 2026-04-25 | Done | Scan and reassign tasks/milestones sharing a permanentDisplayId |
| [Update Task All Fields](#update-task-all-fields) | 2026-05-22 | Done | Extend update_task MCP tool and App Intent to update name, description, type, and metadata |
| [Search Empty State](#search-empty-state) | 2026-05-31 | Done | Show ContentUnavailableView.search empty state when dashboard text search has no matches |
| [Task Priority](#task-priority) | 2026-06-06 | Done | Add a low/medium/high priority field with board glyph, filter, and MCP/Intent support |
| [MCP Project Creation](#mcp-project-creation) | 2026-10-02 | Ready for Review | Create projects through MCP with validation and reusable project metadata |
| [Batch Task Queries](#batch-task-queries) | 2026-10-03 | Done | MCP task detail selection, batch lookup, and frozen cursor pagination |
| [MCP Write Safety](#mcp-write-safety) | 2026-10-03 | Done | Add retry-safe MCP writes, local revision preconditions, and structured saved outcomes |
| [Typed Task Links](#typed-task-links) | 2026-10-03 | Done | Saved typed task relationships with guarded edits, graph-covered revisions and frozen queries |
| [Structured MCP Results](#structured-mcp-results) | 2026-10-03 | Ready for Review | Structured/text results and latest-only transport locally verified; client compatibility explicitly deferred post-merge |
| [Bounded Read Freshness](#bounded-read-freshness) | 2026-10-03 | Done | Bound MCP read completion and report immutable saved capture/import evidence |
| [Portfolio Summaries](#portfolio-summaries) | 2026-10-04 | Done | Saved portfolio counts and reusable frozen task views; qualified native verification complete |
| [Batch Task Mutations](#batch-task-mutations) | 2026-10-04 | Done | Saved-only previews and ordered per-item MCP task writes; fresh native verification complete, publication pending |

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

## Update Task All Fields

Extend the `update_task` MCP tool and `UpdateTaskIntent` App Intent to update name, description, type, and metadata atomically alongside the existing milestone fields (T-650).

- [decision_log.md](update-task-all-fields/decision_log.md)
- [design.md](update-task-all-fields/design.md)
- [requirements.md](update-task-all-fields/requirements.md)
- [tasks.md](update-task-all-fields/tasks.md)

## Search Empty State

Show a `ContentUnavailableView.search` empty state on the dashboard when text search is the only active filter and yields no matches (T-198).

- [decision_log.md](search-empty-state/decision_log.md)
- [implementation.md](search-empty-state/implementation.md)
- [smolspec.md](search-empty-state/smolspec.md)
- [tasks.md](search-empty-state/tasks.md)

## Task Priority

Add a low/medium/high priority field (default medium) to tasks, shown as a board-card glyph for high/low, filterable on the board, editable in the create/edit/detail screens, and readable/settable via the MCP server and App Intents (T-1463).

- [decision_log.md](task-priority/decision_log.md)
- [design.md](task-priority/design.md)
- [implementation.md](task-priority/implementation.md)
- [requirements.md](task-priority/requirements.md)
- [tasks.md](task-priority/tasks.md)

## MCP Project Creation

Create projects through MCP with validation and a returned UUID for task creation (T-2377).

- [requirements.md](mcp-project-creation/requirements.md)
- [design.md](mcp-project-creation/design.md)
- [decision_log.md](mcp-project-creation/decision_log.md)
- [tasks.md](mcp-project-creation/tasks.md)
- [implementation.md](mcp-project-creation/implementation.md)
- [explanation.md](mcp-project-creation/explanation.md)
- The generated `pre-push-review.html` is a local, ignored review deliverable.

## Batch Task Queries

Extend MCP `query_tasks` with explicit detail/comment options, batch identity lookup, and bounded pages over five-minute frozen results (T-2379).

- [requirements.md](batch-task-queries/requirements.md)
- [design.md](batch-task-queries/design.md)
- [decision_log.md](batch-task-queries/decision_log.md)
- [tasks.md](batch-task-queries/tasks.md)
- [implementation.md](batch-task-queries/implementation.md)

## MCP Write Safety

Protect MCP writes with durable retry receipts, local content revisions, and structured saved outcomes (T-2380). The approved plan starts with persistence probes before handler integration.

All 18 coding tasks are implemented and review findings are resolved. Verification passed 1,853 macOS unit tests and 1,308 iOS unit/UI tests; implementation and phase changelog commits are recorded in the implementation report.

- [requirements.md](mcp-write-safety/requirements.md)
- [design.md](mcp-write-safety/design.md)
- [decision_log.md](mcp-write-safety/decision_log.md)
- [tasks.md](mcp-write-safety/tasks.md)
- [prerequisites.md](mcp-write-safety/prerequisites.md)
- [implementation.md](mcp-write-safety/implementation.md)


## Typed Task Links

Saved typed task relationships with guarded edits, graph-covered revisions and frozen queries. All 22 approved tasks and 39 local-scope acceptance criteria are complete. Final runs passed 3,253 macOS unit, 1,391 iOS unit and 26 iOS UI case executions; five macOS opt-in stages remain explicitly disabled. Four independent review roles found no outstanding mandatory fix. T-2402 live CloudKit verification and T-2381 consolidation remain separate work.

- [decision_log.md](typed-task-links/decision_log.md)
- [design-review.md](typed-task-links/design-review.md)
- [design.md](typed-task-links/design.md)
- [explanation.md](typed-task-links/explanation.md)
- [final-handoff.md](typed-task-links/final-handoff.md)
- [implementation.md](typed-task-links/implementation.md)
- [isolation-integration-plan.md](typed-task-links/isolation-integration-plan.md)
- [local-review.md](typed-task-links/local-review.md)
- [migration-next-tests.md](typed-task-links/migration-next-tests.md)
- [prerequisites.md](typed-task-links/prerequisites.md)
- [red-boundary-review.md](typed-task-links/red-boundary-review.md)
- [requirements-review.md](typed-task-links/requirements-review.md)
- [requirements.md](typed-task-links/requirements.md)
- [scope-assessment.md](typed-task-links/scope-assessment.md)
- [task14-checkpoint.md](typed-task-links/task14-checkpoint.md)
- [task20-checkpoint.md](typed-task-links/task20-checkpoint.md)
- [task4-checkpoint.md](typed-task-links/task4-checkpoint.md)
- [tasks-review.md](typed-task-links/tasks-review.md)
- [tasks.md](typed-task-links/tasks.md)
- [verification-readiness.md](typed-task-links/verification-readiness.md)


## Structured MCP Results

Immutable source/presentation results, supported-link availability and modern-only MCP2026-07-28 lifecycle, with unchanged protected replay and frozen read evidence.

**Status:** In Progress

- [Scope](structured-mcp-results/scope.md)
- [Requirements](structured-mcp-results/requirements.md)
- [Requirements review](structured-mcp-results/requirements-review.md)
- [Design](structured-mcp-results/design.md)
- [Design review](structured-mcp-results/design-review.md)
- [Tasks](structured-mcp-results/tasks.md)
- [Task review](structured-mcp-results/tasks-review.md)
- [Prerequisites](structured-mcp-results/prerequisites.md)
- [Decision log](structured-mcp-results/decision_log.md)
- [Implementation evidence](structured-mcp-results/implementation.md)
- [Local verification handoff](structured-mcp-results/local-verification-handoff.md)
- [Bounded client approval request](structured-mcp-results/client-readiness-next-approval.md)
- [Source RED evidence](structured-mcp-results/source-red.md)
- [Source cap RED evidence](structured-mcp-results/source-cap-red.md)
- [Source GREEN evidence](structured-mcp-results/source-green.md)
- [Presentation GREEN evidence](structured-mcp-results/presentation-green.md)
- [Protocol GREEN evidence](structured-mcp-results/protocol-green.md)
- [Encoder implementation draft](structured-mcp-results/encoder-green.md)
- [Encoder RED preparation](structured-mcp-results/encoder-red.md)
- [Encoder fixture review](structured-mcp-results/encoder-review.md)
- [Schema RED preparation](structured-mcp-results/schema-red.md)
- [Schema implementation readiness](structured-mcp-results/schema-green.md)
- [Isolation integration](structured-mcp-results/isolation-integration-plan.md)
- [Presentation RED evidence](structured-mcp-results/presentation-red.md)
- [Presentation supplemental RED evidence](structured-mcp-results/presentation-supplemental-red.md)
- [Pending common interface coordination](structured-mcp-results/interface-coordination.md)
- [Protocol RED evidence](structured-mcp-results/protocol-red.md)

## Bounded Read Freshness

**Created:** 2026-10-03 · **Status:** Done

T-63 bounds MCP reads with saved-only coherent capture, explicit import evidence, independent deadlines and frozen pagination metadata. Shared capture/publication contracts support T2382 reusable portfolio views.

All implementation tasks and native validation are complete. The remaining unique tests/docs proceed through PR review on merged main with explicit publication/disclosure approval.

- [Requirements](bounded-read-freshness/requirements.md)
- [Design](bounded-read-freshness/design.md)
- [Tasks](bounded-read-freshness/tasks.md)
- [Decisions](bounded-read-freshness/decision_log.md)
- [Task review](bounded-read-freshness/tasks-review.md)
- [Foundation handoff](bounded-read-freshness/foundation-handoff.md)
- [Tasks12/13 acceptance and diagnostics readiness](bounded-read-freshness/task13-acceptance.md)
- [Task14 diagnostics RED handoff](bounded-read-freshness/task14-red-handoff.md)
- [Task15 source readiness and owner patches](bounded-read-freshness/task15-source-handoff.md)
- [Catalog READ_FAILED focused RED preparation and diagnostic import](bounded-read-freshness/catalog-read-failed-red-preparation.md)
- [Focused catalog RED evidence and fixture ports](bounded-read-freshness/catalog-read-failed-red-handoff.md) — historical six intended body failures; runtime result unfinalized; finalized GREEN recorded below.
- [Caller read contract](../docs/mcp-read-contract.md)
- [Task15 integrated GREEN acceptance](bounded-read-freshness/task15-green-acceptance.md)
- [Task16 integrated native acceptance](bounded-read-freshness/task16-green-acceptance.md)
- [Implementation explanation](bounded-read-freshness/implementation.md)

## Portfolio Summaries

T-2382 completes regression coverage and caller guidance for the portfolio implementation already integrated on main. Installed-client compatibility remains deferred to post-merge MacBook validation.

- [Requirements](portfolio-summaries/requirements.md)
- [Design](portfolio-summaries/design.md)
- [Tasks](portfolio-summaries/tasks.md)
- [Implementation](portfolio-summaries/implementation.md)
- [Acceptance qualifications](portfolio-summaries/integration-acceptance.md)

## Batch Task Mutations

T-2384 provides `mutate_tasks` as one modern application tool call with advisory saved-only previews and ordered per-item protected writes. Original receipts, revision checks and retry evidence remain authoritative; complete preencoded fallback protects post-effect serialization failure. All 14 tasks and fresh macOS/iOS/UI acceptance are complete locally. Client readiness and specific publication/disclosure approvals remain separate release boundaries.

- [Scope](batch-task-mutations/scope.md)
- [Requirements](batch-task-mutations/requirements.md)
- [Design](batch-task-mutations/design.md)
- [Tasks](batch-task-mutations/tasks.md)
- [Decision log](batch-task-mutations/decision_log.md)
- [Implementation explanation and evidence](batch-task-mutations/implementation.md)
- [Three-level explanation](batch-task-mutations/explanation.md)
- [Final critical review](batch-task-mutations/final-critical-review.md)
- [Original native acceptance](batch-task-mutations/task14-green-actual.json)
- [Fresh reconciled publication verification](batch-task-mutations/publication-verification.json)
- [Final handoff](batch-task-mutations/final-handoff.md)
- [Local pre-push review archive](batch-task-mutations/local-review.json)
