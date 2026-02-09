# Transit — Design Document

**Version:** 0.3 (Draft)
**Status:** Planning

## Overview

Transit is a personal project and task tracker built for a single user across Apple devices. It provides a high-level kanban-style dashboard for tracking tasks as they move through defined stages, with CLI integration via App Intents and a future path to AI agent integration via MCP.

Transit sits alongside the existing tool ecosystem: Orbit (orchestrator), Starwave (spec workflow), and other project-specific utilities.

## Goals

- Single dashboard showing all active work across projects at a glance
- Native Apple experience on iPhone, iPad, and Mac
- Seamless sync between devices via CloudKit
- CLI-driven automation for updating task status from scripts, CI pipelines, and tooling
- Architecture that supports future MCP integration without rework

## Non-Goals (V1)

- Multi-user support
- Web interface
- Remote/server-side API access
- Notification or alerting system

---

## Data Model

### Project

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| id | UUID | Yes | Internal CloudKit record ID |
| name | String | Yes | |
| description | String | Yes | |
| gitRepo | String | No | URL to the repository |
| color | Color | Yes | User-picked via color picker |

### Task

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| id | UUID | Yes | Internal CloudKit record ID |
| displayId | Integer | Yes | Human-readable ID (e.g., T-1, T-42). Allocated via CloudKit counter record. Sequential, globally scoped, may have gaps. |
| name | String | Yes | |
| description | String | Yes | |
| status | Enum | Yes | See Task Statuses below |
| type | Enum | Yes | See Task Types below |
| lastStatusChangeDate | Date | Yes | Auto-updated on every status transition |
| completionDate | Date | No | Auto-set when status changes to `done` or `abandoned` |
| metadata | [String: String] | No | Free-form key-value pairs |

#### Task ID Strategy

Tasks use a UUID as the internal CloudKit record identifier. A separate `displayId` integer provides a human-readable reference (T-1, T-42) for use in the UI, CLI, git commits, and conversation.

Display IDs are allocated from a single counter record in CloudKit using optimistic locking. IDs are sequential and globally scoped but may have occasional gaps due to sync conflicts. Tasks created offline receive a provisional local ID and are assigned a permanent display ID on first sync.

### Relationships

A Project has many Tasks. A Task belongs to exactly one Project. Tasks can be moved between projects via the detail view edit mode.

### Task Statuses

Statuses represent a progression through stages. Tasks move forward through stages via drag interaction on the dashboard or programmatically via App Intents.

1. **Idea** — captured but not yet being considered
2. **Planning** — actively thinking through approach and requirements
3. **Spec** — writing or refining a specification; closer to implementation than planning
4. **Ready for Implementation** — spec is complete, awaiting human review or handoff to begin implementation
5. **In Progress** — actively being worked on
6. **Ready for Review** — implementation is complete, awaiting human review
7. **Done** — completed; auto-assigned a completion date
8. **Abandoned** — dropped from any stage; can be restored to Idea

#### Agent Handoff Statuses

"Ready for Implementation" and "Ready for Review" are agent handoff statuses. They signal that an agent has completed its phase of work and the task requires human attention. They exist primarily to support agent-driven workflows where an AI agent completes spec writing or implementation and needs to surface the result for human review.

These statuses are part of the linear data model but do not get their own columns on the dashboard. Instead:

- **Ready for Implementation** renders within the **Spec** column, visually promoted above other Spec tasks with a distinct highlight or badge indicating the handoff state.
- **Ready for Review** renders within the **In Progress** column, visually promoted above other In Progress tasks with a distinct highlight or badge indicating the handoff state.

This avoids expanding the kanban to seven columns (which would break the iPhone segmented control and crowd the iPad layout) while still giving agents a clear mechanism to signal "I'm done, human take over."

Agents set these statuses via App Intents. Humans acknowledge them by advancing the task to the next stage (e.g., moving a "Ready for Implementation" task to In Progress) or by reverting the status if more work is needed.

### Task Types

Fixed set, hardcoded in V1:

- Bug
- Feature
- Chore
- Research
- Documentation

### Metadata

Free-form string key-value pairs on tasks. No schema enforcement. Used for attaching contextual information such as branch names, PR URLs, build IDs, or any other relevant data. Consistency is maintained by convention rather than validation.

#### Reserved Namespace Conventions

No enforcement, but the following key prefixes are documented for consistency across CLI tools, CI pipelines, and future agent integrations:

| Prefix | Example Keys | Usage |
|--------|-------------|-------|
| `git.` | `git.branch`, `git.pr` | Git-related references |
| `ci.` | `ci.build`, `ci.pipeline` | CI/CD pipeline context |
| `agent.` | `agent.source`, `agent.session` | AI agent attribution |

---

## User Interface

### Navigation Structure

The app uses a single-screen navigation with the dashboard as the root view:

- **Dashboard** — the kanban board (root view, always visible on launch)
- **Settings** — accessed via a gear icon in the dashboard navigation bar, presented as a pushed view with a back button to return

Settings is an infrequent destination — there is no tab bar. The dashboard owns the full screen without persistent navigation chrome at the bottom, which lets Liquid Glass content extend to the bottom edge.

### Visual Design

Transit targets iOS/iPadOS/macOS 26 exclusively and uses Liquid Glass throughout. No fallback styling for older OS versions is needed. The design direction combines a warm, light-mode appearance with a deep dark mode variant.

**Materials and surfaces:**
- Card backgrounds use `.glassEffect()` / `UIGlassEffect` materials — translucent surfaces with backdrop blur and saturation that allow the wallpaper to bleed through
- Column headers, tab bar, segmented controls, and popovers all use glass materials at varying levels of prominence
- Inner highlight (top-edge specular) on cards and interactive surfaces
- Ambient color blobs behind content simulate wallpaper refraction effects

**Light mode:** System grouped background (`#F2F2F7`), white-to-transparent glass card surfaces.

**Dark mode:** True black background, very subtle glass surfaces with lower-intensity ambient color effects.

**Typography:** SF Pro (system font) throughout. Large title weight for screen headers, semibold for column headers, regular for card content.

**Task cards:**
- 1.5px border tinted with the project's assigned color (primary visual identification mechanism)
- Project name as secondary text above the task name
- Display ID (e.g., T-42) right-aligned in the card header
- Type shown as a tinted badge below the task name
- Abandoned tasks rendered at reduced opacity with strikethrough on the task name

**Reference mockup:** See `transit-ui-mockup.jsx` for an interactive web approximation of the layout, information density, and interaction patterns. The native implementation should follow platform conventions even where they differ from the mockup. For example, the filter/add/settings buttons in the nav bar should use a grouped pill container (standard iOS 26 toolbar item grouping) rather than the three separate buttons shown in the mockup. The web mockup cannot replicate Apple's private `UIGlassEffect` material — actual implementation will use native SwiftUI modifiers (`.glassEffect()`, `.materialBackground()`) which handle refraction and specular highlights natively.

### Dashboard

The primary view. A horizontal kanban board with five columns corresponding to the active task statuses, plus a combined terminal column.

**Layout:** Each column displays task cards. The kanban has five visual columns: Idea, Planning, Spec, In Progress, and Done / Abandoned. Tasks with agent handoff statuses ("Ready for Implementation" and "Ready for Review") render within the Spec and In Progress columns respectively, visually promoted to the top of the column with a distinct highlight or badge (e.g., a tinted banner or icon) indicating they require human attention. The final column is a combined **Done / Abandoned** column with a visual separator between the two sections. Abandoned tasks are visually distinct (reduced opacity, strikethrough).

**Navigation bar:** App title on the left. Filter button, add (+) button, and settings (gear icon) on the right, in that order. No project legend — the project-colored card borders provide identification at a glance.

**Sort order within columns:** Tasks are sorted by `lastStatusChangeDate` descending (most recently changed first). This is not user-controllable but provides predictable, consistent ordering.

**Interactions:**

- Drag a task card horizontally between columns to change its status. When moved to Done, the completion date is automatically recorded.
- Tap a task card to open the detail view.
- No vertical drag-to-reorder within columns.
- Tasks can be abandoned from any stage via the detail view. This sets the status to Abandoned and records a completion date.
- Abandoned tasks can be restored, which moves them back to Idea and clears the completion date.

**Done / Abandoned column filtering:** Only tasks completed or abandoned within the last 48 hours are shown, based on the completion date. Older tasks are hidden from the dashboard but remain in the data.

### Project Filter

A filter button in the dashboard navigation bar opens a popover listing all projects with checkboxes. Multiple projects can be selected simultaneously (OR logic — show tasks from any selected project). When active, the filter button shows the count of selected projects.

A "Clear" action resets the filter to show all projects.

The filter applies to all columns including the counts shown in column headers and the iPhone segmented control.

Filter state is ephemeral — it resets on app launch or tab switch. No need to persist it.

### Add Task

A single "+" button in the dashboard navigation bar opens a sheet for creating new tasks.

**Sheet contents:**
- **Project picker** — native dropdown/menu showing project name and color dot for each entry. Handles 10+ projects cleanly in a single row. Scrollable when the list is long.
- **Name** — text field, required
- **Description** — multiline text field, optional
- **Type** — selection from the fixed type list (feature, bug, chore, research, documentation)

New tasks always start in **Idea** status. No status picker on the creation sheet.

**Presentation:**
- iPhone: bottom sheet with drag handle (standard `.sheet` modifier)
- iPad/Mac: centered modal

### Detail View

A card or modal presented on tap from the dashboard.

**Presentation:**
- iPhone: bottom sheet sliding up from the edge
- iPad/Mac: centered modal with glass material background

**Content:** Task display ID, name, type (as a tinted badge), current status, project assignment (with color dot), description, and a list of metadata key-value pairs in a grouped inset section.

**Edit mode:** All fields are editable. Project assignment uses the same dropdown picker as the Add Task sheet. Task can be moved between projects via this picker.

**Actions:** Edit and Abandon buttons. Abandon sets the status to Abandoned and records a completion date.

This view will be iterated on across versions. V1 should be functional but doesn't need to be heavily designed.

#### Future Enhancements

- Show "Abandoned from: [previous status]" note on abandoned tasks (derived at display time, not stored).
- Link to task history view when status change history is implemented.

### Settings

Accessed via the gear icon in the dashboard navigation bar (rightmost button). Presented as a pushed view in the navigation stack with a chevron-only back button (no label text, per iOS 26 convention) to return to the dashboard. Uses a standard iOS grouped list layout.

**Projects section:**
- List of all projects with color swatch (rounded square with initial), project name, and active task count
- Each row navigates to a project detail/edit view (name, description, git repo, color picker)
- "+" button in the section header to create new projects

**General section (V1):**
- About Transit — version number
- iCloud Sync — toggle (maps to CloudKit sync enable/disable)

The Settings tab is designed to be extensible. Additional sections and settings can be added as needs emerge without restructuring the view.

---

## Sync

CloudKit is used for data synchronization across devices. Standard CloudKit container with private database for single-user data.

Both Project and Task records are stored in CloudKit and synced automatically. Conflict resolution follows CloudKit defaults (last-write-wins) which is acceptable for a single-user application.

**Concurrency note:** CLI tools, App Intents, the UI, and (future) MCP agents can all mutate state. Last-write-wins applies across all writers. This is acceptable given single-user usage, but concurrent mutations from multiple sources should be considered unlikely-but-possible rather than impossible.

---

## App Intents

App Intents serve as the application's programmatic API. They are designed with strict, structured input/output schemas to facilitate future wrapping by an MCP server or other integration layers.

### V1 Intents

**Create Task**

Input:
```json
{
  "projectId": "uuid-here",
  "project": "Transit",
  "name": "Implement dashboard layout",
  "description": "Build the kanban board view",
  "type": "feature",
  "metadata": { "git.branch": "feature/dashboard" }
}
```
- `projectId` is preferred. `project` (name) is accepted as a best-effort fallback.
- `metadata` is optional.

Output:
```json
{
  "taskId": "uuid-here",
  "displayId": 42,
  "status": "idea"
}
```

CLI usage: `shortcuts run "Transit: Create Task" --input-type text --input '<json>'`

**Update Task Status**

Input:
```json
{
  "task": { "displayId": 42 },
  "status": "in-progress"
}
```

Valid status values: `idea`, `planning`, `spec`, `ready-for-implementation`, `in-progress`, `ready-for-review`, `done`, `abandoned`.

Output:
```json
{
  "displayId": 42,
  "previousStatus": "spec",
  "status": "in-progress"
}
```

CLI usage: `shortcuts run "Transit: Update Status" --input-type text --input '<json>'`

**Query Tasks**

Input:
```json
{
  "status": "in-progress",
  "projectId": "uuid-here",
  "type": "feature"
}
```
All filters are optional. Omitted filters return all tasks.

Output:
```json
{
  "tasks": [
    {
      "taskId": "uuid-here",
      "displayId": 42,
      "name": "Implement dashboard layout",
      "status": "in-progress",
      "type": "feature",
      "projectId": "uuid-here",
      "projectName": "Transit",
      "completionDate": null,
      "lastStatusChangeDate": "2026-02-08T10:30:00Z"
    }
  ]
}
```

CLI usage: `shortcuts run "Transit: Query Tasks" --input-type text --input '<json>'`

### Error Handling

All intents return structured errors with a consistent shape:

```json
{
  "error": "TASK_NOT_FOUND",
  "hint": "No task with displayId 99. Did you mean T-42?"
}
```

Error codes:

| Code | Meaning |
|------|---------|
| `TASK_NOT_FOUND` | No task matches the provided identifier |
| `PROJECT_NOT_FOUND` | No project matches the provided identifier or name |
| `AMBIGUOUS_PROJECT` | Multiple projects match the provided name |
| `INVALID_STATUS` | Status value is not recognised |
| `INVALID_TYPE` | Type value is not recognised |

### Future Intents (Flagged)

These are not in V1 scope but should be anticipated in the architectural design. The intent interfaces should be consistent enough that adding these is additive, not a refactor.

- **Create Project** — needed for AI agent integration (e.g., creating a project at the end of a planning session)
- **Update Metadata** — attaching PR URLs, branch names, or build info from CI pipelines
- **Query Projects** — listing projects with summary information

### Design Principle

All intents accept and return structured JSON with strict schemas. Project references support both UUID (`projectId`) and name (`project`) with UUID preferred. Task references use `displayId` for human-facing operations. Error responses are structured and consistent across all intents. These conventions are the foundation for future MCP integration.

---

## Future: MCP Integration

Not in V1 scope, but the architecture is designed to support it.

**Architecture:** MCP server acts as a thin translation layer over App Intents. The MCP server runs locally on macOS and invokes intents via Shortcuts. The Mac app must be running.

**MCP tools would map directly to App Intents:**

| MCP Tool | App Intent |
|----------|-----------|
| create_project | Create Project (future) |
| create_task | Create Task |
| update_task_status | Update Task Status |
| update_metadata | Update Metadata (future) |
| query_projects | Query Projects (future) |
| query_tasks | Query Tasks |

**Use cases:**

- Creating a project and tasks at the end of a brainstorming or planning conversation with Claude
- Daily check-in: Claude queries current project/task status and provides a summary
- Automated updates: Claude Code or other agents update task status as work progresses
- Agent handoff: agents set tasks to "Ready for Implementation" or "Ready for Review" to surface work for human attention

**Operational constraints:**

- **App must be running:** The Mac app (or at minimum, the App Intents host) must be running for the MCP server to function. Agents should detect and report this clearly if invocation fails.
- **Local-only:** The Mac running the app and MCP server must be the same machine. If remote access is ever needed, a server-side API in front of CloudKit would be required — that's a different architecture and out of scope.
- **Concurrent writes:** MCP, CLI, and UI can all mutate state. Last-write-wins applies. Single-user makes this acceptable but agents should be aware that state may change between queries and updates.

### MCP Apps

MCP Apps is the first official MCP extension (SEP-1865, released January 2026). It enables MCP servers to return interactive HTML-based UI components that render directly in the host's conversation — supported by Claude, ChatGPT, VS Code, Goose, and others. UI components run in sandboxed iframes with bidirectional JSON-RPC communication to the host.

Transit's MCP server should adopt MCP Apps to provide richer agent interactions than plain JSON responses. Potential UI surfaces include:

- **Task cards** — interactive cards rendered inline in conversation when querying tasks, with buttons to advance status or edit fields directly from the chat
- **Dashboard summary** — a compact kanban or status overview embedded in a daily check-in response, showing task distribution and flagged items
- **Creation confirmation** — a visual card showing the newly created task with project color and metadata, rather than a JSON blob

The MCP Apps spec requires servers to provide text-only fallback for all UI-enabled tools, so Transit's MCP server would continue to work with text-only hosts (CLI Shortcuts, headless agents) while providing rich UI in capable hosts.

**Architecture implications:** MCP Apps uses HTML rendered in iframes. The UI components would be bundled as part of the MCP server, not the native iOS/macOS app. They don't need to match the native app's Liquid Glass styling — they should follow the host application's conventions instead (e.g., Claude's conversation aesthetic, VS Code's editor style). The MCP server should provide the interaction, not attempt to replicate the native app's design.

**Implementation priority:** MCP tools (plain JSON) first, MCP Apps UI second. The tools provide the functional foundation; the UI is an enhancement layer on top.

---

## Technical Stack

- **Language:** Swift 6.2
- **UI Framework:** SwiftUI
- **Minimum Targets:** iOS 26, iPadOS 26, macOS 26 — no backwards compatibility with older OS versions
- **Sync:** CloudKit (private database)
- **Integration:** App Intents framework, Shortcuts

---

## Platform Layout

### iPhone — Portrait
Single column visible at a time. A segmented control below the navigation bar shows all five status categories with task counts. Tapping a segment switches the visible column. Default segment on launch: **In Progress** ("Active" in the compact label).

Short labels used in the segmented control: Idea, Plan, Spec, Active, Done.

### iPhone — Landscape
Three columns visible at a time. Swipe left/right to reveal additional columns. Default columns on launch: **Planning / Spec / In Progress**.

### iPad and Mac
Full five-column view. All statuses visible simultaneously.

---

## Conventions

### Shortcuts Naming
All Shortcuts follow the pattern `Transit: Action Name`. Examples:
- `Transit: Create Task`
- `Transit: Update Status`
- `Transit: Query Tasks`

---

## Decision Log

Decisions made during the design phase, including alternatives that were considered and rejected.

### Task ID strategy
**Decision:** UUID internally for CloudKit record identity. Separate `displayId` integer for human-facing use, allocated via a CloudKit counter record with optimistic locking. Globally scoped, sequential, may have gaps.
**Alternatives considered:**
- Auto-incrementing integer as sole ID — CloudKit has no atomic increment primitive; two devices creating tasks offline would collide.
- UUIDs as the displayed ID — guaranteed unique but not human-friendly for CLI, git commits, or conversation.
- Timestamp-based monotonic IDs — avoids coordination but produces longer, less memorable identifiers.
**Rationale:** UUID + displayId gives CloudKit-native uniqueness with human-readable references. The counter record adds minor complexity but keeps IDs short and sequential.

### Project identity in intents
**Decision:** Intents accept both `projectId` (UUID, preferred) and `project` (name, best-effort fallback).
**Rationale:** Project names may change over time. UUID provides a stable reference for automation. Name fallback preserves CLI ergonomics for quick, ad-hoc use.

### Cross-project task moves
**Decision:** Supported via a project selection picker in the detail view edit mode.
**Rationale:** The "this task was misclassified" moment is inevitable. Restricting moves to the detail view edit mode avoids accidental project changes via drag interactions on the dashboard.

### Task ordering within status columns
**Decision:** No user-defined ordering. Tasks sorted by `lastStatusChangeDate` descending.
**Rationale:** Adding drag-to-reorder vertically requires persisting a sort order per task, which adds model and interaction complexity. Sorting by last status change provides predictable, consistent ordering that reflects recent activity. Cross-column drag (status change) is supported.

### Task metadata approach
**Decision:** Free-form string key-value pairs with no schema enforcement. Reserved namespace conventions documented for consistency.
**Alternatives considered:**
- Fixed fields (branch, PR, etc.) — too rigid, requires schema changes for new fields.
- User-defined field templates with a schema editor — provides structure and validation but requires building field management UI, deciding on per-project vs global scope, handling field types, and teaching the CLI which fields exist. Significant complexity for uncertain benefit.
**Rationale:** Start with free-form and rely on convention for consistency. Documenting namespace prefixes (`git.`, `ci.`, `agent.`) bridges the gap between free-form and structured without enforcement overhead.

### Task type list
**Decision:** Hardcoded list: bug, feature, chore, research, documentation.
**Alternative considered:** User-configurable type list.
**Rationale:** Single user, small set, can be changed in code. A configurable list adds UI and storage complexity for a feature that will rarely change.

### Task dependencies
**Decision:** Not supported.
**Rationale:** The use case is personal tracking, not project management. Dependencies add significant model complexity (graph of relationships, cycle detection, blocked state visualization). Not needed for the intended workflow.

### Task priority
**Decision:** Not supported in V1.
**Rationale:** No current need. Position on the dashboard (which column a task is in) provides sufficient signal about what needs attention.

### Status change history
**Decision:** Only `lastStatusChangeDate` and `completionDate` are tracked. No full history.
**Alternative considered:** Full status change history with timestamps for self-analysis.
**Rationale:** `lastStatusChangeDate` covers the immediate needs (column sorting, agent summaries, recent activity). Full history is useful but not essential for V1. Can be added later without breaking changes.

### Project archival
**Decision:** Not in V1.
**Rationale:** Acknowledged as a future need. V1 projects persist indefinitely. Archival can be added without breaking changes.

### Done / Abandoned column display
**Decision:** Show tasks completed or abandoned within the last 48 hours only, in a combined column with a visual separator.
**Rationale:** Both are terminal states. The done/abandoned column would grow unbounded without a time filter. 48 hours provides a window to see recent completions and restore abandoned tasks without clutter. The completion date field enables this filter.

### Project colors
**Decision:** User-picked via a color picker.
**Alternative considered:** Auto-assigned colors.
**Rationale:** Small number of projects, user will care about distinguishability. Auto-assignment risks poor contrast or confusing color choices.

### CLI integration mechanism
**Decision:** App Intents invoked via Shortcuts from the CLI.
**Alternative considered:** Direct CloudKit writes from CLI tools — would work cross-device but requires maintaining CloudKit authentication outside the app, which is complex.
**Alternative considered:** Local HTTP server — additional surface area to maintain, port conflicts, security considerations.
**Rationale:** App Intents via Shortcuts is the most Apple-native approach and aligns with the existing pattern used in Meridian. Requires the Mac app to be running, which is acceptable.

### MCP vs direct API for AI integration
**Decision:** Plan for MCP as a thin layer over App Intents. Local-only.
**Alternative considered:** Server-side API in front of CloudKit for remote access.
**Rationale:** Local-only is acceptable for current needs. Server-side API is a fundamentally different architecture that adds hosting, authentication, and maintenance burden. Can be revisited if remote access becomes necessary.

### MCP-UI
**Decision:** Not designing around MCP-UI.
**Rationale:** Too experimental. Standard MCP tools returning structured JSON that Claude can summarize conversationally cover all identified use cases. MCP-UI can be adopted later if it matures — it would be additive.

### Abandoned task restoration
**Decision:** Restoring an abandoned task always returns it to Idea status.
**Alternative considered:** Restoring to the pre-abandonment status.
**Rationale:** Returning to previous status requires storing additional state (the prior status). Restoring to Idea is simple and the user can manually advance the task from there. Avoids edge cases around stale context.

### Abandoned task display
**Decision:** Abandoned tasks share a column with Done, shown below a visual separator, with the same 48-hour visibility window.
**Alternative considered:** Separate Abandoned column.
**Rationale:** Abandoned and Done are the same category (terminal states). A separate column wastes space for what is typically a small number of tasks. Keeping them visible for 48 hours enables the undo/restore use case.

### Sync conflict resolution
**Decision:** CloudKit default (last-write-wins).
**Rationale:** Single-user application. Multiple writers (UI, CLI, future MCP) make conflicts theoretically possible but practically rare and low-stakes.

### Navigation structure
**Decision:** Single-screen navigation. Dashboard is the root view. Settings is accessed via a gear icon in the nav bar, pushed as a standard navigation stack view with a back button.
**Alternatives considered:**
- Two-tab navigation (Dashboard + Settings) — gives Settings equal visual prominence via a permanent tab bar, but Settings is visited infrequently. Wastes bottom-edge screen real estate, especially on iPhone. With Liquid Glass, a persistent tab bar caps the content area and prevents the glass effect from extending to the bottom edge.
- Sidebar navigation — overkill for one primary view and one settings screen.
- "Management" as a co-equal tab — only justified if project management becomes a frequent, complex activity. As a settings subsection, it doesn't warrant tab-level placement.
**Rationale:** A navigation push is the standard iOS pattern for infrequent destinations (Weather, Clock, Calculator all do this). The dashboard is the only view that matters day-to-day — it should own the full screen without sharing navigation chrome with a rarely-used settings view.

### Dashboard project legend
**Decision:** Removed. Replaced with a project filter.
**Rationale:** The project-colored card borders already provide at-a-glance project identification. A legend showing 10+ projects in the navigation bar wastes space and doesn't scale. A filter button is more useful — it lets you scope the dashboard to specific projects when needed.

### Project picker pattern
**Decision:** Native dropdown/menu with project color dot and name.
**Alternatives considered:**
- Chip grid (tappable buttons laid out in rows) — works at 4 projects, breaks at 10+. Multiple lines are ugly and don't work well on iPhone.
- Searchable list — handles scale but heavy UI for picking one item.
- Scrollable single row with search — keeps the visual feel but adds complexity.
**Rationale:** A dropdown is the most iOS-native pattern, takes up a single row regardless of project count, and the color dot preserves visual identification. For the Add Task sheet where you're picking one project, you don't need to see them all at once.

### iPhone column navigation
**Decision:** Segmented control with status names and task counts, defaulting to "Active" (In Progress).
**Alternative considered:** Horizontal swipe between columns.
**Rationale:** A segmented control gives immediate visibility into task distribution across all statuses. Swipe-based navigation hides the other columns entirely. The counts in each segment provide useful ambient information about where work is accumulating.

### Visual design direction
**Decision:** Liquid Glass design targeting iOS 26+. Light mode uses system grouped background with translucent glass cards. Dark mode uses true black with subtle glass surfaces. Project-colored borders on task cards (1.5pt) as the primary visual identification.
**Rationale:** Aligns with the iOS 26 design language. Project-colored borders are more visible than a dot prefix and scale across card sizes. True black dark mode follows Apple's convention for OLED displays.

### Task creation default status
**Decision:** New tasks always start in Idea. No status picker on the creation sheet.
**Rationale:** The creation sheet should be fast and minimal. "Capture first, promote later" matches the intended workflow. If tasks frequently need to bypass Idea (e.g., from CLI mid-sprint), the App Intents support creating directly into any status — the UI optimises for the common case.

### Filter state persistence
**Decision:** Ephemeral. Filter resets on app launch and tab switch.
**Rationale:** No clear benefit to persisting filter state for a personal app. If you always want to see only certain projects, that's a signal to use project archival (future feature) rather than a permanent filter.

### Agent handoff statuses
**Decision:** "Ready for Implementation" and "Ready for Review" are full statuses in the data model but render within existing kanban columns (Spec and In Progress respectively) with visual promotion rather than as separate columns.
**Alternatives considered:**
- Separate kanban columns for each handoff status — expands the board to seven columns, breaking the iPhone segmented control and crowding the iPad layout.
- Boolean flag on tasks (e.g., `needsReview: true`) — simpler model but doesn't integrate cleanly with the status progression or App Intents, and creates ambiguity about what the current "real" status is.
- Tags instead of statuses — tags are free-form and wouldn't show up in the kanban flow.
**Rationale:** Handoff statuses are part of the logical progression (Spec → Ready for Implementation → In Progress → Ready for Review → Done) but don't justify dedicated columns. Promoting them visually within their parent column provides the "human, look at this" signal without expanding the board. Agents set them via App Intents, humans acknowledge them by advancing the task.

### MCP Apps adoption
**Decision:** Plan for MCP Apps as an enhancement layer on top of the plain JSON MCP tools. Tools first, UI second.
**Previous position:** MCP-UI was dismissed as too experimental to design around.
**Updated rationale:** MCP Apps became an official, production-ready MCP extension in January 2026 (SEP-1865), jointly developed by Anthropic, OpenAI, and MCP-UI. It is supported by Claude, ChatGPT, VS Code, Goose, and others. The spec is stable, the SDK is mature, and the extension model is explicitly designed for optional adoption without breaking existing text-only tools. Transit should plan for MCP Apps from the start and adopt it once the base MCP tools are functional.

### Intent error handling
**Decision:** Structured error responses with error codes and hints.
**Rationale:** Consistent error shapes across all intents simplify CLI scripting and future MCP integration. Hints provide actionable context without requiring the caller to parse free-form error messages.

---

## Future Enhancements (Flagged)

Items identified during design that are explicitly deferred but worth tracking:

- **Project archival** — hiding completed projects from active views
- **Full status change history** — tracking every status transition with timestamps for self-analysis
- **"Abandoned from" indicator** — showing the pre-abandonment status in the detail view (derived, not stored)
- **Completed tasks history view** — browsable history of done/abandoned tasks beyond the 48-hour dashboard window, with a footer hint on the dashboard linking to it
- **Additional App Intents** — Create Project, Update Metadata, Query Projects
- **MCP server** — thin translation layer over App Intents for AI agent integration
- **MCP Apps UI** — interactive task cards, dashboard summaries, and creation confirmations rendered inline in MCP-capable hosts (Claude, ChatGPT, VS Code)
- **Remote access** — server-side API in front of CloudKit (only if local-only becomes insufficient)

---

## Open Questions

- App icon design
