# Decision Log: Reports

## Decision 1: Spec Name

**Date**: 2026-02-18
**Status**: accepted

### Context

Need a directory name for the report feature spec.

### Decision

Use `reports` as the spec name (`specs/reports/`).

### Rationale

Short, clear, and matches the feature name. No ambiguity.

### Alternatives Considered

- **report-generation**: More descriptive — Rejected as unnecessarily verbose for a simple feature

### Consequences

**Positive:**
- Concise and easy to reference

**Negative:**
- None

---

## Decision 2: UI Access Pattern

**Date**: 2026-02-18
**Status**: accepted

### Context

The report needs to be accessible from the app UI. Options include a toolbar button, a settings section, or a menu item.

### Decision

Use a toolbar button on the dashboard that pushes a report view onto the NavigationStack.

### Rationale

A toolbar button provides direct access from the main workflow without burying the feature in settings. Pushing onto the NavigationStack is consistent with existing navigation patterns (e.g., Settings).

### Alternatives Considered

- **Settings section**: Would bury reports under settings — Rejected because reports are not a configuration concern
- **Menu item**: Less discoverable on iOS — Rejected for cross-platform consistency

### Consequences

**Positive:**
- Discoverable and quick to access
- Consistent with existing navigation patterns

**Negative:**
- Adds a button to the dashboard toolbar (minor visual impact)

---

## Decision 3: No MCP Support in V1

**Date**: 2026-02-18
**Status**: accepted

### Context

Reports could be exposed via the MCP server for agent integration, in addition to UI and Shortcuts.

### Decision

Limit V1 to UI and Shortcuts (App Intent) only. No MCP tool.

### Rationale

The App Intent already provides programmatic access. MCP can be added later if agent workflows need it. Reduces scope.

### Alternatives Considered

- **Include MCP tool**: Would provide agent access — Rejected to reduce scope; can be added later without breaking changes

### Consequences

**Positive:**
- Smaller implementation scope
- MCP can be added as a follow-up without breaking changes

**Negative:**
- Agents cannot generate reports directly via MCP (must use Shortcuts or query tasks manually)

---

## Decision 4: Week Start Day

**Date**: 2026-02-18
**Status**: accepted

### Context

"This Week" and "Last Week" date ranges need a defined start day. Different locales use Monday or Sunday.

### Decision

Use the device's locale setting to determine the first day of the week.

### Rationale

Respects user's regional conventions. Swift's `Calendar.current` already provides this via `firstWeekday`.

### Alternatives Considered

- **ISO 8601 (Monday)**: Consistent but ignores locale — Rejected because it would feel wrong to users in Sunday-start locales

### Consequences

**Positive:**
- Matches user expectations based on their region
- Trivial to implement via `Calendar.current`

**Negative:**
- Reports may differ across devices if locales differ (minor edge case for a single-user app)

---

## Decision 5: Include Summary Counts

**Date**: 2026-02-18
**Status**: accepted

### Context

The report could be a plain task list or include summary statistics.

### Decision

Include a summary section at the top with total count and per-project breakdown, separating Done and Abandoned counts.

### Rationale

Counts provide a quick overview without requiring the user to scan the full list. Minimal extra implementation effort.

### Alternatives Considered

- **List only**: Simpler output — Rejected because counts add significant value with minimal cost

### Consequences

**Positive:**
- Quick at-a-glance overview of work completed
- Distinguishes Done from Abandoned clearly

**Negative:**
- Slightly more complex Markdown template

---

## Decision 6: Copy to Clipboard

**Date**: 2026-02-18
**Status**: accepted

### Context

Users may want to share or paste reports into other tools.

### Decision

Include a copy-to-clipboard button in the report view that copies the raw Markdown text.

### Rationale

Markdown is a portable format. Copying raw Markdown lets users paste into any Markdown-compatible tool (notes, docs, chat).

### Alternatives Considered

- **View only**: Simpler but limits utility — Rejected because the whole point of Markdown output is portability

### Consequences

**Positive:**
- Reports can be easily shared or stored externally
- Raw Markdown preserves formatting in compatible tools

**Negative:**
- None significant

---

## Decision 7: Native SwiftUI View for Report Rendering

**Date**: 2026-02-18
**Status**: accepted

### Context

SwiftUI's `Text` supports inline Markdown (bold, italic, links) but not block-level Markdown (`##` headings, `- ` list items). The report view needs to render structured report content.

### Decision

Render the report as a native SwiftUI view using the same structured data model that feeds the Markdown generator. The Markdown string is only used for copy-to-clipboard and the Shortcuts intent.

### Rationale

Avoids third-party Markdown rendering dependencies. Gives full control over styling. The data model is generated once and consumed by both the SwiftUI view and the Markdown formatter.

### Alternatives Considered

- **Parse and render Markdown in SwiftUI**: Would need a third-party library or complex `AttributedString` parsing — Rejected as unnecessary complexity
- **WKWebView with Markdown→HTML**: Works but adds a web view to a native app — Rejected for inconsistent look and feel

### Consequences

**Positive:**
- Full control over visual presentation
- No third-party dependencies
- Consistent with app's native SwiftUI approach

**Negative:**
- Two rendering paths (SwiftUI view + Markdown text) that must stay in sync

---

## Decision 8: GitHub Flavored Markdown

**Date**: 2026-02-18
**Status**: accepted

### Context

Abandoned tasks use `~~strikethrough~~` which is a GFM extension, not part of CommonMark.

### Decision

Target GitHub Flavored Markdown (GFM) for the Markdown output.

### Rationale

GFM is the most widely supported Markdown variant. Most tools users would paste into (GitHub, Notion, Slack, Obsidian) support GFM strikethrough.

### Alternatives Considered

- **CommonMark only**: Would need a different abandoned task marker (e.g., `[ABANDONED]` prefix) — Rejected because strikethrough is more visually clear
- **Custom marker without strikethrough**: Less intuitive — Rejected

### Consequences

**Positive:**
- Strikethrough renders correctly in most modern Markdown tools
- Clear visual distinction for abandoned tasks

**Negative:**
- Tools that only support strict CommonMark will show literal `~~` characters

---

## Decision 9: Intent Runs in Background

**Date**: 2026-02-18
**Status**: accepted

### Context

The Generate Report App Intent returns Markdown text. It could either foreground the app or run in the background.

### Decision

Set `openAppWhenRun = false` so the intent runs without foregrounding the app.

### Rationale

The intent is a pure data operation — it returns a Markdown string. CLI and automation callers don't want the app to pop up. This differs from the existing `QueryTasksIntent` which sets `openAppWhenRun = true`, but report generation is explicitly designed for background automation.

### Alternatives Considered

- **Foreground the app**: Consistent with existing intents — Rejected because it disrupts automation workflows for no benefit

### Consequences

**Positive:**
- Clean automation experience from CLI/Shortcuts
- No app disruption when generating reports programmatically

**Negative:**
- Inconsistent with existing intents (minor; justified by different use case)

---

## Decision 10: Menu Picker for Date Range Selection

**Date**: 2026-02-18
**Status**: accepted

### Context

The report view needs a picker for 8 date range options. The picker style affects usability and layout.

### Decision

Use a menu-style picker (compact dropdown) for date range selection.

### Rationale

A menu picker is compact, works well with 8 options, and is the standard pattern for both macOS and iOS. A segmented control would be cramped, and a wheel picker takes too much space.

### Alternatives Considered

- **Segmented control**: All options visible at once — Rejected because 8 items is too many for a segmented control
- **Inline wheel picker**: Scrollable but takes vertical space — Rejected as overkill for a simple selection

### Consequences

**Positive:**
- Compact, familiar UI pattern
- Works consistently across iOS and macOS

**Negative:**
- Options hidden behind a tap (minor; standard trade-off for menus)

---

## Decision 11: Separate ReportDateRange Enum

**Date**: 2026-02-18
**Status**: accepted

### Context

The report needs an enum to drive the UI picker and map to `DateFilterHelpers.DateRange`. Options: reuse `DateFilterHelpers.DateRange` directly, or create a dedicated `ReportDateRange` with display labels.

### Decision

Create a dedicated `ReportDateRange` enum conforming to `AppEnum`, `CaseIterable`, and `Identifiable`. It owns display labels, drives the in-app menu picker, serves as the Shortcuts parameter type, and maps to `DateFilterHelpers.DateRange` for date calculation.

### Rationale

`DateFilterHelpers.DateRange` includes `.absolute(from:toDate:)` which isn't applicable to reports, and it has no display labels or `AppEnum` conformance. A dedicated enum keeps the report concern isolated, provides `CaseIterable` for the picker, and `AppEnum` for the Shortcuts parameter.

### Alternatives Considered

- **Reuse DateFilterHelpers.DateRange directly**: Would require filtering out `.absolute` and adding display labels and `AppEnum` conformance to a shared type — Rejected as it pollutes the shared utility with report-specific concerns

### Consequences

**Positive:**
- Clean separation of concerns
- `CaseIterable` conformance drives the menu picker naturally
- `AppEnum` conformance gives Shortcuts a native picker for free

**Negative:**
- Mapping layer between two enums (minimal overhead)

---

## Decision 12: Native Picker for Shortcuts Intent

**Date**: 2026-02-18
**Status**: accepted

### Context

The report intent could accept input as JSON (like existing Transit intents) or as a native `AppEnum` parameter with a picker. The intent is user-facing in Shortcuts, not a programmatic CLI-only tool.

### Decision

Use a native `AppEnum` picker parameter instead of JSON input. The intent accepts a `ReportDateRange` parameter directly and returns plain Markdown text.

### Rationale

A native picker is the correct UX for a user-facing Shortcuts action. Users select from a dropdown rather than typing JSON. This eliminates input validation errors entirely. The existing JSON-based intents serve a different purpose (CLI/automation with complex filter objects).

### Alternatives Considered

- **JSON input string**: Consistent with existing intents — Rejected because report generation is a user-facing action, not a programmatic API. JSON input is hostile UX for Shortcuts users.
- **Both JSON and picker**: Support both input modes — Rejected as unnecessary complexity for V1

### Consequences

**Positive:**
- Native Shortcuts UX with picker dropdown
- No input validation needed (picker constrains to valid values)
- Simpler intent implementation (no JSON parsing, no error codes)

**Negative:**
- Different pattern from existing intents (justified by different use case)
- No `INVALID_DATE_RANGE` error code needed (removed from IntentError)

---
