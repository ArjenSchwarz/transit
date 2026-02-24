# Requirements: Filter Redesign

**Transit Ticket:** T-224
**Status:** Draft

## Introduction

The current filter system uses a single popover containing all filter types (project, task type, milestone) in a scrollable list. This has become cumbersome — users must open the popover and scroll through sections to find the filter they want, and "Clear All" is buried at the bottom of the list.

This feature replaces the single-popover filter UI with separate, dedicated controls for each filter type. Each filter should be independently accessible without needing to navigate through unrelated filters. A persistent "clear all" control should be visible whenever any filter is active, without requiring scrolling.

---

### 1. Separate Filter Controls

**User Story:** As a user, I want each filter type to have its own dedicated control, so that I can quickly access and modify a specific filter without scrolling through unrelated options.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL provide a separate, dedicated control for the project filter
2. <a name="1.2"></a>The system SHALL provide a separate, dedicated control for the task type filter
3. <a name="1.3"></a>The system SHALL provide a separate, dedicated control for the milestone filter
4. <a name="1.4"></a>Each filter control SHALL be operable independently — activating one filter SHALL NOT require interacting with another filter's control
5. <a name="1.5"></a>The filter controls SHALL support multi-selection within each filter type (same as current behaviour)
6. <a name="1.6"></a>The milestone filter SHALL scope available milestones to selected projects (cascading behaviour)
7. <a name="1.7"></a>WHEN the project filter selection changes, THEN all selected milestones SHALL be cleared
8. <a name="1.8"></a>Each filter control SHALL visually indicate when it has active selections (e.g., filled icon, badge, highlighted state)
9. <a name="1.9"></a>WHEN a filter type has no available options (e.g., no milestones exist for selected projects), THEN the filter control SHALL be hidden or disabled

---

### 2. Clear All Visibility

**User Story:** As a user, I want a clear-all control that is always visible when filters are active, so that I can reset all filters without scrolling or opening additional UI.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN one or more filters are active (project, type, milestone, or search), THEN the system SHALL display a persistent "clear all" control
2. <a name="2.2"></a>The "clear all" control SHALL be visible without scrolling or opening a popover/menu
3. <a name="2.3"></a>WHEN the user activates "clear all", THEN all project, type, milestone selections, and search text SHALL be cleared
4. <a name="2.4"></a>WHEN no filters are active, THEN the "clear all" control SHALL be hidden

---

### 3. Per-Control Filter Counts

**User Story:** As a user, I want to see how many selections are active in each filter at a glance, so that I know which filters are narrowing my view.

**Acceptance Criteria:**

1. <a name="3.1"></a>Each filter control SHALL display the number of active selections within that filter type (e.g., "Projects (2)")
2. <a name="3.2"></a>The per-control count SHALL update when selections are added or removed
3. <a name="3.3"></a>IF no selections are active in a filter, THEN the count SHALL be hidden (showing only the filter label)

---

### 4. Filter State Behaviour

**User Story:** As a user, I want filters to behave consistently regardless of the UI change, so that the redesign does not alter how filtering works.

**Acceptance Criteria:**

1. <a name="4.1"></a>Filter state SHALL remain ephemeral — all selections reset on app launch
2. <a name="4.2"></a>All filter types SHALL continue to use AND logic (intersection) — only tasks matching ALL active filters are shown
3. <a name="4.3"></a>The filtered task counts in column headers SHALL reflect the active filters
4. <a name="4.4"></a>The 48-hour cutoff for terminal tasks (Done/Abandoned) SHALL continue to apply after filter evaluation

---

### 5. Platform Adaptation

**User Story:** As a user on any Apple platform, I want the filter controls to be appropriately placed for my device, so that I can access them without difficulty.

**Acceptance Criteria:**

1. <a name="5.1"></a>The filter controls SHALL be reachable within one tap on all platforms (iPhone, iPad, Mac)
2. <a name="5.2"></a>On compact-width devices (iPhone portrait), the filter controls SHALL fit within the available toolbar or screen space without horizontal scrolling
3. <a name="5.3"></a>All interactive filter elements SHALL meet Apple HIG minimum touch target size (44pt)

---

### 6. Remove Single Filter Popover

**User Story:** As a user, I want the old combined filter popover to be removed, so that there is a single, consistent way to manage filters.

**Acceptance Criteria:**

1. <a name="6.1"></a>The single combined filter popover SHALL be replaced by the new separate controls
2. <a name="6.2"></a>There SHALL NOT be two parallel filter UIs

---

### 7. Per-Filter Clear

**User Story:** As a user, I want to clear an individual filter type without affecting the others, so that I can incrementally adjust my view.

**Acceptance Criteria:**

1. <a name="7.1"></a>Each filter control SHALL provide a way to clear its own selection
2. <a name="7.2"></a>WHEN a per-filter clear is activated, THEN only that filter type's selection SHALL be reset, EXCEPT clearing the project filter also triggers cascading milestone clear per [1.7](#1.7)
3. <a name="7.3"></a>Per-filter clear SHALL NOT affect other filter types or search text

---

### 8. Accessibility

**User Story:** As a user relying on assistive technology, I want the new filter controls to be fully accessible, so that I can manage filters with VoiceOver and keyboard navigation.

**Acceptance Criteria:**

1. <a name="8.1"></a>Each filter control SHALL have a descriptive VoiceOver label (e.g., "Project filter, 2 selected")
2. <a name="8.2"></a>Each filter control SHALL have an accessibility identifier for UI test automation
3. <a name="8.3"></a>The "clear all" control SHALL be discoverable via VoiceOver
4. <a name="8.4"></a>On macOS, all filter controls SHALL be navigable via keyboard
