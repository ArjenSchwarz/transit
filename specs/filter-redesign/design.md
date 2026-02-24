# Design: Filter Redesign

**Transit Ticket:** T-224
**Requirements:** [requirements.md](requirements.md)
**Decision Log:** [decision_log.md](decision_log.md)

## Overview

Replace the single filter popover with three separate filter controls in the toolbar — one each for projects, task types, and milestones. A conditional "Clear All" button appears in the toolbar when any filter (including search) is active.

**Platform-specific dropdown mechanism (Decision 10, 12):**
- **iOS/iPadOS:** `.sheet` with `.presentationDetents([.medium])` containing a `List` of custom `Button` rows with `Circle().fill()` color dots and checkmark indicators
- **macOS:** Per-filter popover with `List` and custom `Button` rows (same row layout as iOS)

Native `Menu` with `Toggle` was originally planned but rejected because iOS strips custom `.foregroundStyle()` from toggle labels, removing project and type color indicators entirely.

The toolbar labels adapt by size class: text labels with counts on regular width (iPad/Mac), icon-only with `.badge()` counts on compact width (iPhone portrait).

No changes to the underlying filter logic (`DashboardLogic`, `matchesFilters`). The data flow remains the same — `@State` bindings from `DashboardView` passed to the filter controls.

## Architecture

### Component Hierarchy

```
DashboardView
├── .toolbar
│   ├── ToolbarItemGroup(.primaryAction)     ← filter menus
│   │   ├── ProjectFilterMenu
│   │   ├── TypeFilterMenu
│   │   ├── MilestoneFilterMenu (conditionally hidden)
│   │   └── ClearAllButton (conditionally shown)
│   ├── ToolbarSpacer(.fixed)               ← separates filter & action glass bubbles
│   ├── ToolbarItemGroup(.primaryAction)     ← action buttons
│   │   ├── AddButton
│   │   └── ReportButton
│   ├── ToolbarSpacer(.fixed)               ← separates action & settings glass bubbles
│   └── ToolbarItem(.primaryAction)          ← settings
│       └── SettingsButton
├── .searchable(text: $searchText)           ← unchanged
├── SingleColumnView / KanbanBoardView       ← unchanged
├── .overlay { FilteredEmptyStateView }      ← NEW: shown when filters active + no results
└── .onChange(of: selectedProjectIDs)         ← clears milestones
```

### Liquid Glass Toolbar Layout

Toolbar items with the same placement group into glass bubbles. `ToolbarSpacer(.fixed)` creates visual separation.

**iPad / Mac (regular width):**

```
[ Projects (2) ▾ │ Types ▾ │ Milestones ▾ │ ✕ ]   [ + │ chart ]   │   [ gear ]
 ╰─── filter glass group ───────────────────╯     ╰── actions ──╯     ╰─ settings ─╯
```

**iPhone portrait (compact width):**

```
Transit         [ folder•2 │ tag│ flag │ ✕ ]   [ + ]   │   [ gear ]
                 ╰── filters (icon-only) ──╯   ╰─ add ─╯     ╰─ settings ─╯
```

Note: Report button moves to the action group with add. When filter count badges are active, the filled icon variant is used.

**iPhone landscape (compact height, regular width):**

Same as iPad layout — text labels, all items visible in the wide toolbar.

### Data Flow

```
DashboardView (@State)
│
├── selectedProjectIDs: Set<UUID> ──────┐
├── selectedTypes: Set<TaskType> ───────┤
├── selectedMilestones: Set<UUID> ──────┤── Bindings to filter menus
├── searchText: String ─────────────────┘   (and to .searchable)
│
├── .onChange(of: selectedProjectIDs)
│   └── selectedMilestones.removeAll()     ← cascading clear
│
├── filteredColumns (computed)
│   └── DashboardLogic.buildFilteredColumns(...)  ← unchanged
│
└── hasAnyFilter (computed)
    └── Controls ClearAll visibility
```

No new state types or models. The existing `@State` properties remain the source of truth. Filter menus receive `@Binding` parameters.

## Components and Interfaces

### 1. ProjectFilterMenu

Each filter menu uses a platform-conditional approach: sheet on iOS, popover on macOS. Both use custom `Button` rows with `Circle().fill()` color dots and checkmark indicators. The toggle content is extracted to a shared `@ViewBuilder` method to avoid duplication.

```swift
struct ProjectFilterMenu: View {
    let projects: [Project]
    @Binding var selectedProjectIDs: Set<UUID>
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showPopover = false

    var body: some View {
        Button { showPopover.toggle() } label: { filterLabel }
            #if os(macOS)
            .popover(isPresented: $showPopover) {
                List { Section { toggleContent } clearSection }
                    .frame(minWidth: 220, minHeight: 200)
            }
            #else
            .sheet(isPresented: $showPopover) {
                NavigationStack {
                    List { Section { toggleContent } clearSection }
                        .navigationTitle("Projects")
                        .toolbarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showPopover = false }
                            }
                        }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            #endif
    }

    @ViewBuilder
    private var toggleContent: some View {
        ForEach(projects) { project in
            Button {
                toggleBinding(for: project.id).wrappedValue.toggle()
            } label: {
                HStack {
                    Circle().fill(Color(hex: project.colorHex))
                        .frame(width: 12, height: 12)
                    Text(project.name).foregroundStyle(.primary)
                    Spacer()
                    if selectedProjectIDs.contains(project.id) {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    // clearSection, filterLabel, toggleBinding omitted for brevity
}
```

**Key details:**
- **iOS:** `.sheet` with `.presentationDetents([.medium])` stays open for rapid multi-select [req 1.5]. Done button provides explicit dismissal.
- **macOS:** `Button` opening a `.popover` with a `List`. The popover stays open until dismissed [req 1.5, Decision 12]
- `toggleContent` and `clearSection` are shared between both platforms — no logic duplication
- `Circle().fill(color)` renders reliably regardless of parent styling — unlike `.foregroundStyle()` on `Label` inside native `Menu`
- Compact size class uses icon-only label with `.badge()` (iOS 26 API) [req 5.2]
- Regular size class uses text label with count [req 3.1]

### 2. TypeFilterMenu

Same sheet/popover pattern as `ProjectFilterMenu`. Row content iterates `TaskType.allCases` with `Circle().fill(type.tintColor)` color dots. Label uses SF Symbol `tag` / `tag.fill`.

### 3. MilestoneFilterMenu

Same sheet/popover pattern. Scoped to selected projects. Hidden when no milestones are available [req 1.9]. Milestones have no color dots — plain text with checkmarks.

**Additional details beyond the shared pattern:**
- The entire view is conditionally rendered: hidden when `availableMilestones` is empty AND no milestones are selected [req 1.9]. The `|| !selectedMilestones.isEmpty` check handles the edge case where milestones are selected but their project was deselected before `.onChange` fires.
- `availableMilestones` computed from `milestoneService.milestonesForProject()`, scoped by `selectedProjectIDs` [req 1.6]
- `selectedProjectIDs` is passed as a `let` (read-only) — milestone clearing happens via `.onChange` in `DashboardView` [req 1.7]
- Label uses SF Symbol `flag` / `flag.fill`
- Milestone display: use `milestone.name` when scoped to a single project, `milestone.displayName` (includes project prefix) when showing across multiple projects

### 4. ClearAllButton

A toolbar button that appears when any filter is active. Clears all filters including search text [req 2.3, Decision 5].

```swift
@ViewBuilder
private var clearAllButton: some View {
    if hasAnyFilter {
        Button {
            selectedProjectIDs.removeAll()
            selectedTypes.removeAll()
            selectedMilestones.removeAll()
            searchText = ""
        } label: {
            Label("Clear All", systemImage: "xmark.circle.fill")
        }
        .accessibilityIdentifier("dashboard.clearAllFilters")
        .accessibilityLabel("Clear all filters")
    }
}
```

Where `hasAnyFilter` is:

```swift
private var hasAnyFilter: Bool {
    !selectedProjectIDs.isEmpty
        || !selectedTypes.isEmpty
        || !selectedMilestones.isEmpty
        || !effectiveSearchText.isEmpty
}
```

This lives in `DashboardView` (not extracted to a separate file) since it needs direct access to all filter state and `searchText`.

### 5. Updated DashboardView Toolbar

The toolbar section of `DashboardView` is restructured:

```swift
.toolbar {
    ToolbarItemGroup(placement: .primaryAction) {
        ProjectFilterMenu(
            projects: projects,
            selectedProjectIDs: $selectedProjectIDs
        )
        TypeFilterMenu(selectedTypes: $selectedTypes)
        MilestoneFilterMenu(
            projects: projects,
            selectedProjectIDs: selectedProjectIDs,
            selectedMilestones: $selectedMilestones
        )
        clearAllButton
    }

    ToolbarSpacer(.fixed)  // separates filter bubble from action bubble

    ToolbarItemGroup(placement: .primaryAction) {
        addButton
        NavigationLink(value: NavigationDestination.report) {
            Label("Report", systemImage: "chart.bar.doc.horizontal")
        }
        .accessibilityIdentifier("dashboard.reportButton")
    }

    ToolbarSpacer(.fixed)  // separates action bubble from settings bubble

    ToolbarItem(placement: .primaryAction) {
        NavigationLink(value: NavigationDestination.settings) {
            Label("Settings", systemImage: "gear")
        }
        .accessibilityIdentifier("dashboard.settingsButton")
    }
}
// MIGRATION: move .onChange from deleted FilterPopoverView into DashboardView body
.onChange(of: selectedProjectIDs) { _, _ in
    selectedMilestones.removeAll()
}
```

### Removed Components

- `FilterPopoverView.swift` — deleted entirely [req 6.1]
- `filterButton` computed property in `DashboardView` — removed
- `showFilter` state variable — removed
- `activeFilterCount` computed property — removed (replaced by per-control counts)
- `activeFilterAccessibilityValue` — removed

### 6. Filtered Empty State

When filters are active but produce zero results across all columns, show an explanatory overlay. This covers the stale-milestone edge case (Decision 11) and the general over-filtering case.

```swift
// In DashboardView, alongside the existing empty state overlay:
.overlay {
    if allTasks.isEmpty {
        EmptyStateView(message: "No tasks yet. Tap + to create one.")
    } else if hasAnyFilter && filteredColumns.values.allSatisfy(\.isEmpty) {
        EmptyStateView(message: "No matching tasks.\nClear filters to see all tasks.")
    }
}
```

This reuses the existing `EmptyStateView` component. The condition checks that tasks exist (`!allTasks.isEmpty`) but all filtered columns are empty, ensuring it only shows when filters are the cause of the empty board.

## Data Models

No new data models. The filter state remains as existing `@State` properties on `DashboardView`:

| Property | Type | Purpose |
|----------|------|---------|
| `selectedProjectIDs` | `Set<UUID>` | Selected project IDs |
| `selectedTypes` | `Set<TaskType>` | Selected task types |
| `selectedMilestones` | `Set<UUID>` | Selected milestone IDs |
| `searchText` | `String` | Search text (managed by `.searchable`) |

### Binding Helper

Each filter menu needs to create a `Binding<Bool>` from a `Set` for use with `Toggle`. The code samples above use a `contains(_:)` subscript on `Binding<Set<T>>`. This is implemented as a generic extension:

```swift
extension Binding {
    /// Creates a Bool binding that toggles membership of `element` in a Set.
    /// Usage: Toggle(isOn: $selectedIDs.contains(item.id)) { ... }
    func contains<Element: Hashable>(_ element: Element) -> Binding<Bool>
    where Value == Set<Element> {
        Binding<Bool>(
            get: { wrappedValue.contains(element) },
            set: { isOn in
                if isOn {
                    wrappedValue.insert(element)
                } else {
                    wrappedValue.remove(element)
                }
            }
        )
    }
}
```

This single extension handles both `Set<UUID>` and `Set<TaskType>` via the generic `Element: Hashable` constraint.

## Error Handling

This feature has minimal error surface — it's a pure UI restructuring with no network calls, persistence, or complex state transitions.

| Scenario | Handling |
|----------|----------|
| No projects exist | ProjectFilterMenu shows empty menu (no items). Toolbar icon is still visible. |
| No milestones exist | MilestoneFilterMenu is hidden entirely [req 1.9] |
| Milestones become stale (closed while selected) | Cleared automatically via `.onChange(of: selectedProjectIDs)`. For non-project-triggered staleness, the milestone won't appear in the menu but remains in the selection — it acts as a filter with no matches. The user can clear it via per-filter clear or Clear All. **Note:** The current popover shows stale milestones dimmed. The new design drops this display — see Decision 11. |
| Toolbar overflow on compact devices | SwiftUI handles overflow automatically — excess items move to a "..." overflow menu. Worst case (all 7 items visible) requires milestones existing AND filters active. Prototype on iPhone SE (375pt) during implementation. If overflow occurs, move Report to `.secondaryAction` placement. |
| Filters active but zero results | Filtered empty state overlay shows "No matching tasks. Clear filters to see all tasks." |

## Testing Strategy

### Unit Tests (Swift Testing, `make test-quick`)

The underlying filter logic (`DashboardLogic.buildFilteredColumns`, `matchesFilters`) is unchanged. Existing `DashboardFilterTests` continue to cover filter behaviour. No new unit tests needed for filter logic.

**New unit tests for binding helpers:**

| Test | Verifies |
|------|----------|
| `toggleBinding_insertsOnTrue` | Setting binding to `true` inserts element into set |
| `toggleBinding_removesOnFalse` | Setting binding to `false` removes element from set |
| `toggleBinding_reflectsCurrentState` | Getting binding returns `true` when element is in set |

### UI Tests (Xcode UI Testing, `make test-ui`)

Existing UI tests reference `accessibilityIdentifier("dashboard.filterButton")` which will be removed. These tests need updating.

**Updated UI tests:**

| Test | Action | Verification |
|------|--------|--------------|
| `testProjectFilterMenu` | Tap project filter icon → toggle a project → verify board filters | Tasks for unselected projects are hidden |
| `testTypeFilterMenu` | Tap type filter icon → toggle "bug" → verify board filters | Only bug tasks shown |
| `testMilestoneFilterMenu` | Select a project → tap milestone filter → toggle a milestone | Board shows only tasks with that milestone |
| `testClearAll` | Apply multiple filters → tap clear all button | All filters cleared, full board restored, search text cleared |
| `testMilestoneHiddenWhenNoMilestones` | No milestones seeded → verify milestone filter not present | `dashboard.filter.milestones` does not exist |
| `testMilestoneClearedOnProjectChange` | Select milestone → change project filter | Milestone selection is cleared |
| `testPerFilterClear` | Apply project filter → open project menu → tap Clear | Project filter cleared, other filters unchanged |

**Accessibility identifiers for new components:**

| Identifier | Component |
|------------|-----------|
| `dashboard.filter.projects` | Project filter menu |
| `dashboard.filter.types` | Type filter menu |
| `dashboard.filter.milestones` | Milestone filter menu |
| `dashboard.clearAllFilters` | Clear all button |

### Manual Testing Checklist

- [ ] iPad: all three filter menus visible with text labels and counts
- [ ] iPhone portrait: icon-only filter menus with badge counts
- [ ] iPhone landscape: text labels (same as iPad)
- [ ] Mac: filter popovers work with mouse click and keyboard navigation
- [ ] Mac: popover stays open for multi-select (no dismiss-per-toggle)
- [ ] VoiceOver: each filter menu is announced with label and value
- [ ] Multi-select (iOS): menu stays open when toggling items
- [ ] Clear button in menu: dismisses the menu
- [ ] Clear All: clears all filters and search text
- [ ] Milestone menu: hidden when no milestones exist
- [ ] Milestone cascading: milestones cleared when project filter changes
- [ ] Drag-and-drop: still works with filtered board (no regression)
- [ ] Filtered empty state: shown when filters active but no tasks match
- [ ] Toolbar overflow: test on iPhone SE (375pt) with all filters visible
- [ ] Glass grouping: three separate glass bubbles (filters, actions, settings)

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `Views/Dashboard/ProjectFilterMenu.swift` | Create | Project filter toolbar menu |
| `Views/Dashboard/TypeFilterMenu.swift` | Create | Task type filter toolbar menu |
| `Views/Dashboard/MilestoneFilterMenu.swift` | Create | Milestone filter toolbar menu |
| `Views/Dashboard/DashboardView.swift` | Modify | Replace filter button/popover with menu components, add clearAllButton, update toolbar layout. **Migration:** move `.onChange(of: selectedProjectIDs)` from the deleted FilterPopoverView into DashboardView body. |
| `Views/Dashboard/FilterPopoverView.swift` | Delete | Replaced by individual menus |
| `Extensions/Binding+ToggleSet.swift` | Create | `Binding<Set<T>>` toggle helpers |
| `TransitTests/BindingToggleSetTests.swift` | Create | Unit tests for binding helpers |
| `TransitUITests/` | Modify | Update filter UI tests for new accessibility identifiers |
