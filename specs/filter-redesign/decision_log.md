# Decision Log: Filter Redesign

## Decision 1: Scope — Task Type, Not Status

**Date**: 2026-02-23
**Status**: accepted

### Context

The original ticket (T-224) mentioned "status" as one of the filter types to break out. However, the kanban board columns already represent status grouping. Adding a status filter would either conflict with the column layout or require collapsing the board into a flat list.

### Decision

The "status" filter mentioned in T-224 refers to the existing task type filter (bug, feature, chore, research, documentation). No new status-based filter will be added.

### Rationale

The user confirmed this was a misnomer. The kanban columns already serve as the status grouping mechanism.

### Alternatives Considered

- **Add a status filter**: Would conflict with the column-based layout and require significant UX rethinking — rejected as out of scope for this feature
- **Filter to show/hide specific columns**: More complex, changes the kanban paradigm — rejected

### Consequences

**Positive:**
- Keeps the feature focused on UI restructuring
- No changes to the underlying data model or filtering logic

**Negative:**
- None significant

---

## Decision 2: Search Stays As-Is

**Date**: 2026-02-23
**Status**: accepted

### Context

The existing `.searchable()` modifier in the navigation bar provides text search across task names and descriptions. It could be integrated into the new filter UI or left separate.

### Decision

Search remains as-is using the `.searchable()` navigation bar modifier. It is out of scope for this redesign.

### Rationale

The user confirmed search works fine in its current location. Integrating it would add complexity without clear benefit.

### Alternatives Considered

- **Integrate search into the filter UI**: Would unify all filtering in one place — rejected because `.searchable()` is a well-understood iOS pattern and works well where it is

### Consequences

**Positive:**
- Smaller scope, faster delivery
- Users keep a familiar search interaction

**Negative:**
- Search and filters remain visually separate (acceptable trade-off)

---

## Decision 3: Always-Visible Clear All

**Date**: 2026-02-23
**Status**: accepted

### Context

The current "Clear All" button is at the bottom of a scrollable list inside the filter popover. Users must scroll past all filter sections to reach it.

### Decision

Provide a persistent "clear all" control that is visible whenever any filter is active, without requiring scrolling or opening a popover/menu.

### Rationale

The user explicitly requested this. Clearing filters is a common action that should be immediately accessible.

### Alternatives Considered

- **Per-filter clear only (no global clear)**: Each filter has its own clear — rejected because a single action to reset everything is valuable when multiple filters are active
- **Global clear inside a menu**: Keeps it discoverable but still requires opening something — rejected as not solving the core problem

### Consequences

**Positive:**
- One-tap access to clearing all filters
- Visible indicator that filters are active

**Negative:**
- Takes up toolbar/screen space when filters are active

---

## Decision 4: UI Pattern — Explore in Design Phase

**Date**: 2026-02-23
**Status**: accepted

### Context

The user is leaning towards toolbar-based menus (like Finder's sort/group menus) but wants to explore options during the design phase before committing.

### Decision

Defer the specific UI pattern choice to the design phase. The requirements are written to be pattern-agnostic — they specify what the controls must do, not how they look.

### Rationale

Multiple valid patterns exist (toolbar menus, filter bar, chips). The right choice depends on platform constraints, visual design, and interaction ergonomics that are better explored during design.

### Alternatives Considered

- **Commit to toolbar menus now**: User's initial preference — deferred rather than rejected, to allow informed comparison in design phase

### Consequences

**Positive:**
- Design phase can evaluate options with full context
- Requirements don't over-constrain the solution

**Negative:**
- Slightly longer path to implementation

---

## Decision 5: Clear All Includes Search

**Date**: 2026-02-23
**Status**: accepted

### Context

The initial draft had "clear all" clearing project, type, and milestone filters but not search text. Meanwhile, the active filter count included search. This created an inconsistency: after clearing all, the count could still show "1" (for search) with no visible way to clear it via the clear-all button.

### Decision

"Clear all" clears everything — project, type, milestone selections AND search text.

### Rationale

The user chose consistency. If there's a "clear all" action, it should reset the view completely. The count and clear-all now operate on the same set of filters.

### Alternatives Considered

- **Exclude search from the count**: Would make the count match clear-all's original scope — rejected because the user preferred clear-all to be truly "all"
- **Keep the asymmetry**: Accept that clear-all doesn't touch search — rejected as confusing UX

### Consequences

**Positive:**
- Clear-all is truly "all" — no residual filter state after clearing
- Count and clear-all semantics are consistent

**Negative:**
- Clear-all reaches into the `.searchable()` state, coupling the two systems slightly

---

## Decision 6: Keep Current Milestone Clearing Behaviour

**Date**: 2026-02-23
**Status**: accepted

### Context

The current implementation clears ALL milestones when the project filter changes. The initial draft of requirement 1.7 said "milestones that are no longer in scope SHALL be cleared," implying selective clearing. The review flagged this as an unintentional behaviour change.

### Decision

Keep the current behaviour: clear all milestones on any project filter change.

### Rationale

Milestones are scoped to projects. When the project filter changes, the milestone context changes fundamentally. Selective clearing would preserve milestone selections that may no longer make sense in the new project context. The user confirmed there's no practical difference since milestones are tied to projects.

### Alternatives Considered

- **Selective clearing (only out-of-scope)**: Would preserve in-scope selections — rejected as unnecessary complexity with no practical benefit

### Consequences

**Positive:**
- No behaviour change from current implementation
- Simple, predictable behaviour

**Negative:**
- None

---

## Decision 7: Per-Control Counts, No Aggregate

**Date**: 2026-02-23
**Status**: accepted

### Context

The current implementation shows an aggregate filter count on a single filter button ("Filter (3)"). With separate controls, that single button no longer exists. The count needs a new home.

### Decision

Each filter control shows its own selection count (e.g., "Projects (2)"). No aggregate count is displayed.

### Rationale

Per-control counts are more informative than an aggregate — they tell the user which specific filter has selections. With separate controls, users can see at a glance which filters are active and how many selections each has.

### Alternatives Considered

- **Keep an aggregate count somewhere**: Adds visual noise without clear benefit when per-control counts already exist — rejected
- **Defer to design**: Rejected because the requirements needed to specify the count model to be implementable

### Consequences

**Positive:**
- More informative than a single aggregate number
- Natural fit for separate controls
- No need for a separate count display element

**Negative:**
- Slightly more visual information to process (three counts vs one)

---

## Decision 8: Clear All Hidden When Inactive

**Date**: 2026-02-23
**Status**: accepted

### Context

When no filters are active, the clear-all control could either be hidden (disappearing from the UI) or disabled (remaining visible but grayed out). The choice affects layout stability.

### Decision

Hide the clear-all control when no filters are active.

### Rationale

Matches the current implementation pattern. A disabled "clear all" that can never be activated is visual noise. Hiding it keeps the UI clean in the default (unfiltered) state.

### Alternatives Considered

- **Disabled but visible**: Prevents layout shifts — rejected because layout stability is a design concern that can be handled with fixed-width toolbar areas

### Consequences

**Positive:**
- Clean default state
- Consistent with current behaviour

**Negative:**
- Layout may shift when filters are toggled (mitigated by toolbar design)

---

## Decision 9: Toolbar Menu Buttons as UI Pattern

**Date**: 2026-02-23
**Status**: accepted

### Context

Three UI patterns were evaluated for the filter controls:
1. **Toolbar Menu Buttons** — `Menu` controls directly in the toolbar
2. **Adaptive Filter Bar** — Pill-shaped menus in a bar (toolbar on iPad/Mac, content area on iPhone portrait)
3. **Hybrid** — Different UIs per platform

A UX review, frontend design exploration, and technical research informed the decision.

### Decision

Use Toolbar Menu Buttons. Each filter type gets a `Menu` in the toolbar that adapts label density by size class: text labels with counts on regular width (iPad/Mac), icon-only with `.badge()` on compact width (iPhone portrait).

### Rationale

- Zero vertical space cost — the kanban board keeps maximum content area
- Most native iOS 26 pattern — toolbar menus with Liquid Glass grouping
- Lowest interaction cost — 2 taps to apply a filter, 0 taps to see state
- Single code path — same components everywhere, only label rendering adapts
- The adaptive filter bar would cost ~34pt of vertical space on iPhone portrait where the segmented picker already consumes space

### Alternatives Considered

- **Adaptive Filter Bar**: Richer labels on compact but costs vertical space — rejected because kanban content area is precious on iPhone
- **Hybrid (different UIs per platform)**: Doubles testing surface and creates inconsistent mental models — rejected

### Consequences

**Positive:**
- No vertical space lost on any platform
- Native Liquid Glass integration automatic
- Simple implementation — standard SwiftUI `Menu` API

**Negative:**
- On iPhone portrait, icon-only labels are less descriptive (mitigated by `.badge()` counts and filled icon variants)
- Toolbar can get crowded with 6+ items on compact width (mitigated by SwiftUI's automatic overflow handling)

---

## Decision 10: Sheet with Custom Rows for Multi-Select

**Date**: 2026-02-23
**Status**: accepted (revised 2026-02-24)

### Context

Two approaches were evaluated for the dropdown content when a filter menu is opened:
1. **Native Menu with Toggle** — `Toggle` items with `.menuActionDismissBehavior(.disabled)` for multi-select
2. **Sheet/Popover with custom rows** — Custom `List` with `Button` rows, colored `Circle().fill()` dots, and checkmark indicators

The initial implementation used native `Menu` with `Toggle`, but iOS strips custom `.foregroundStyle()` from toggle labels inside menus, removing the project and type color indicators entirely.

### Decision

Use sheet (iOS) / popover (macOS) with custom `Button` rows containing explicit `Circle().fill()` color dots and checkmark selection indicators.

### Rationale

- Native `Menu` with `Toggle` strips all custom foreground styling — colored dots are invisible
- `Circle().fill(color)` is a shape fill that renders reliably regardless of parent styling
- Sheets on iOS provide a clean half-height presentation with `.presentationDetents([.medium])`
- Popovers on macOS provide the same List+Button layout without needing sheets
- Custom `Button` rows with checkmarks match the original `FilterPopoverView` visual style

### Alternatives Considered

- **Native Menu with Toggle**: Simplest implementation — rejected because iOS strips custom foreground styles from menu items, losing color indicators entirely
- **Native Menu with Label icon foregroundStyle**: Tried explicit `Label { } icon: { Image.foregroundStyle() }` — rejected because iOS menus still override icon colors

### Consequences

**Positive:**
- Colored dots render reliably on all platforms
- Checkmark selection indicators match native iOS patterns
- Sheet presentation with drag indicator is familiar to iOS users

**Negative:**
- More code than native `Menu` — custom button rows with manual selection state
- Sheet requires explicit Done button for dismissal

---

## Decision 11: Drop Stale Milestone Display

**Date**: 2026-02-23
**Status**: accepted

### Context

The current `FilterPopoverView` tracks "stale" milestones — milestones that are selected but no longer in the open/available set. It fetches them by ID and renders them dimmed at 50% opacity, allowing the user to see and deselect them. This requires `MilestoneService.findByID()` and custom display logic.

With the move to native `Menu` with `Toggle`, custom dimmed-item rendering is not supported. Menu items are either present or not.

### Decision

Drop the stale milestone display. Stale milestones remain in the `selectedMilestones` set (acting as a filter with no matches) until the user clears the milestone filter, changes projects (triggering cascade clear), or uses Clear All.

### Rationale

- The most common staleness scenario (project filter change) is already handled by the cascade clear (`selectedMilestones.removeAll()` on project change)
- The remaining scenario (milestone closed while selected, no project change) is rare for a single-user app
- Native `Menu` items don't support dimmed/custom opacity rendering
- The user can always recover via per-filter clear or Clear All

### Alternatives Considered

- **Switch to per-pill popovers to preserve stale display**: Adds complexity for a rare edge case — rejected in favor of native menus (Decision 10)
- **Auto-clear stale milestones on menu open**: Would silently remove filter selections — rejected as potentially confusing

### Consequences

**Positive:**
- Simpler implementation
- No need for `MilestoneService.findByID()` in the filter UI

**Negative:**
- If a milestone becomes stale (non-project-related), the user sees an empty board. Mitigated by the filtered empty state overlay ("No matching tasks. Clear filters to see all tasks.") and the per-filter count badge on the milestone menu.

---

## Decision 12: Popover on macOS, Sheet on iOS

**Date**: 2026-02-23
**Status**: accepted (revised 2026-02-24)

### Context

The filter menus need a container that supports multi-select without dismissing after each tap, and that allows custom view rendering (colored dots, checkmarks). Native `Menu` on iOS strips custom styling (see Decision 10). macOS has no such limitation with popovers.

### Decision

Use platform-conditional rendering: `.sheet` with `.presentationDetents([.medium])` on iOS/iPadOS, `Button` with `.popover` on macOS. Both contain a `List` of custom `Button` rows with checkmark indicators. The toggle content and clear section are extracted into shared `@ViewBuilder` properties.

### Rationale

- Sheets on iOS provide a familiar half-height presentation that supports full custom view rendering
- Popovers on macOS stay open for multi-select and support the same custom row layout
- The shared `@ViewBuilder` extraction keeps duplication minimal — only the container (sheet vs popover) differs per platform

### Alternatives Considered

- **Native Menu on iOS**: Simpler but strips custom styling — rejected (see Decision 10)
- **Popovers everywhere**: On iPhone, popovers either become full sheets or show as tiny bubbles depending on `presentationCompactAdaptation` — rejected in favor of explicit sheet with medium detent

### Consequences

**Positive:**
- Full custom view rendering on both platforms
- Sheet with medium detent is a natural iOS pattern
- Shared content means minimal code duplication

**Negative:**
- Two rendering paths to test (sheet on iOS, popover on macOS)
- Sheet requires explicit Done button for dismissal

---

## Decision 13: Filtered Empty State

**Date**: 2026-02-23
**Status**: accepted

### Context

When filters are active but produce zero results across all columns, the board appears completely empty. The existing empty state ("No tasks yet. Tap + to create one.") only shows when there are genuinely no tasks. There is no message for the "filters are too restrictive" case.

This is especially problematic for the stale-milestone edge case (Decision 11): a milestone closed while selected produces an empty board with no explanation.

### Decision

Add a filtered empty state overlay: "No matching tasks. Clear filters to see all tasks." Shown when tasks exist but all filtered columns are empty.

### Rationale

Low implementation cost (reuses existing `EmptyStateView`), covers both the stale-milestone edge case and the general over-filtering case. Provides an actionable hint ("clear filters") rather than a blank screen.

### Alternatives Considered

- **No empty state (badges are sufficient hint)**: Rejected — a blank screen with no explanation is poor UX, especially when the cause (stale milestone) is not obvious

### Consequences

**Positive:**
- Clear explanation when over-filtering
- Covers the stale-milestone edge case from Decision 11
- Minimal implementation cost

**Negative:**
- None significant

---
