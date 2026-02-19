# Requirements: Report Functionality

## Introduction

Transit needs a report feature that lets the user review completed and abandoned work over configurable date ranges. Reports produce a structured data model that is rendered as a native SwiftUI view in the app and as Markdown text for copy-to-clipboard and the Shortcuts intent. The feature is accessible via a toolbar button on the dashboard and as a Shortcuts App Intent.

---

### 1. Report Generation

**User Story:** As a user, I want to generate a report of completed and abandoned tasks for a date range, so that I can review what I've worked on.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL generate a report containing all tasks with a terminal status (Done or Abandoned) whose `completionDate` falls within the selected date range
2. <a name="1.2"></a>The system SHALL support the following predefined date ranges with their canonical JSON tokens: Today (`today`), Yesterday (`yesterday`), This Week (`this-week`), Last Week (`last-week`), This Month (`this-month`), Last Month (`last-month`), This Year (`this-year`), Last Year (`last-year`)
3. <a name="1.3"></a>WHEN calculating week-based ranges, the system SHALL use the device's locale setting (via `Calendar.current`) to determine the first day of the week
4. <a name="1.4"></a>"This X" ranges SHALL span from the start of the current calendar period to the current moment. "Last X" ranges SHALL span the entire previous calendar period (start to end). All ranges use the device's local timezone.
5. <a name="1.5"></a>The system SHALL group tasks by their project, with each project as a section header
6. <a name="1.6"></a>The system SHALL sort project groups alphabetically by project name
7. <a name="1.7"></a>The system SHALL sort tasks within each project group by `completionDate` ascending, with `permanentDisplayId` ascending as a tie-breaker
8. <a name="1.8"></a>IF no tasks match the selected date range, the system SHALL produce a report indicating no tasks were found for that period
9. <a name="1.9"></a>Tasks with a terminal status but nil `completionDate` SHALL be excluded from reports

---

### 2. Markdown Output Format

**User Story:** As a user, I want the report in Markdown format, so that I can read it directly or paste it into other tools.

**Acceptance Criteria:**

1. <a name="2.1"></a>The system SHALL output the report as a Markdown document (GitHub Flavored Markdown for strikethrough support)
2. <a name="2.2"></a>The report SHALL include a level-1 heading with the date range label (e.g., `# Report: This Week`)
3. <a name="2.3"></a>The report SHALL include a summary section immediately after the title showing total Done count, total Abandoned count, and a per-project breakdown
4. <a name="2.4"></a>Each project group SHALL use a level-2 heading (`##`) with the project name
5. <a name="2.5"></a>Each task SHALL be rendered as a list item containing the display ID and the task name (e.g., `- T-42: Implement login`)
6. <a name="2.6"></a>Abandoned tasks SHALL be rendered with strikethrough and an explicit label (e.g., `- ~~T-5: Old feature~~ (Abandoned)`)
7. <a name="2.7"></a>User-generated content (project names, task names) SHALL be escaped to prevent Markdown formatting corruption
8. <a name="2.8"></a>The Markdown output SHALL follow this template:

```markdown
# Report: {Date Range Label}

**{total} tasks** ({done_count} done, {abandoned_count} abandoned)

## {Project Name}

{done_count} done, {abandoned_count} abandoned

- T-42: Implement login
- ~~T-5: Old feature~~ (Abandoned)

## {Another Project}

{done_count} done

- T-17: Fix dashboard layout

```

When no tasks are found:

```markdown
# Report: {Date Range Label}

No tasks completed or abandoned in this period.
```

---

### 3. UI Access

**User Story:** As a user, I want to access reports from the dashboard, so that I can quickly review my progress without navigating away from my workflow.

**Acceptance Criteria:**

1. <a name="3.1"></a>The dashboard toolbar SHALL include a button that navigates to the report view
2. <a name="3.2"></a>The report view SHALL be pushed onto the NavigationStack (consistent with existing navigation patterns)
3. <a name="3.3"></a>The report view SHALL display a date range picker allowing selection of any predefined range from [1.2](#1.2)
4. <a name="3.4"></a>The report view SHALL render the report as a native SwiftUI view using the same structured data model as the Markdown generator (not by parsing Markdown)
5. <a name="3.5"></a>The report view SHALL include a copy-to-clipboard button that copies the raw Markdown text
6. <a name="3.6"></a>WHEN the user changes the date range selection, the report SHALL regenerate immediately
7. <a name="3.7"></a>The default date range SHOULD be "This Week"

---

### 4. Shortcuts Integration

**User Story:** As a user, I want to generate reports via Shortcuts, so that I can automate report creation from the CLI or other workflows.

**Acceptance Criteria:**

1. <a name="4.1"></a>The system SHALL provide an App Intent named "Transit: Generate Report"
2. <a name="4.2"></a>The intent SHALL present a native picker parameter for date range selection, using the predefined ranges from [1.2](#1.2) via an `AppEnum`
3. <a name="4.3"></a>The intent SHALL return the Markdown report as a plain string
4. <a name="4.4"></a>The intent SHALL NOT foreground the app (`openAppWhenRun = false`) since it returns data only

---

### 5. Edge Cases

**User Story:** As a user, I want the report to handle unusual situations gracefully, so that I always get a useful output.

**Acceptance Criteria:**

1. <a name="5.1"></a>IF a task has no `permanentDisplayId` (provisional only), the system SHALL use the existing `DisplayID.formatted` representation
