# Implementation Explanation: Task Priority (T-1463)

Three-level walkthrough of the task-priority feature as implemented on
`T-1463/task-priority`, followed by a completeness assessment.

---

## Beginner Level

### What This Does

Every task in Transit now has a **priority**: low, medium, or high. New tasks
default to medium. You can:

- See a small coloured arrow on a task card — a red up-arrow for high, a blue
  down-arrow for low. Medium shows nothing (so the board isn't cluttered with
  arrows on the most common case).
- Filter the board to show only tasks of certain priorities.
- Set priority when creating or editing a task, and see it on the task detail
  screen.
- Read and set priority from automation — both the MCP server (used by agents)
  and Shortcuts/CLI App Intents.

### Why It Matters

Before this, every task looked equally urgent. Priority lets a single user (and
their agents) tell at a glance what to do next, and filter the board down to the
things that matter most.

### Key Concepts

- **Enum**: a fixed set of named choices. `TaskPriority` is an enum with exactly
  three values: `low`, `medium`, `high`. You can't accidentally set priority to
  "urgent" or "P1" — only those three.
- **Default value**: existing tasks created before this feature have no priority
  stored. Rather than run a database migration, the code treats any
  missing/blank value as `medium`. So old tasks "just work" and read as medium.
- **CloudKit**: Transit syncs across devices via Apple's CloudKit. CloudKit
  requires every new field to have a default value — here, the stored priority
  string defaults to `"medium"`.

---

## Intermediate Level

### Changes Overview

The feature was built in four layers, each verified before the next:

1. **Foundation** (`Models/`, `Services/`)
   - New `TaskPriority` enum (`Models/TaskPriority.swift`): `String, Codable,
     CaseIterable`, mirroring the existing `TaskType` enum. It owns its own
     presentation: `tintColor` (red/orange/blue), `glyphSymbol` (the SF Symbol
     for the card; `nil` for medium), `accessibilityLabel`, and a `displayOrder`
     array (`[.high, .medium, .low]`) for pickers/filters.
   - `TransitTask` gains a stored `priorityRawValue: String = "medium"` and a
     computed `priority: TaskPriority` accessor that falls back to `.medium` for
     any absent/empty/unrecognized raw value. The initializer takes
     `priority: TaskPriority = .medium`.
   - `TaskService.createTask` (both overloads) accepts a defaulted priority;
     `updateTask` accepts an optional `priority` where omitting it leaves the
     stored value unchanged.

2. **Automation** (`Intents/`, `MCP/`)
   - A dedicated `INVALID_PRIORITY` error code (`IntentError`), shared by MCP and
     App Intents.
   - `TaskUpdateValidator.validatePriority` (mirrors `validateType`) threads an
     optional priority through the shared validate/apply pipeline that both
     `update_task` (MCP) and `UpdateTaskIntent` use.
   - MCP `create_task` parses/defaults priority and echoes it; `query_tasks`
     filters by a multi-value priority array; `update_task` accepts priority;
     schemas updated in `MCPToolDefinitions`.
   - App Intents: `CreateTaskIntent` (optional-with-default parse + echo),
     `QueryTasksIntent` (scalar priority filter), `UpdateTaskIntent` (via the
     validator). Serialization (`IntentHelpers.taskToDict` /
     `taskUpdateResponseDict`) emits `priority`.

3. **UI** (`Views/`)
   - `PriorityFilterMenu` (mirrors `TypeFilterMenu`) — multi-select, ordered
     high→medium→low, wired into `DashboardView`'s ephemeral filter state and the
     `DashboardLogic` predicate.
   - `PriorityIndicator` — the card glyph, rendered for high/low only.
   - Priority pickers in `AddTaskSheet` and `TaskEditView`; a priority row in
     `TaskDetailView`.

4. **Verification** (`TransitTests/`)
   - `EffectivePriorityInvariantTests` — one cross-surface regression test
     proving a legacy (`priorityRawValue = ""`) task reads/serializes/filters as
     medium on every read surface.

### Implementation Approach

The guiding principle was **mirror the existing `type` field exactly**. `type`
already had this shape — an enum owning its presentation, a `*RawValue` stored
property with a computed accessor, service params, MCP/intent plumbing, a filter
menu, a picker, a detail row — so `priority` follows the same template
throughout. This keeps the change idiomatic and low-risk: a reviewer who knows
how `type` works already knows how `priority` works.

The one deliberate deviation from `type`: priority gets its **own** error code
(`INVALID_PRIORITY`) rather than reusing `INVALID_TYPE`, and pickers/filters
iterate `displayOrder` (high-first) rather than `allCases` (source order).

### Trade-offs

- **Default-value backfill vs. migration**: chosen to avoid a CloudKit schema
  migration (which is add-only and risky). Cost: the "effective priority" is a
  computed concept, not a stored one, so *every* read surface must go through the
  computed accessor — a discipline enforced by the regression test rather than
  the type system.
- **Non-clearable priority on update** (Decision 8): `updateTask`'s priority is
  `Optional` where `nil` means "don't change," not "clear to default." There's no
  way to "unset" priority back to absent — it's always one of the three values.
  Simpler than a tri-state (`FieldChange`) and matches user expectations.
- **`PriorityFilterMenu` as a near-copy of `TypeFilterMenu`** rather than a
  generic `EnumFilterMenu<E>`: two similar menus don't justify the abstraction;
  a third would.

---

## Expert Level

### Technical Deep Dive

**The effective-priority invariant (Req 1.4) is the load-bearing design choice.**
Because legacy tasks have no stored priority, "priority" is defined as
`TaskPriority(rawValue: priorityRawValue) ?? .medium`, computed at every read.
The failure mode this guards against is a copy-paste that reads `priorityRawValue`
directly on one surface — that surface would then treat a legacy task as having
an empty/invalid priority and drop it from a `medium` filter, silently breaking
sync-era tasks. The mitigation is structural:

- `priorityRawValue` is read *only* in the accessor getter, the initializer, and
  the setter. Every other site — board `matchesFilters`, `MCPQueryFilters.matches`,
  `IntentHelpers.taskToDict`/`taskUpdateResponseDict`, `QueryTasksIntent`'s
  `applyFilters`, the milestone sub-dicts — goes through `task.priority` /
  `task.priority.rawValue`.
- `EffectivePriorityInvariantTests` asserts a `priorityRawValue = ""` task
  reads/serializes/filters as medium across all five read surfaces plus the
  accessor. This is the regression guard; the invariant is a property of test
  coverage, not the compiler.

**Glyph suppression has a single source of truth** (Decision 6):
`TaskPriority.glyphSymbol` returns `nil` for medium, and `PriorityIndicator`
renders nothing when it's `nil`. The view never re-decides "is this medium?" — it
asks the enum. Adding a fourth priority later would change one switch, not the
view.

**Error-code surfacing is asymmetric and intentional.** A *non-string* priority
in an update surfaces as `INVALID_INPUT`, while a *string that isn't a valid
level* surfaces as `INVALID_PRIORITY`. This exactly matches `validateType`'s
behaviour, so the four surfaces (MCP create/update, intent create/update) are
consistent with each other and with the pre-existing `type` handling.

**The `update_task`/`UpdateTaskIntent` parity** is preserved: both route through
`TaskUpdateValidator` + `IntentHelpers.taskUpdateResponseDict`, so adding priority
to the validation pipeline automatically gave both surfaces identical
priority-update semantics and byte-equivalent responses (covered by
`UpdateTaskAllFieldsParityTests`).

### Architecture Impact

- **No new coupling.** Priority rides the existing `type` pathways; no service or
  view gained a new dependency. `DashboardView`'s filter inputs were bundled into
  a `DashboardLogic.FilterSelection` value type to absorb the new dimension
  without growing the predicate's parameter list — a net readability improvement.
- **Contract evolution, not break.** The `CreateTaskIntent` JSON response gained a
  `priority` key. Existing keys are unchanged, so consumers that ignore unknown
  keys stay compatible; the `createTaskIntentJsonContractRemainsCompatible` test
  was updated to assert the new key (count 3→4).
- **Extensibility.** A new priority level is a one-line enum change plus its
  presentation (`tintColor`/`glyphSymbol`/`accessibilityLabel`) and a
  `displayOrder` entry. All read/filter/serialize sites pick it up automatically.

### Potential Issues to Monitor

- **The invariant is test-enforced, not type-enforced.** Any future surface that
  reads tasks must use the computed accessor. The regression test catches the
  five current surfaces; a new surface needs its own assertion (or to be added to
  the invariant test).
- **`IntentHelpers.swift` and `TaskUpdateValidator.swift`** now carry
  `swiftlint:disable file_length` and are growing by accretion. Not a defect, but
  they're trending toward a future split.
- **No `AppEnum`/`Sendable` conformance** was added for `TaskPriority` — the
  visual App Intents (`AddTaskIntent`/`FindTasksIntent`) and `TaskEntity`
  deliberately do not expose priority yet. If a future task wants priority in the
  Shortcuts visual UI, that conformance (and the `@MainActor`-isolation handling
  the project's Swift rules document) will be needed.

---

## Completeness Assessment

**Fully implemented** (all of requirements 1–6, verified by `make test-quick` —
1356 checks passing, and `make lint` — 0 violations):

- Model: stored `priorityRawValue` + computed accessor + init param; medium
  default; no migration (Req 1).
- Effective-priority invariant on every read surface (Req 1.4), with a dedicated
  cross-surface regression test.
- Board card glyph for high/low, medium suppressed (Req 2).
- Board priority filter — multi-select, high→medium→low, ephemeral, in clear-all
  (Req 3).
- In-app create/edit pickers and detail row (Req 4).
- MCP `create_task` (default/echo/invalid-rejects), `query_tasks` (array filter),
  `update_task` (omit-leaves-unchanged) (Req 5).
- App Intents `CreateTaskIntent`/`QueryTasksIntent`/`UpdateTaskIntent` with
  `INVALID_PRIORITY` and lock-step `@Parameter` docs (Req 6).

**Partially implemented / deliberately scoped out** (documented in the decision
log and design parity table, not gaps):

- Priority is **not** exposed in the visual App Intents (`AddTaskIntent`,
  `FindTasksIntent`) or `TaskEntity` — intentional; those keep their current
  surface.
- Priority is **not** part of report output or task share text — out of scope.
- Priority does **not** affect the "Organized" sort (Decision 3) — sort behaviour
  is unchanged.

**Missing**: nothing required by the spec. The only non-spec items are UI-level
assertions for the new accessibility identifiers (consistent with the project's
existing practice of not UI-testing SwiftUI view internals).
