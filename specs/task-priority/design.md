# Design: Task Priority (T-1463)

## Overview

Add a `priority` field (low/medium/high, default medium) to `TransitTask`, mirroring the existing `type` field, and surface it on the board card (glyph), the board filter, the in-app create/edit/detail screens, the MCP server, and the JSON App Intents. No data migration: legacy tasks read as medium through a computed accessor.

## Architecture

The field threads through the same layers as `type`. The governing rule:

> **Effective-priority invariant (Req [1.4](requirements.md#1.4)):** every read — display, filter predicate, serialization — goes through the computed `task.priority` accessor (which falls back to medium), never the raw `priorityRawValue` string. This makes legacy tasks (absent/empty raw value) behave as medium everywhere, including matching a "medium" filter.
>
> **This invariant runs *against* the local convention.** The analogous `type`/`status` reads at the serialization and query-predicate sites use the raw value directly (`task.typeRawValue`, `task.statusRawValue`). Priority must **not** copy that. Every priority read site below is flagged "use `task.priority(.rawValue)`, NOT `priorityRawValue`." A faithful copy-paste of the neighbouring line is the one way to silently break Req 1.4, so the parity table calls out each such site explicitly, and the testing strategy has a dedicated legacy regression test.

Deviations from a literal `type` copy, and why:

| Aspect | `type` does | `priority` does | Why |
|---|---|---|---|
| Query filter cardinality | scalar on both surfaces | **MCP: multi-value array; intent: scalar** | Mirrors the existing `status` filter's actual per-surface cardinality (array on MCP, scalar on intent). Req [5.4](requirements.md#5.4) / [6.3](requirements.md#6.3), Decision 5 |
| Card rendering | text capsule (`TypeBadge`) | **bare SF Symbol glyph**, low/high only | Req [2.1](requirements.md#2.1)/[2.2](requirements.md#2.2); medium suppressed (Decision 6) |
| Organized-sort tie-break | participates (`compareOrganized`) | **does not** | Decision 3 — priority never affects ordering |
| Update semantics | Optional (omit = no change) | same (Optional, **not** `FieldChange`) | Decision 8 — non-clearable |
| Invalid-value error code | `INVALID_TYPE` | **`INVALID_PRIORITY`** (new, dedicated) | Decision 9 — parity with `INVALID_TYPE`/`INVALID_STATUS` |

### Pattern-extension parity audit

Sites that consume `type`/`typeRawValue`/`TaskType` and the priority decision for each. The **read-via-accessor** column flags sites where the invariant forces `task.priority`, against the local raw-value convention.

| Site | Priority change | Read via accessor? |
|---|---|---|
| `TransitTask.swift` `typeRawValue` (L11), `type` accessor (L28–31), `init` (L102–129) | **Yes** — `priorityRawValue` (default `"medium"`), `priority` accessor, defaulted init param | — (this *is* the accessor) |
| `Models/TaskType.swift` | **Yes** — new `Models/TaskPriority.swift` | — |
| `Views/Shared/TypeBadge.swift` | **Yes (new, different)** — `PriorityIndicator` (symbol, not capsule) | reads `task.priority` |
| `TaskCardView.swift` badges HStack (L48–75) | **Yes** — add `PriorityIndicator` | reads `task.priority` |
| `DashboardView.swift` `selectedTypes` plumbing (L9,41,50,58,116,195,393,470,481–483) | **Yes** — `selectedPriorities` + predicate | **Yes** — `selectedPriorities.contains(task.priority)` |
| `DashboardView.swift` `compareOrganized` (L452–455) | **No** — Decision 3 | — |
| `TypeFilterMenu.swift` | **Yes (new)** — `PriorityFilterMenu` | — |
| `AddTaskSheet.swift` (L19,115–119,171–180,263–275) + `+Save.swift` (L41,60–65) | **Yes** — state, Pickers, reset default, `TaskDraft.priority`, create call | — |
| `TaskEditView.swift` (L16,95–99,153–162,277,305–313) | **Yes** — state, Pickers, `load = task.priority`, save | reads `task.priority` on load |
| `TaskDetailView.swift` (L56,115–117) | **Yes** — priority row (text, all 3 levels) | reads `task.priority` |
| `TaskService.swift` `createTask` ×2, `updateTask` (L54,79,262,278) | **Yes** — `priority` param on all three | — |
| `MCPToolDefinitions.swift` create/update `.stringEnum` (L59,242) | **Yes** — `priority` enum prop | — |
| `MCPToolDefinitions.swift` query `status` `.array` (L108) | **Yes** — `priority` as `.array` (MCP only) | — |
| `MCPToolDefinitions.swift` query `type` `.stringEnum` (L117) | **No** — MCP priority query is array, not scalar | — |
| `MCPToolHandler.swift` handleCreateTask (L192–198,258–264) | **Yes** — parse (optional, default medium)/validate/apply | — |
| `MCPToolHandler.swift` create-task response (~L271) | **Yes** — response echoes `priority` (via `taskToDict`) | **Yes** |
| `MCPToolHandler.swift` handleUpdateTask (L836–891) | **No** — delegates to `TaskUpdateValidator` | — |
| `MCPToolHandler.swift` handleQueryTasks (L431–454) | **Yes** — validate array (`allowArray: true`), pass to filters | — |
| `MCPHelperTypes.swift` `MCPQueryFilters` (L9 add field; predicate beside L66) | **Yes** — `priorities: [String]?` + array predicate | **Yes** — compare `task.priority.rawValue`, NOT `priorityRawValue` |
| `Intents/CreateTaskIntent.swift` (L21–39,219–224, create call) | **Yes** — docs ×2, optional-with-default validation, create | — |
| `Intents/UpdateTaskIntent.swift` (L27–53) | **Yes** — docs ×2 (logic via validator) | — |
| `Intents/QueryTasksIntent.swift` `QueryFilters` scalar (L22–54,247–249,287–289,69–82) | **Yes** — scalar `priority: String?`, validate, apply, docs | **Yes** — compare `task.priority.rawValue`, NOT `priorityRawValue` |
| `Intents/TaskUpdateValidator.swift` (L193–205,312,319,103–117) | **Yes** — `validatePriority` (mirror `validateType`); add term to `apply`'s `hasFieldChange` (L103) in the **same** edit | — |
| `Intents/IntentHelpers.swift` `taskToDict` (L267), `taskUpdateResponseDict` (L312) | **Yes** — add `"priority"` | **Yes** — `task.priority.rawValue`, NOT `priorityRawValue` |
| `MCPToolHandler.swift` `milestoneToDict` task sub-dict (L1139); `QueryMilestonesIntent.swift` (L209) | **Yes** — add `"priority"` (serialization consistency) | **Yes** — `task.priority.rawValue`, NOT `priorityRawValue` |
| `Intents/Shared/Enums/TaskTypeAppEnum.swift`; Visual `AddTaskIntent`/`FindTasksIntent`; `TaskEntity` | **No** — JSON intents use the raw enum directly; Visual intents + `TaskPriorityAppEnum` out of scope | — |
| `Reports/*` (`taskType`); `TransitTask.shareText` (L62) | **No** — Non-Goal (priority not in reports/share text) | — |

## Components and Interfaces

### New: `Models/TaskPriority.swift`
```swift
import SwiftUI

enum TaskPriority: String, Codable, CaseIterable {
    case low, medium, high

    var tintColor: Color { … }        // high .red, medium .orange, low .blue
    var glyphSymbol: String? { … }    // high "arrow.up.circle.fill", low "arrow.down.circle.fill", medium nil
    var accessibilityLabel: String { … } // "High priority" / "Medium priority" / "Low priority"
}
```
- `glyphSymbol == nil` for medium is the single source of truth for "no card glyph" (Decision 6); the card reads it rather than re-deciding suppression.
- `tintColor` is defined for **all three** (medium `.orange`) because `PriorityFilterMenu` renders a colored dot per case, including medium.
- Display order in pickers and the filter menu is **high → medium → low** (iterate an explicit ordered array, not `allCases`, which is low-first), so the most actionable value reads first.

### Model: `TransitTask`
```swift
var priorityRawValue: String = "medium"          // CloudKit-safe default (same shape as statusRawValue/typeRawValue)
var priority: TaskPriority {                      // effective accessor (the invariant)
    get { TaskPriority(rawValue: priorityRawValue) ?? .medium }
    set { priorityRawValue = newValue.rawValue }
}
// init gains: priority: TaskPriority = .medium   → self.priorityRawValue = priority.rawValue
```
No production code reads `priorityRawValue` outside this accessor, the init, and the setter. (Enforced by review + the invariant test.)

### Service: `TaskService`
- `createTask(... , priority: TaskPriority = .medium, ...)` on both overloads → into `TransitTask` init.
- `updateTask(... , priority: TaskPriority? = nil, ...)` → `if let priority { task.priority = priority }` (omit = unchanged, Decision 8).

### UI
- **`PriorityIndicator`** (new, `Views/Shared/`): when `priority.glyphSymbol` is non-nil, an `Image(systemName:)` at `.font(.caption)`, `.foregroundStyle(priority.tintColor)`, `.accessibilityLabel(priority.accessibilityLabel)`, identifier `dashboard.taskCard.priority`; medium renders nothing. It is a bare symbol (the card's comment-count `Label` is the symbol precedent), **not** a `TypeBadge`-style text capsule. Slots into the `TaskCardView` badges HStack (L48–75). It reacts to `task.priority`, satisfying Req [2.3](requirements.md#2.3) (the glyph appears/disappears when priority crosses to/from medium via normal SwiftUI re-render). Medium has no glyph and so is **not** VoiceOver-discoverable from the card — by design (Req 2.2); the detail and edit screens expose medium explicitly.
- **`PriorityFilterMenu`** (new, `Views/Dashboard/`): mirrors `TypeFilterMenu` — `@Binding selectedPriorities: Set<TaskPriority>`, iterates the ordered [high, medium, low] with `Circle().fill(priority.tintColor)` + checkmark, identifiers `dashboard.filter.priorities` and `filter.priority.<raw>` (Req [3.7](requirements.md#3.7)). Added to `DashboardView` toolbar next to `TypeFilterMenu` (L116), with `@State selectedPriorities` (resets on launch → Req [3.5](requirements.md#3.5) ephemeral), inclusion in `hasAnyFilter`/`hasOtherFilters` (L41,50), clear-all (L195), and threading into `buildFilteredColumns`/`matchesFilters`.
- **Filter predicate** (in `matchesFilters`, beside the type predicate L481–483):
  ```swift
  if !selectedPriorities.isEmpty {
      guard selectedPriorities.contains(task.priority) else { return false }   // computed accessor
  }
  ```
- **`AddTaskSheet`** / **`TaskEditView`**: `@State selectedPriority` (default `.medium`; edit loads `task.priority`), a `Picker("Priority", selection:)` over the ordered cases mirroring the existing Type picker on both iOS and macOS, threaded through `TaskDraft`/`createTask` and the `updateTask` call respectively.
- **`TaskDetailView`**: a Priority row in both layouts, rendered as **text for all three levels** (`task.priority.rawValue.capitalized`, like the Status row) so medium is visible (Req [4.4](requirements.md#4.4)).

### MCP
- **Definitions**: `priority` as `.stringEnum` on `create_task`/`update_task`; `priority` as `.array` on `query_tasks` (mirror `status`, L108).
- **handleCreateTask**: `args["priority"] as? String` defaulting to `"medium"` when absent; present-but-invalid → `INVALID_PRIORITY` error result, **no task created** (Req [5.5](requirements.md#5.5)); valid → pass to `createTask`. The create response serializes through `taskToDict`, so it echoes the resolved `priority`.
- **handleUpdateTask**: unchanged — `TaskUpdateValidator` carries priority.
- **handleQueryTasks**: validate via `validateEnumFilter(..., key: "priority", allowArray: true)` (like `status`), pass the parsed array to `MCPQueryFilters.from`.
- **`MCPQueryFilters`**: add `priorities: [String]?`, parsed in `from(args:)` accepting either a single string or an array (defensive, mirroring `status` L28–44 — this works because MCP reads an untyped `[String: Any]`). Predicate (beside status L66):
  ```swift
  if let priorities, !priorities.isEmpty, !priorities.contains(task.priority.rawValue) { return false }
  ```
  Compares the **computed** `task.priority.rawValue` (invariant), so legacy tasks match a `["medium"]` filter.
- **Serialization**: `IntentHelpers.taskToDict` and `taskUpdateResponseDict` add `"priority": task.priority.rawValue`; the `milestoneToDict`/`QueryMilestonesIntent` task sub-dicts add the same. All use the computed accessor.

### App Intents (JSON)
- **CreateTaskIntent**: add `priority` to both the `inputParameterDescription` and the `@Parameter` literal (lock-step, T-1170). Validation is an **optional-with-default** path — *not* a copy of the required-`type` force-unwrap: absent → `.medium`; present-and-invalid → `INVALID_PRIORITY` JSON error; present-and-valid → parse. Pass to `createTask`.
- **UpdateTaskIntent**: document `priority` in both literals; field logic via `TaskUpdateValidator`.
- **QueryTasksIntent**: add a **scalar** `priority: String?` to `QueryFilters` (matching the struct's existing scalar `status`/`type` — no custom `Codable` needed), a `validateEnumFilters` clause (→ `INVALID_PRIORITY`), an `applyFilters` clause (`task.priority.rawValue != priority`, computed accessor), and `@Parameter` docs.
- **TaskUpdateValidator**: `validatePriority` mirrors `validateType` exactly — absent → `.success(nil)`; non-string → invalid-input; bad raw → `INVALID_PRIORITY` listing `TaskPriority.allCases`; carried as `ValidatedTaskUpdate.priority: TaskPriority?`, counted in `hasChanges`, and — in the **same edit** — added to `apply`'s `hasFieldChange` check (L103) and passed to `updateTask(priority:)`. (The L99–102 comment warns that a field added to the struct but not to `apply` validates but never applies.) Use `Optional`, **not** `FieldChange` (non-clearable).

## Data Models

One new stored attribute (`priorityRawValue: String = "medium"`) on `TransitTask`. CloudKit add-only: non-optional with a default, no `@Attribute(.unique)`, no relationship — the identical shape to the already-shipping `statusRawValue`/`typeRawValue`, which sync through CloudKit in production today. New records get the schema default; the computed accessor's `?? .medium` covers any record whose raw value is empty or an unrecognized string. No `VersionedSchema`/migration entry is required.

## Error Handling

New dedicated error code **`INVALID_PRIORITY`**, added to the intent `IntentError` enum and the MCP error-code set, parallel to `INVALID_TYPE`/`INVALID_STATUS` (Decision 9).

| Condition | Surface | Behavior |
|---|---|---|
| Invalid priority on `create_task` | MCP | `INVALID_PRIORITY` error result, no task created (Req [5.5](requirements.md#5.5)) |
| Invalid priority on create/update intent | Intent | JSON `INVALID_PRIORITY`, no mutation (Req [6.4](requirements.md#6.4)) |
| Invalid priority in query filter | MCP/Intent | `INVALID_PRIORITY` validation error |
| Omitted priority on update | MCP/Intent | unchanged (Decision 8) |

Validation messages list `low, medium, high`; matching is exact-lowercase (Req Value Format).

## Testing Strategy

Swift Testing, `@MainActor @Suite(.serialized)`, fresh context via `TestModelContainer.newContext()`.

- **Enum / model**: `TaskPriority` raw values, `allCases`, `tintColor` (all three), `glyphSymbol` (nil only for medium); accessor fallback — empty/unknown `priorityRawValue` → `.medium`.
- **Effective-priority invariant (Req 1.4) — the legacy-backfill regression test**: a task with `priorityRawValue = ""` is (a) serialized as `"medium"` by `taskToDict` and `taskUpdateResponseDict`, and (b) included by a `["medium"]`/`"medium"` filter on every read surface — board `matchesFilters`, `MCPQueryFilters.matches`, and intent `applyFilters`. This is the guard against a raw-value copy-paste.
- **Service**: create defaults to medium and honors explicit value; update sets priority; update omitting priority leaves it unchanged.
- **`TaskUpdateValidator`**: absent → no change; invalid → `INVALID_PRIORITY`; valid → applied (proves the `hasFieldChange` term was added). Extend `UpdateTaskAllFieldsParityTests` so MCP and intent updates stay in lockstep on priority.
- **MCP**: create with/without priority (response echoes it); create with invalid priority → `INVALID_PRIORITY`, no creation; query returns priority; query filters by a single value and by an array; invalid filter value rejected.
- **Intents**: create default/explicit/invalid; update set/omit; query scalar filter (single value; invalid rejected); JSON error shape carries `INVALID_PRIORITY`.
- **Dashboard filter** (`DashboardFilterTests`): single and multi priority selection; empty set = all; intersection with project and type filters.

PBT is not used: the only universal property (raw-value round-trip) is over three cases and is covered exhaustively by example tests.
