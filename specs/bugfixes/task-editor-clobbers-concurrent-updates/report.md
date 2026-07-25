# Bugfix Report: Task Editor Clobbers Concurrent Updates

**Date:** 2026-07-25
**Status:** Investigating
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

`save()` submits the entire form unconditionally:

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
never passes `nil`, so every field is always written back from a snapshot that may
be minutes old.

**Defect type:** Lost update (last-writer-wins over a stale read) — a logic error,
not a race in the threading sense. Everything runs on `@MainActor` and the two
writes are strictly ordered. What is missing is the comparison that would tell the
second writer it is overwriting the first.

**Why it occurred:** The editor was written for a single-writer world. When the MCP
server was added it was deliberately wired to the shared `mainContext` so agent
changes appear live in the UI — which made the app a *concurrent* writer without
the editor's write path being revisited. The form-state pattern (snapshot into
`@State`, submit the form) is the right shape for a cancellable editor; it just
needs a baseline to diff against.

**Contributing factors:**
- `updateTask`'s optional-means-no-change contract is expressive enough to submit a
  partial update, but nothing forced the caller to use it that way.
- Only two of the eight fields (`project`, `status`) were guarded against the live
  value, which made the write look more selective than it actually was.

## Resolution for the Issue

_(Filled in after implementation.)_

## Regression Test

**Test file:** `Transit/TransitTests/TaskEditConcurrentUpdateTests.swift`

Pre-fix state: the suite does not compile, because the merge API it exercises
(`TaskEditSnapshot`, `TaskEditMerge`, `TaskEditApplier`) does not exist yet — the
production code has no concept of "which fields did the user change". That is the
red phase.

**Run command:** `make test-quick`

## Related

- T-1817 — `ProjectEditView` and `MilestoneEditView` share the same
  snapshot-and-write-everything-back pattern. Out of scope here; tracked separately.
- T-854 — description clearing must keep working (`clearDescription`).
- T-452 — save/rollback pattern the editor relies on.
