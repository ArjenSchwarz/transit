# Decision Log: Shortcuts-Friendly Intents

## Decision 1: Feature Naming

**Date**: 2026-02-11
**Status**: accepted

### Context

The feature adds Shortcuts-friendly App Intents with visual UI elements alongside the existing JSON-based CLI intents. A clear feature name is needed for the spec directory and documentation.

### Decision

Use "shortcuts-friendly-intents" as the feature name.

### Rationale

This name clearly distinguishes the new Shortcuts UI-based intents from the existing JSON-based CLI intents. It communicates the primary goal: making Transit more accessible to Shortcuts users who prefer visual interfaces over JSON input.

### Alternatives Considered

- **intent-enhancements-v2**: Generic version-based naming - Rejected because it doesn't communicate what makes this version different
- **visual-app-intents**: Emphasizes the visual/UI parameter approach - Rejected because "visual" is less specific than "shortcuts-friendly" about the target user experience

### Consequences

**Positive:**
- Clear differentiation from CLI-focused intents
- Communicates user-facing benefit (Shortcuts compatibility)
- Aligns with Apple's Shortcuts terminology

**Negative:**
- Slightly longer name than alternatives

---

## Decision 2: Backward Compatibility Strategy

**Date**: 2026-02-11
**Status**: accepted

### Context

The existing JSON-based intents (`QueryTasksIntent`, `CreateTaskIntent`, `UpdateStatusIntent`) are used by CLI automation tools. We need to decide whether to replace them, deprecate them, or keep both versions.

### Decision

Keep both JSON-based and visual intents available simultaneously without deprecation.

### Rationale

Maintaining both versions ensures existing CLI automations continue working unchanged while providing a better experience for Shortcuts users. There is no technical cost to supporting both approaches, and they serve different user needs (programmatic vs interactive).

### Alternatives Considered

- **Replace JSON intents**: Remove JSON-based intents entirely - Rejected because it breaks existing CLI integrations and forces migration
- **Deprecate JSON intents**: Mark JSON intents as deprecated but keep them working - Rejected because JSON is still the best interface for CLI use; deprecation implies it's inferior

### Consequences

**Positive:**
- Zero breaking changes for existing users
- CLI users get the best interface for their use case (JSON)
- Shortcuts users get the best interface for their use case (visual)
- No forced migration work

**Negative:**
- Two parallel intent implementations to maintain
- Slightly larger API surface area

---

## Decision 3: Date Filtering Capabilities

**Date**: 2026-02-11
**Status**: accepted

### Context

Users need to filter tasks by `completionDate` and `lastStatusChangeDate`. We need to decide what types of date filtering to support.

### Decision

Support both relative date ranges (today, this week, this month) and absolute date ranges (from/to ISO 8601 dates).

### Rationale

Relative dates are more convenient for common use cases ("show me tasks completed today"), while absolute dates enable precise historical queries and scheduled automations. Supporting both provides maximum flexibility without significant implementation complexity.

### Alternatives Considered

- **Relative dates only**: Pre-defined relative time ranges - Rejected because it limits precision for historical queries
- **Absolute dates only**: User-specified exact dates - Rejected because it's less convenient for common queries like "today"
- **Last N days/hours only**: Flexible recent time window - Considered as addition but decided against to keep initial implementation simpler

### Consequences

**Positive:**
- Convenient for common cases (relative dates)
- Flexible for precise queries (absolute dates)
- Covers both interactive and automation use cases

**Negative:**
- More implementation complexity than single approach
- More parameters to document and test

---

## Decision 4: Task Creation Initial Status

**Date**: 2026-02-11
**Status**: accepted

### Context

The visual task creation intent needs to determine whether users can choose the initial task status or if it should match the existing CLI behavior (always Idea).

### Decision

Always create tasks in "Idea" status, matching existing CLI behavior. Do not provide a status selection dropdown.

### Rationale

Consistency with the existing `CreateTaskIntent` reduces cognitive overhead and ensures predictable behavior regardless of how tasks are created. The status can be changed immediately after creation using the existing `UpdateStatusIntent` or the app UI.

### Alternatives Considered

- **Allow status selection**: Let users choose the initial status from a dropdown - Rejected because it creates inconsistency with CLI and adds complexity to the creation flow

### Consequences

**Positive:**
- Consistent behavior across all task creation methods
- Simpler creation interface (fewer parameters)
- Matches user mental model (tasks start as ideas, then progress)

**Negative:**
- Requires separate step to set status if user wants something other than Idea

---

## Decision 5: Search Intent Output Format

**Date**: 2026-02-11
**Status**: accepted

### Context

The visual search intent needs to determine what format to return when used in Shortcuts - structured data, human-readable text, or both.

### Decision

Return structured task array for automation use. Do not provide human-readable summary option.

### Rationale

Shortcuts is primarily an automation tool. Structured data enables users to build complex workflows that process task information, filter results further, or combine with other data sources. Users who want human-readable output can use Shortcuts' built-in formatting actions on the structured data.

### Alternatives Considered

- **Human-readable summary text**: Return formatted text showing task count and details - Rejected because it limits automation capabilities and can't be processed further
- **Both (configurable output format)**: Let users choose between structured data or summary text - Rejected to avoid complexity; structured data can be formatted to text but not vice versa

### Consequences

**Positive:**
- Maximum flexibility for automation workflows
- Can be transformed to any desired format using Shortcuts actions
- Consistent with Shortcuts' automation-first philosophy

**Negative:**
- Users wanting simple text output must add formatting steps

---

## Decision 6: Empty Projects Handling

**Date**: 2026-02-11
**Status**: accepted

### Context

The visual task creation intent requires a project selection. We need to decide what happens when no projects exist in the database.

### Decision

Show an error message with code `NO_PROJECTS` requiring at least one project before creating tasks.

### Rationale

In Transit's data model, every task belongs to exactly one project (required relationship). Allowing task creation without projects would violate this constraint. Showing an error with clear guidance ("Create a project in Transit first") educates users about the data model and ensures data integrity.

### Alternatives Considered

- **Provide 'No Project' option**: Allow task creation without a project (project field optional) - Rejected because it violates the data model constraint that every task must have a project
- **Auto-create default project**: Create a 'Default' or 'Inbox' project if none exist - Rejected because it creates unexpected side effects and pollutes the project list

### Consequences

**Positive:**
- Maintains data integrity (task-project relationship enforced)
- Clear user education about data model
- No unexpected side effects

**Negative:**
- Extra step for new users (must create project first)
- Additional error case to handle and test

---

## Decision 7: Empty Search Results Handling

**Date**: 2026-02-11
**Status**: accepted

### Context

The visual search intent needs to determine how to handle cases where no tasks match the filter criteria.

### Decision

Return an empty array `[]` and let Shortcuts handle the empty case.

### Rationale

Returning an empty array is the standard convention for search/filter operations that find no results. It allows Shortcuts users to use standard control flow (If/Otherwise) to handle empty results. This is more flexible than returning an error, which would interrupt automation flow.

### Alternatives Considered

- **Return error/message**: Return an error indicating no tasks found - Rejected because "no results" is not an error condition; it's a valid outcome
- **Return empty array with metadata**: Return empty array plus metadata like filter criteria - Rejected to keep implementation simple; metadata can be tracked separately in Shortcuts if needed

### Consequences

**Positive:**
- Standard convention for search operations
- Works naturally with Shortcuts control flow
- "No results" is treated as valid outcome, not error

**Negative:**
- None significant

---

## Decision 8: Intent Naming Convention

**Date**: 2026-02-11
**Status**: accepted

### Context

The new visual intents need user-visible names that appear in the Shortcuts app. Names should be clear, concise, and distinguish them from the existing JSON-based intents.

### Decision

Use "Transit: Add Task" for task creation and "Transit: Find Tasks" for search.

### Rationale

- "Add Task" uses a more conversational verb than "Create" to differentiate from the JSON-based "Transit: Create Task"
- "Find Tasks" is more natural and user-friendly than "Query" or "Search"
- Both names clearly convey the intent's purpose
- Consistent "Transit:" prefix maintains branding

### Alternatives Considered

- **Transit: Create Task (Visual)**: Add '(Visual)' suffix to distinguish from JSON version - Rejected because it's verbose and exposes implementation details users don't care about
- **Transit: New Task**: Shorter, more natural name different from 'Create Task' - Rejected because "Add" is more common in iOS/macOS interfaces
- **Transit: Search Tasks / Filter Tasks**: Alternative search names - Rejected because "Find" is more natural and conversational

### Consequences

**Positive:**
- Clear, concise intent names
- Natural language that matches user mental models
- Distinct from JSON-based intent names

**Negative:**
- Slight inconsistency in verb choice (Add vs Create) but this is intentional for differentiation

---

## Decision 9: TaskEntity and Structured Return Types

**Date**: 2026-02-11
**Status**: accepted

### Context

The requirements initially specified returning "structured task objects" without defining the concrete App Intents type. This left implementation details ambiguous - should it return `AppEntity` instances, a custom struct, or some other type?

### Decision

Define explicit `TaskEntity` struct conforming to `AppEntity` for Find Tasks results, and `TaskCreationResult` struct for Add Task results. Both use standard Swift types (String, Int, Date) that Shortcuts can natively serialize.

### Rationale

App Intents requires specific return type conformances for Shortcuts compatibility. By defining these types explicitly in requirements, we ensure the implementation creates the correct architecture from the start. Using `AppEntity` for TaskEntity enables future extensions like entity queries and detail views. Using simple `Codable` structs avoids overcomplicating single-use return types.

### Alternatives Considered

- **Return JSON strings from visual intents**: Match existing CLI pattern - Rejected because it defeats the purpose of "Shortcuts-friendly" visual intents
- **Use TransitTask model directly**: Return SwiftData model objects - Rejected because SwiftData models aren't Codable and contain CloudKit implementation details
- **Generic "structured objects" without specification**: Leave implementation to decide - Rejected because it creates ambiguity and potential rework

### Consequences

**Positive:**
- Clear implementation path with correct type conformances
- Shortcuts can display task properties natively
- Can extend TaskEntity with additional AppEntity features later
- Type-safe interface

**Negative:**
- Additional struct definitions to maintain
- Need to map between TransitTask and TaskEntity

---

## Decision 10: supportedModes Differentiation

**Date**: 2026-02-11
**Status**: accepted

### Context

The initial requirements specified that all intents should open the app after execution (matching existing behavior). However, "Find Tasks" is a query operation designed for automation workflows, and forcing the app to foreground breaks background Shortcuts execution.

In iOS 26, the `openAppWhenRun` property is deprecated in favor of `supportedModes`, which provides finer-grained control over foreground/background execution.

### Decision

Set `supportedModes` to include `.foreground` for "Add Task" (users likely want to see created tasks) and `.background` only for "Find Tasks" (automation/query intent).

### Rationale

Different intents serve different purposes. Task creation is often a user-initiated action where seeing the result in the app is helpful. Task search is typically part of automation chains where opening the app disrupts the workflow. Using `supportedModes` follows the iOS 26 API and provides the best experience for each use case.

### Alternatives Considered

- **Always open app (original requirement)**: Consistent with existing intents - Rejected because it breaks background automation for Find Tasks
- **Never open app**: Keep all intents in background - Rejected because users creating tasks likely want visual confirmation
- **Make it a configurable parameter**: Add boolean parameter to each intent - Rejected to avoid complexity; the sensible default differs by intent type

### Consequences

**Positive:**
- Find Tasks works in background automation workflows
- Add Task provides visual confirmation of creation
- Each intent optimized for its primary use case
- Uses modern iOS 26 API instead of deprecated property

**Negative:**
- Inconsistency between intents (but intentional)
- Add Task users who want background operation must manually close app

---

## Decision 11: Error Handling Strategy for Visual Intents

**Date**: 2026-02-11
**Status**: accepted

### Context

The initial requirements specified that visual intents should "return structured error objects (not thrown exceptions)" matching the JSON intent pattern. However, App Intents conventions for visual Shortcuts intents use thrown errors that Shortcuts displays natively, not error objects embedded in success responses.

### Decision

JSON-based intents continue to return error objects as JSON strings (existing behavior). Visual intents throw typed errors that Shortcuts can display natively.

### Rationale

Each interface should follow its platform's conventions. JSON intents return error strings because CLI callers need parseable output. Visual Shortcuts intents should throw errors because Shortcuts has native error handling UI. Embedding errors in success responses creates awkward APIs where callers must check if the "success" result is actually an error.

### Alternatives Considered

- **Use error objects for all intents**: Consistent error handling across all intents - Rejected because it creates poor UX in Shortcuts and ignores platform conventions
- **Throw errors for all intents**: Use native Swift error handling everywhere - Rejected because JSON intents need string output for CLI parsing

### Consequences

**Positive:**
- Each interface follows its platform's conventions
- Shortcuts displays errors natively with system UI
- Cleaner API for visual intents (success is truly success)
- JSON intents remain compatible with existing CLI tools

**Negative:**
- Different error handling approaches for different intent types
- Slightly more code to maintain two error patterns

---

## Decision 12: Timezone Handling for JSON API

**Date**: 2026-02-11
**Status**: accepted

### Context

The date filtering requirements specified timezone behavior for visual intents but not for the JSON-based QueryTasksIntent. Absolute date strings (YYYY-MM-DD) are inherently timezone-ambiguous, which matters for CLI automation scripts that might run in different contexts.

### Decision

All YYYY-MM-DD date strings in both JSON and visual intents are interpreted in the user's local timezone using `Calendar.current`.

### Rationale

Consistency across all intents reduces confusion. Using the device's local timezone (`Calendar.current`) ensures that "2026-02-11" means the same day regardless of which intent is called. For CLI scripts, this means the date is interpreted relative to where the device/script is running, which is the most intuitive behavior.

### Alternatives Considered

- **Use UTC for JSON API**: Canonical timezone for programmatic access - Rejected because it creates inconsistency with visual intents and is less intuitive
- **Require full ISO 8601 with timezone**: Force explicit timezone in dates - Rejected because it's more complex for users and breaks the YYYY-MM-DD format

### Consequences

**Positive:**
- Consistent behavior across all intents
- Intuitive interpretation (date relative to device location)
- Simple date format (YYYY-MM-DD)

**Negative:**
- CLI scripts running on devices in different timezones get different results for the same date string
- No way to specify absolute UTC dates (could add later if needed)

---

## Decision 13: Calendar.current for "this-week" Definition

**Date**: 2026-02-11
**Status**: accepted

### Context

The initial requirement specified "this-week" as "Monday 00:00:00 to current moment" but also said to use `Calendar.current` for all date calculations. `Calendar.current` respects user locale settings for first day of week (Sunday in US, Monday in most of Europe), creating a conflict.

### Decision

"this-week" is defined as the current calendar week per the user's locale settings (`Calendar.current`'s first weekday) from 00:00:00 to the current moment.

### Rationale

Respecting user locale provides the most intuitive behavior. Users in the US expect weeks starting Sunday, users in Europe expect Monday. `Calendar.current` handles this automatically. Hardcoding Monday would feel wrong to US users and would be inconsistent with how the system calendar works.

### Alternatives Considered

- **Hardcode Monday**: Always use Monday regardless of locale - Rejected because it ignores user locale preferences and feels wrong to US users
- **Use last-7-days instead**: Avoid the locale issue entirely - Rejected because it changes the meaning of "this-week" to a rolling window

### Consequences

**Positive:**
- Respects user locale and calendar preferences
- Consistent with system calendar behavior
- Intuitive for all users regardless of location

**Negative:**
- "this-week" means different date ranges for users in different locales
- Potentially confusing for international teams sharing Shortcuts

---

## Decision 14: Result Set Limit for Find Tasks

**Date**: 2026-02-11
**Status**: accepted

### Context

The initial requirements allowed Find Tasks to return all tasks when no filters are specified. For a single-user task tracker, this is likely fine, but could cause performance issues if a user accumulates thousands of tasks.

### Decision

Limit Find Tasks results to a maximum of 200 tasks.

### Rationale

A sensible default limit provides insurance against performance issues with minimal cost. 200 tasks is far more than most users will need in a single Shortcuts automation, while still being a reasonable upper bound. For Transit (single-user tracker), even power users are unlikely to hit this limit in practice.

### Alternatives Considered

- **No limit**: Return all tasks - Rejected to avoid potential performance issues
- **Pagination**: Add offset/limit parameters - Rejected as overengineering for V1 of single-user app
- **Higher limit (500-1000)**: More permissive - Rejected because 200 is already generous for automation use cases

### Consequences

**Positive:**
- Prevents performance issues with large task sets
- Forces users to think about filtering for better automation design
- Low implementation cost

**Negative:**
- Users with >200 tasks matching filters get truncated results
- No way to access tasks beyond the limit (would need pagination)

---

## Decision 15: TaskType Enum as Source of Truth

**Date**: 2026-02-11
**Status**: accepted

### Context

The initial requirement 2.4 listed task type values as "bug, feature, chore, research, documentation" directly in the requirements. This hardcodes values that should come from the existing `TaskType` enum, creating a maintenance risk if the enum is extended.

### Decision

Change requirement 2.4 to reference "values sourced from the TaskType enum" instead of listing literals.

### Rationale

The enum is the authoritative source of valid task types. Listing values in requirements creates duplication and risks them drifting out of sync if the enum changes. Referencing the enum ensures consistency and makes it clear where the values come from.

### Alternatives Considered

- **Keep hardcoded list**: Explicitly document current values - Rejected because it creates maintenance burden
- **Define values in requirements only**: Make requirements the source of truth - Rejected because the enum already exists in the codebase

### Consequences

**Positive:**
- Single source of truth for task type values
- No drift between requirements and implementation
- Clear where values come from

**Negative:**
- Requirements don't explicitly show what the values are (must refer to enum)

---

## Decision 16: Nested Conditional Parameters for Dual Date Filters

**Date**: 2026-02-11
**Status**: accepted

### Context

FindTasksIntent supports filtering by both completion date and last changed date. Each filter can use relative dates (today, this-week, this-month) or custom date ranges. When a user selects custom-range for either filter, additional from/to date picker parameters must appear. If both filters use custom-range simultaneously, the UI needs to show 4 date pickers total.

### Decision

Use nested `When` clauses in `ParameterSummary` to conditionally display the correct combination of date pickers based on which filters are set to custom-range.

### Rationale

App Intents' `ParameterSummary` supports nested `When` clauses, allowing us to handle all four cases:
1. Neither filter uses custom-range → show no date pickers
2. Only completion uses custom-range → show completionFrom/completionTo
3. Only lastChanged uses custom-range → show lastChangedFrom/lastChangedTo
4. Both use custom-range → show all 4 date pickers

This provides maximum flexibility while maintaining clear UX.

### Alternatives Considered

- **Make filters mutually exclusive**: Only allow one date filter at a time - Rejected because users may want to find tasks completed today that were also changed this week
- **Always show all date pickers**: Display from/to for both filters regardless of selection - Rejected because it clutters the UI with 4 unused parameters when using relative dates
- **Use separate intents**: Create FindByCompletionDate and FindByLastChanged intents - Rejected because it fragments the search experience

### Consequences

**Positive:**
- Supports all valid filter combinations
- Clean UI that only shows relevant parameters
- Follows App Intents best practices

**Negative:**
- More complex ParameterSummary code (nested When clauses)
- 4 date pickers visible when both use custom-range (potentially overwhelming)

---

## Decision 17: Exclude Metadata from Visual AddTaskIntent

**Date**: 2026-02-11
**Status**: accepted (revised)

### Context

The initial design included an optional metadata parameter in AddTaskIntent using "key=value,key2=value2" format. However, this format is fragile and breaks when values contain commas or equals signs (e.g., `description=Fix bug, add tests` would be incorrectly parsed). Proper escaping or quoting would add complexity that defeats the "Shortcuts-friendly" purpose.

### Decision

Remove the metadata parameter from AddTaskIntent entirely. Metadata remains available via the JSON-based CreateTaskIntent where it works naturally as a JSON object.

### Rationale

Metadata is a power-user feature primarily used by CLI/agent integrations, as evidenced by the reserved `git.`, `ci.`, and `agent.` namespace prefixes. Shortcuts users creating tasks interactively are unlikely to need metadata. Removing the parameter eliminates a fragile parsing problem while keeping the feature available where it's actually used (JSON API).

### Alternatives Considered

- **Add proper escaping**: Support quoted strings like `key="value,with,commas"` - Rejected because it adds complexity and still requires users to understand escaping rules
- **Use JSON string input**: Accept metadata as JSON text - Rejected because it defeats the "Shortcuts-friendly" purpose (users would type JSON in a text field)
- **Constrain allowed characters**: Disallow commas and equals in values - Rejected because it's overly restrictive and still needs validation

### Consequences

**Positive:**
- Eliminates fragile parsing edge cases
- Simpler parameter list for visual intent
- Clear separation: metadata for power users (JSON API), simple fields for interactive users (visual API)

**Negative:**
- Shortcuts users cannot set metadata (acceptable given low usage)
- Requires two intents if a user needs both visual UI and metadata (can work around by using JSON intent)

---

## Decision 18: TaskEntity Factory Method Error Handling

**Date**: 2026-02-11
**Status**: accepted

### Context

TaskEntity.from(_:) converts SwiftData TransitTask models to AppEntity structs. The project relationship is required in the data model, but SwiftData represents it as optional due to CloudKit compatibility. The initial design used a fallback UUID when project was nil, which would never occur in valid data but could hide data integrity issues.

### Decision

Make `from(_:)` a throwing function that raises `VisualIntentError` if project is nil, indicating a data integrity issue.

### Rationale

If a task has no project, it represents a critical data integrity violation. Using a fallback UUID would create a broken entity that can't be resolved by ProjectEntityQuery. Throwing an error surfaces the problem immediately and prevents propagating corrupt data through the intent system.

### Alternatives Considered

- **Use fallback UUID**: Continue with `project?.id ?? UUID()` - Rejected because it hides data integrity issues and creates unresolvable entities
- **Filter out nil projects**: Skip tasks without projects in EntityQuery - Rejected because it silently drops data without user awareness
- **Make project optional in TaskEntity**: Allow nil projectId - Rejected because it violates the business rule that all tasks must have a project

### Consequences

**Positive:**
- Surfaces data integrity issues immediately
- Fails fast rather than propagating corrupt data
- Forces investigation of how a task could lack a project

**Negative:**
- Intent fails if any task has nil project (cascading failure)
- Requires error handling in all callers of from(_:)

---

## Decision 19: SwiftData Predicate Limitations - Fetch-Then-Filter Pattern

**Date**: 2026-02-11
**Status**: accepted

### Context

TaskEntityQuery.entities(for:) needs to find tasks by an array of UUIDs. SwiftData's `#Predicate` macro has limitations with dynamic array membership checks (`array.contains(value)`) and may not compile or may have runtime issues.

### Decision

Fetch all tasks with an unfiltered FetchDescriptor, then filter in-memory using standard Swift collection methods.

### Rationale

While less efficient than a database-level predicate, this approach is simple, reliable, and safe from SwiftData predicate limitations. For a single-user task tracker with tens to hundreds of tasks, the performance cost is negligible. EntityQuery is called only when Shortcuts displays parameter pickers (user-initiated, infrequent).

### Alternatives Considered

- **Generate OR-ed predicates**: Build `task.id == uuid1 || task.id == uuid2 || ...` - Rejected because it's complex and has limits on predicate expression count
- **Use separate queries**: Fetch each UUID individually - Rejected because it multiplies database round-trips
- **Trust SwiftData predicate with array**: Use `#Predicate { uuids.contains($0.id) }` - Rejected due to known SwiftData limitations

### Consequences

**Positive:**
- Simple, readable code
- Avoids SwiftData predicate edge cases
- Works reliably across all SwiftData versions

**Negative:**
- Less efficient (fetch all, filter in-memory)
- Doesn't scale to thousands of tasks (acceptable for single-user app)

---

## Decision 20: JSON Date Filter Precedence Rules

**Date**: 2026-02-11
**Status**: accepted

### Context

The JSON API for date filtering accepts either relative dates (`"relative": "today"`) or absolute dates (`"from": "2026-02-01", "to": "2026-02-11"`). The design didn't specify what happens if both are present in the same filter object.

### Decision

If both `relative` and absolute dates are present, `relative` takes precedence and absolute dates are ignored.

### Rationale

Relative dates are simpler and more commonly used. If a user specifies both, they likely intended the relative date and accidentally left the absolute dates in place. Explicit precedence rules prevent ambiguous behavior. The precedence order (relative > absolute) matches intuition: "today" is clearer than a specific date range.

### Alternatives Considered

- **Reject with error**: Throw error if both are present - Rejected because it's overly strict for a CLI interface where trial-and-error is common
- **Absolute takes precedence**: Prefer specific dates over relative - Rejected because it's counter-intuitive
- **Last-wins**: Use whichever appears last in JSON - Rejected because JSON object key order is not guaranteed

### Consequences

**Positive:**
- Clear, predictable behavior
- Forgiving of user mistakes (no error for extra fields)
- Favors simpler relative dates

**Negative:**
- Silent ignoring of absolute dates when both present
- Users must know the precedence rule

---

---

## Decision 21: CloudKit Sync Resilience in Entity Queries

**Date**: 2026-02-11
**Status**: accepted

### Context

TaskEntity.from(_:) throws an error if task.project is nil, indicating a data integrity violation. However, during CloudKit sync, a TransitTask record can arrive before its related Project record, temporarily making task.project nil. EntityQuery methods that convert batches of tasks need to handle this gracefully without cascading failures.

### Decision

Use `compactMap { try? TaskEntity.from($0) }` in batch contexts (EntityQuery.entities(for:), EntityQuery.suggestedEntities(), FindTasksIntent.perform()) to gracefully skip tasks without projects. The throwing behavior in TaskEntity.from(_:) itself remains unchanged to surface data integrity issues.

### Rationale

CloudKit sync is eventually consistent. During sync, it's normal for related records to arrive out of order, temporarily creating tasks without projects. In batch operations (showing pickers, returning search results), skipping these incomplete records is preferable to failing the entire operation. Once sync completes, the project relationship resolves and the tasks become available. The throwing factory method still catches permanent data integrity violations when tested in isolation.

### Alternatives Considered

- **Remove throwing from TaskEntity.from()**: Make it always return an entity with fallback values - Rejected because it hides data integrity issues permanently
- **Fail entire batch on any nil project**: Use map { try ... } instead of compactMap - Rejected because temporary sync states would break all entity queries
- **Filter tasks before conversion**: Check task.project != nil before calling from() - Rejected as less concise; compactMap achieves the same result

### Consequences

**Positive:**
- EntityQuery works correctly during CloudKit sync
- Individual tasks with permanent data issues are still caught (via throwing)
- Graceful degradation in batch operations

**Negative:**
- Tasks without projects are silently excluded from pickers/results during sync
- Users won't see newly created tasks in Shortcuts until project relationship syncs (typically <1 second)

---
