# Decision Log: Milestones

## Decision 1: Milestones Over Epics

**Date**: 2026-02-22
**Status**: accepted

### Context

T-137 was originally titled "Introduce epics/milestones". Both terms describe grouping mechanisms for tasks, but they have different connotations. Epics typically imply large user stories that break down into smaller tasks and carry their own lifecycle complexity. Milestones are lighter — named markers that tasks are assigned to, representing a release or goal.

### Decision

Use "Milestones" as the concept name, not "Epics".

### Rationale

Milestones are a better fit for Transit's use case of grouping tasks by release (e.g. "v1.0"). They're simpler to reason about — a named grouping with a minimal lifecycle — without the baggage of epic-style decomposition hierarchies. Transit is a single-user tool where lightweight concepts are preferred.

### Alternatives Considered

- **Epics**: Richer concept with parent-child task relationships — Rejected because it adds hierarchy complexity that Transit doesn't need
- **Labels/Tags**: Even lighter grouping — Rejected because milestones need a lifecycle (open/done) and display IDs, which tags don't provide

### Consequences

**Positive:**
- Simple mental model: a milestone is just a named bucket with a status
- No parent-child task hierarchy to manage

**Negative:**
- If hierarchical task decomposition is ever needed, a separate concept would need to be introduced

---

## Decision 2: Simple Three-State Lifecycle

**Date**: 2026-02-22
**Status**: accepted

### Context

Milestones need some way to indicate whether they're active or finished. The question is how many states to support. Tasks have 8 statuses with a linear progression, but milestones are simpler — they're either being worked on or they're not.

### Decision

Milestones have exactly three statuses: Open, Done, Abandoned.

### Rationale

A milestone doesn't go through planning/spec/review stages — it's a container, not a work item. Open means "tasks are being assigned and worked on", Done means "the release shipped", Abandoned means "we dropped this goal". This mirrors the terminal states of tasks without the intermediate workflow.

### Alternatives Considered

- **Two states (Open/Closed)**: Simpler — Rejected because distinguishing "completed successfully" from "dropped" is valuable for reports and history
- **Full task lifecycle**: Matching task statuses — Rejected because milestones don't have their own work phases; overkill for a grouping concept

### Consequences

**Positive:**
- Minimal UI complexity (a simple status picker with 3 options)
- Clear semantics for reports (done vs abandoned milestones)

**Negative:**
- No "in progress" vs "planning" distinction — milestones are either open or terminal

---

## Decision 3: One Milestone Per Task

**Date**: 2026-02-22
**Status**: accepted

### Context

Tasks need to be associated with milestones. The question is whether a task can belong to multiple milestones (many-to-many) or just one (many-to-one).

### Decision

A task belongs to at most one milestone (optional to-one relationship).

### Rationale

A task shipping in a release is a singular event — it ships in v1.0 or v1.1, not both. A to-one relationship is simpler in SwiftData (just an optional property), avoids CloudKit many-to-many complexity, and is easier to display in the UI (a single badge rather than a list).

### Alternatives Considered

- **Many-to-many**: Tasks could appear in multiple milestones — Rejected because it complicates the data model (junction table), UI (multiple badges), and doesn't match the "which release does this ship in" use case

### Consequences

**Positive:**
- Simple data model: `task.milestone: Milestone?`
- Simple UI: one badge, one picker
- CloudKit-friendly (no junction records)

**Negative:**
- Can't track "this task was considered for v1.0 but moved to v1.1" history (acceptable — just reassign)

---

## Decision 4: Nullify on Milestone Deletion

**Date**: 2026-02-22
**Status**: accepted

### Context

When a milestone is deleted, we need to decide what happens to its assigned tasks. CloudKit supports `.cascade` (delete tasks too) or `.nullify` (remove association).

### Decision

Use `.nullify` delete rule — deleting a milestone removes the association but keeps the tasks.

### Rationale

Tasks represent actual work that doesn't disappear when a release goal changes. Deleting a milestone should just "ungroup" its tasks, not destroy work. This is also the safer option for a single-user app where accidental milestone deletion shouldn't cause data loss.

### Alternatives Considered

- **Cascade delete**: Delete milestone and all its tasks — Rejected because it's destructive and doesn't match the mental model (tasks exist independently of milestones)
- **Prevent deletion if tasks assigned**: Block deletion until tasks are unassigned — Rejected because it adds friction without meaningful benefit; nullify achieves the same safety

### Consequences

**Positive:**
- No data loss when milestones are deleted
- Tasks remain intact and can be reassigned to a new milestone

**Negative:**
- Users might not realize tasks have been "ungrouped" after deletion (mitigated by the fact that cards lose their milestone badge)

---

## Decision 5: Milestone Status Changes Don't Cascade to Tasks

**Date**: 2026-02-22
**Status**: accepted

### Context

When a milestone is marked Done or Abandoned, should its tasks automatically change status too? For example, should marking milestone "v1.0" as Done automatically mark all its tasks as Done?

### Decision

Milestone status changes have no effect on task statuses.

### Rationale

A milestone being "done" means the release shipped, not that every task is finished. Some tasks might have been descoped but left assigned for tracking. Auto-cascading would be surprising and potentially destructive — a user marks a milestone done and suddenly 30 tasks change status without their knowledge.

### Alternatives Considered

- **Auto-cascade to Done**: All tasks move to Done when milestone is Done — Rejected because it's surprising, potentially incorrect (some tasks may not be done), and hard to undo
- **Warn if tasks are incomplete**: Show a confirmation when marking done with open tasks — Rejected as unnecessary complexity; the user can see task statuses on the board

### Consequences

**Positive:**
- No surprise status changes
- Milestones and tasks have independent lifecycles

**Negative:**
- User must manually close remaining tasks after marking a milestone done (expected workflow)

---

## Decision 6: Clear Milestone on Project Change

**Date**: 2026-02-22
**Status**: accepted

### Context

Milestones are project-scoped. If a task moves from Project A to Project B, its milestone (which belongs to Project A) becomes invalid.

### Decision

When a task's project changes, the system clears its milestone assignment automatically.

### Rationale

A milestone from Project A has no meaning in Project B. Keeping a stale association would be confusing and could cause data integrity issues. Clearing it is the only consistent option.

### Alternatives Considered

- **Prevent project change if milestone assigned**: Block the project change — Rejected because it adds unnecessary friction; the user can reassign a milestone in the new project
- **Prompt to reassign**: Show a picker for the new project's milestones — Rejected as over-engineering for an uncommon action

### Consequences

**Positive:**
- Data integrity maintained — no cross-project milestone references
- Simple, automatic behavior

**Negative:**
- User loses milestone assignment silently when changing project (acceptable — project changes are rare and intentional)

---

## Decision 7: Separate CloudKit Counter for Milestone Display IDs

**Date**: 2026-02-22
**Status**: accepted

### Context

Tasks use a CloudKit counter record with optimistic locking for sequential display IDs (T-1, T-2, ...). Milestones need their own sequence (M-1, M-2, ...).

### Decision

Reuse the `DisplayIDAllocator` mechanism with a separate CloudKit counter record type for milestones.

### Rationale

The existing allocator pattern is proven and handles offline/conflict scenarios. Using a separate counter keeps task and milestone sequences independent. Parameterising the allocator (or creating a second instance) is straightforward.

### Alternatives Considered

- **Shared counter for tasks and milestones**: Both draw from the same sequence — Rejected because it would create confusing gaps (T-1, M-2, T-3) and conflate unrelated concepts
- **UUID-only (no display IDs)**: Skip human-readable IDs for milestones — Rejected because the user explicitly wants M-<id> for reference in conversation and CLI

### Consequences

**Positive:**
- Independent, gap-free sequences for tasks and milestones
- Proven pattern with offline/sync handling

**Negative:**
- Two counter records to maintain in CloudKit (minimal overhead)

---

## Decision 8: Central Milestone Assignment Validation

**Date**: 2026-02-22
**Status**: accepted

### Context

Milestone assignment must enforce that the task and milestone belong to the same project (requirement 4.3). Multiple consumers set milestones: the task edit view, add task sheet, MCP tools, and App Intents. Without a central validation point, each consumer must independently enforce the constraint.

### Decision

Add `MilestoneService.setMilestone(_:on:)` as the single entry point for all milestone assignment. All consumers call this method rather than setting `task.milestone` directly.

### Rationale

Centralising validation prevents bugs where one consumer forgets to check the project match. The method also validates that tasks without a project can't be assigned a milestone (requirement 4.5). This is a small addition that significantly reduces data integrity risk.

### Alternatives Considered

- **Direct property assignment with per-consumer validation**: Each view/handler validates independently — Rejected because it's error-prone and duplicates logic
- **SwiftData-level validation (willSave)**: SwiftData doesn't support custom save validators with CloudKit — Rejected as technically infeasible

### Consequences

**Positive:**
- Single place to enforce and test the constraint
- Consistent error reporting (`.projectMismatch`) across all consumers

**Negative:**
- Slight indirection — consumers call a service method instead of setting a property

---

## Decision 9: Preserve DisplayID.formatted as a Property

**Date**: 2026-02-22
**Status**: accepted

### Context

`DisplayID.formatted` is a computed property that returns "T-{id}" or "T-\u2022". Milestones need "M-{id}". The question is whether to change the existing property or add alongside it.

### Decision

Keep the existing `var formatted: String` property unchanged. Add a new `func formatted(prefix: String) -> String` method. The property calls through to the method with prefix "T".

### Rationale

Changing a property to a method touches every call site (~10 files) for no functional benefit. Keeping the property preserves all existing code. Milestone code uses the new method with prefix "M".

### Alternatives Considered

- **Replace property with method**: Change `formatted` to `formatted(prefix:)` with a default parameter — Rejected because it creates unnecessary churn across the codebase for a purely additive change

### Consequences

**Positive:**
- Zero changes to existing call sites
- Clean extension point for milestones

**Negative:**
- Two ways to format (property and method) — minimal confusion since the property is just sugar

---
