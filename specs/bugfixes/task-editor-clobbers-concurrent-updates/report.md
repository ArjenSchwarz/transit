# Bugfix Report: Task Editor Clobbers Concurrent Updates

**Date:** 2026-07-25
**Status:** Fixed
**Ticket:** T-1798

## Description of the Issue

`TaskEditView` copies every editable field of a task into `@State` when the view
appears, and writes **all** of them back when the user taps Save — regardless of
which fields the user actually touched. Because the editor keeps no record of
what it started from, it cannot tell "the user set this value" apart from "this
value is just what I loaded".

If anything else writes to the task while the editor is open, the next Save
reverts that write. Two writers can do this today:

- **The MCP server**, which shares the app's `mainContext`. An MCP tool call
  mutates the very same `TransitTask` instance the editor is bound to.
- **CloudKit**, whose remote changes SwiftData merges into the same context.

**Reproduction steps:**
1. Open a task in the task editor.
2. Without closing the editor, update the task through MCP (e.g. `update_task`
   renaming it, or `update_task_status` moving it to In Progress).
3. In the still-open form, change only the priority.
4. Tap Save.
5. The priority change applies — and the MCP rename/status change is gone.

**Impact:** High. Silent data loss with no error and no visible cue. It hits the
core agent-integration workflow Transit exists for: an agent updates a ticket
over MCP while the human has that ticket open, and the human's next Save quietly
undoes the agent's work. Every editable field is affected — name, description,
type, priority, status, project, milestone and metadata.

## Investigation Summary

- **Symptoms examined:** External writes to name, description, type, status,
  priority, milestone and metadata all disappear after an unrelated form save.
- **Code inspected:**
  - `Transit/Transit/Views/TaskDetail/TaskEditView.swift` — `loadTask()` (the
    snapshot) and `save()` (the write-back).
  - `Transit/Transit/Services/TaskService.swift` — `updateTask`, `updateStatus`,
    `changeProject`.
  - `Transit/Transit/Services/MilestoneService.swift` — `setMilestone`.
  - `Transit/Transit/MCP/MCPToolHandler.swift` — confirms MCP tools mutate tasks
    through the same services on the same context.
- **Hypotheses tested and ruled out:**
  - *A stale object graph / separate context.* Ruled out — the MCP server reuses
    the UI's `mainContext`, so the editor's `task` reference sees external writes
    immediately. The staleness is entirely in the view's `@State` copy.
  - *Missing `@Bindable` / observation.* Ruled out — even perfect observation
    would not help, because the form deliberately holds an editable copy that
    must not track the model until Save.
  - *A `safeRollback` / save-ordering fault.* Ruled out — the save path is already
    atomic (T-452, and the earlier `taskeditview-partial-persist-on-failed-save`
    fix). The defect is *what* gets written, not *whether* it commits.

## Discovered Root Cause

`save()` submitted the entire form unconditionally:

```swift
try taskService.updateTask(
    task,
    name: trimmedName,
    description: trimmedDesc.isEmpty ? nil : trimmedDesc,
    clearDescription: trimmedDesc.isEmpty,
    type: selectedType,
    metadata: metadata,
    priority: selectedPriority,
    save: false
)
try milestoneService.setMilestone(selectedMilestone, on: task, save: false)
```

`TaskService.updateTask` treats every non-`nil` argument as "apply this". The view
never passed `nil`, so every field was always written back from a snapshot that
could be minutes old.

**Defect type:** Lost update (last-writer-wins over a stale read) — a logic error,
not a race in the threading sense. Everything runs on `@MainActor` and the two
writes are strictly ordered. What was missing is the comparison that would tell
the second writer it is overwriting the first.

**Why it occurred:** The editor was written for a single-writer world. When the MCP
server was added it was deliberately wired to the shared `mainContext` so agent
changes appear live in the UI — which made the app a *concurrent* writer without
the editor's write path being revisited. The form-state pattern (snapshot into
`@State`, submit the form) is the right shape for a cancellable editor; it just
needed a baseline to diff against.

**Contributing factors:**
- `updateTask`'s optional-means-no-change contract is expressive enough to submit a
  partial update, but nothing forced the caller to use it that way.
- Only two of the eight fields (`project`, `status`) were guarded against the live
  value, which made the write look more selective than it actually was.

## Resolution for the Issue

A **three-way merge** at save time. The editor now keeps the task's values from
when it loaded (`original`), reads the form (`edited`), and re-reads the task
(`live`) at the moment of saving. Per field:

| user changed | external changed | outcome |
|---|---|---|
| no | – | not written — the external value stands |
| yes | no | written |
| yes | yes, same value | written (agreement, no prompt) |
| yes | yes, different value | **conflict — the user is asked** |

Reading `live` at save time is sound precisely *because* the editor and MCP share
`mainContext`: the external write has already landed on the same `TransitTask`
instance the view holds, so `TaskEditSnapshot(task:)` sees it without any refetch.

**Changes made:**
- `Transit/Transit/Services/TaskEditMerge.swift` *(new)* — `TaskEditField`,
  `TaskEditSnapshot` (value copy of the eight editable fields, normalised the way
  the form normalises input), `TaskEditMerge` (the three-way comparison producing
  `changedFields` and `conflictingFields`), and `TaskEditApplier` (writes only the
  changed fields, still routed through the services, still deferring persistence).
- `Transit/Transit/Views/TaskDetail/TaskEditView.swift` — records the baseline in
  `loadTask()`, computes the merge in `save()`, writes only changed fields, and
  presents the conflict alert instead of saving when a conflict is found. Adds
  `adoptLiveValues(for:)` for the "use theirs" branch. `loadTask()` is now
  idempotent — a second `onAppear` no longer discards in-flight edits or resets
  the baseline.
- `Transit/Transit/Views/TaskDetail/TaskEditConflictAlert.swift` *(new)* — the
  alert and its copy.
- `Transit/Transit/Views/TaskDetail/TaskEditView+Milestones.swift` *(new)* —
  `availableMilestones` moved out unchanged, to keep the view file within the
  SwiftLint `file_length` limit.

### Conflict-surfacing behaviour (and why)

A same-field conflict **blocks the save** and raises an alert naming the affected
fields, offering two choices:

- **Keep My Changes** — the save proceeds; the user's values win on the
  conflicting fields.
- **Use Updated Values** — the external values are loaded into the form, the
  baseline is re-taken, and **the editor stays open without saving**.

In both branches the user's edits to *non-conflicting* fields are preserved.

Rationale: the editor has no basis for preferring either version, so picking one
silently is what caused this bug in the first place. Blocking the save keeps the
existing atomicity guarantee (T-361/T-452) — there is never a partial write where
some fields landed and a conflicting one did not. "Use Updated Values" deliberately
does not save, because its purpose is to let the user *see* what the other writer
did before committing; discarding their typing invisibly would be a smaller version
of the same defect.

Alternatives considered:
- **Last-writer-wins on the user's side (status quo).** Rejected — the bug.
- **External writer always wins.** Rejected — silently discards the user's typing.
- **Save non-conflicting fields, then prompt for the rest.** Rejected — breaks the
  atomic save and leaves the task in a half-applied state if the user cancels.
- **Live-bind the form to the model (no snapshot).** Rejected — the editor is
  cancellable by design; fields must not write through until Save.

## Regression Test

**Test files:**
- `Transit/TransitTests/TaskEditConcurrentUpdateTests.swift` — external-change
  survival, including the ticket's exact repro
  (`externalUpdateSurvivesUnrelatedFormEdit`), plus status, milestone and
  no-op-save cases.
- `Transit/TransitTests/TaskEditOrdinaryEditTests.swift` — ordinary editing still
  applies every field; description clearing (T-854) and project-move milestone
  clearing (Decision 6) still work.
- Conflict detection lives in `TaskEditConflictDetectionTests` (same file as the
  first): different-value conflicts, same-value agreement, per-field granularity,
  metadata by value, and the alert copy.

**Red phase:** before the fix the suites did not compile — production code had no
concept of "which fields did the user change".

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/TaskEditMerge.swift` | New — snapshot, three-way merge, applier |
| `Transit/Transit/Views/TaskDetail/TaskEditView.swift` | Baseline capture, merge-driven save, conflict alert |
| `Transit/Transit/Views/TaskDetail/TaskEditConflictAlert.swift` | New — conflict alert + copy |
| `Transit/Transit/Views/TaskDetail/TaskEditView+Milestones.swift` | New — `availableMilestones` moved, unchanged |
| `Transit/TransitTests/TaskEditConcurrentUpdateTests.swift` | New — regression + conflict suites |
| `Transit/TransitTests/TaskEditOrdinaryEditTests.swift` | New — ordinary-edit suite |

## Verification

**Automated:**
- [x] Regression tests pass (14 new tests)
- [x] Full unit suite passes — 1367 passed, 0 failed
- [x] `make lint` clean (`--strict`, 0 violations in 274 files)

**Note on the test runs:** the suite was executed while three sibling fix streams
were building concurrently (peak load average ~270). Both runs finished with zero
failures, but `xcodebuild` hung in post-test teardown after `Testing started
completed` — an environment artifact of several Transit test hosts running at once,
unrelated to this change.

## Prevention

**Recommendations:**
- Any form editing a shared `@Model` needs a load-time baseline. The pattern
  "snapshot to `@State`, write everything back" is only safe with a single writer,
  and Transit stopped being single-writer when the MCP server was added.
- `TaskEditSnapshot`/`TaskEditMerge` are generic in shape and could be reused for
  the other editors.
- Prefer passing `nil` for untouched fields to the service layer's
  optional-means-no-change APIs rather than resubmitting whole forms.

## Related

- **T-1817** — `ProjectEditView` and `MilestoneEditView` have the *same*
  snapshot-and-write-everything-back defect. Deliberately out of scope here;
  fixed separately under that ticket. The merge types added here are the obvious
  basis for that fix.
- T-854 — description clearing must keep working (`clearDescription`).
- T-361 / T-452 — the atomic save/rollback behaviour this fix preserves.
