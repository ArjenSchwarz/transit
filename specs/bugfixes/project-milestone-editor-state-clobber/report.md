# Bugfix Report: Project and Milestone Editor State Clobber

**Date:** 2026-07-25
**Status:** Fixed
**Tickets:** T-1817, T-1880

## Description of the Issue

`ProjectEditView` and `MilestoneEditView` copy every editable field into `@State`
when the view appears and write **all** of them back when the user taps Save.
The editors keep no record of what they started from, and they reload
unconditionally from `onAppear`. Two opposite failures fall out of that one
design:

- **T-1817 — other writers' changes are lost.** Without a baseline the form
  cannot tell "the user set this value" apart from "this value is just what I
  loaded". Anything written to the project or milestone while the editor is open
  — by the MCP server, which shares `mainContext`, by a CloudKit merge, or by a
  second window — is reverted by the next Save, even when the user touched only
  an unrelated field.
- **T-1880 — the user's own draft is lost.** `ProjectEditView` pushes
  `MilestoneEditView` via `NavigationLink`. Popping back re-runs `onAppear`, and
  `loadProject()` overwrote the unsaved name, description, repository and colour
  with the persisted values.

**Reproduction steps (T-1817):**
1. Open a project in Settings.
2. Without closing the editor, change that project elsewhere (another window, a
   CloudKit sync from another device).
3. In the still-open form, change only the colour.
4. Tap Save.
5. The colour change applies — and the external change is gone.

**Reproduction steps (T-1880):**
1. Open an existing project in Settings.
2. Change one or more project fields without saving.
3. Tap Add Milestone (or open an existing milestone).
4. Return to the project editor.
5. The draft has silently reverted to the persisted values.

**Impact:** High, and silent in both directions — no error, no visible cue. The
first half hits the agent-integration workflow Transit exists for; the second
hits an everyday navigation path, since the milestone editor is the only child
screen the project editor has and adding a milestone mid-edit is the obvious
thing to do.

## Investigation Summary

- **Symptoms examined:** external writes to name, description, git repo and
  colour disappearing after an unrelated save; unsaved drafts reverting after a
  return trip through the milestone editor.
- **Code inspected:**
  - `Transit/Transit/Views/Settings/ProjectEditView.swift` — `loadProject()`
    (called unconditionally from both platforms' `onAppear`) and `save()` (the
    unconditional write-back).
  - `Transit/Transit/Views/Settings/MilestoneEditView.swift` — the same pair.
  - `Transit/Transit/Views/Settings/MilestoneListSection.swift` — confirms the
    `NavigationLink`s that make `ProjectEditView` reappear.
  - `Transit/Transit/Services/ProjectService.swift` (`updateProject`) and
    `MilestoneService.swift` (`updateMilestone`) — what each write path accepts.
  - `Transit/Transit/Services/TaskEditMerge.swift` — the machinery merged for
    T-1798, which is this defect in `TaskEditView`.
- **Hypotheses tested and ruled out:**
  - *A stale object graph / separate context.* Ruled out — the MCP server reuses
    the UI's `mainContext`, so the editor's `project` reference already sees
    external writes. The staleness is entirely in the view's `@State` copy.
  - *SwiftUI recreating the view (T-1880).* Ruled out — the `@State` survives the
    push/pop; it is `onAppear` re-running `loadProject()` that discards it.
  - *A `safeRollback` / save-ordering fault.* Ruled out — the save path already
    rolls back atomically. The defect is *what* gets written, not whether it
    commits.

## Discovered Root Cause

One design flaw, two symptoms: **the editors treat their `@State` as a mirror of
the model rather than as a draft with a baseline.**

`save()` submitted the whole form unconditionally:

```swift
try projectService.updateProject(
    project,
    name: trimmedName,
    description: trimmedDesc,
    gitRepo: trimmedRepo.isEmpty ? nil : trimmedRepo,
    colorHex: color.hexString
)
```

`updateProject` writes all four fields, and the view always passed all four from
a snapshot that could be minutes old. `MilestoneEditView` did the same through
`updateMilestone`, which does support "leave this alone" (`nil`) but was never
called that way.

And `loadProject()` had no guard:

```swift
.onAppear { loadProject() }   // fires again on every return from a pushed screen
```

**Defect type:** lost update (last-writer-wins over a stale read) for T-1817; a
lifecycle error — treating `onAppear` as "on first appear" — for T-1880. Neither
is a race in the threading sense; everything runs on `@MainActor`.

**Why it occurred:** the editors were written for a single-writer world with no
child navigation. The MCP server made the app a concurrent writer, and
`MilestoneListSection` gave the project editor a child screen; neither change
revisited the form's state handling. T-1798 fixed exactly this in `TaskEditView`
and explicitly left the project and milestone editors to T-1817.

**Contributing factors:**
- `ProjectService.updateProject` has no optional-means-no-change contract, so
  "write only this field" was not expressible without reading the live values.
- The colour is stored as a hex string but edited as a `Color`, so a naive
  comparison of form state against the model would report spurious changes.

## Resolution for the Issue

The same **three-way merge** T-1798 introduced for tasks, now shared by all three
editors, plus a load-once draft.

At save time the editor holds the values from when it loaded (`original`), the
form (`edited`), and re-reads the model (`live`). Per field:

| user changed | external changed | outcome |
|---|---|---|
| no | – | not written — the external value stands |
| yes | no | written |
| yes | yes, same value | written (agreement, no prompt) |
| yes | yes, different value | **conflict — the user is asked** |

**Changes made:**
- `Transit/Transit/Services/EditMerge.swift` *(new)* — the `EditableField` and
  `EditSnapshot` protocols and the generic `EditMerge<Snapshot>`. The three-way
  comparison, the changed/conflicting field sets and the field ordering now exist
  once for all editors.
- `Transit/Transit/Services/TaskEditMerge.swift` — `TaskEditField` and
  `TaskEditSnapshot` conform to the new protocols; `TaskEditMerge` becomes
  `typealias TaskEditMerge = EditMerge<TaskEditSnapshot>`. Behaviour for
  `TaskEditView` is unchanged, including every call site and existing test.
- `Transit/Transit/Services/ProjectEditMerge.swift` *(new)* — `ProjectEditField`,
  `ProjectEditSnapshot`, `ProjectEditMerge`, `ProjectEditApplier`, and
  `ProjectEditForm` (the draft plus its load-once guard).
- `Transit/Transit/Services/MilestoneEditMerge.swift` *(new)* — the same four
  types for milestones.
- `Transit/Transit/Views/Shared/EditConflictAlert.swift` *(new)* — the generic
  conflict alert and its copy.
- `Transit/Transit/Views/TaskDetail/TaskEditConflictAlert.swift` — reduced to the
  task-flavoured wrapper over the shared alert; wording unchanged.
- `Transit/Transit/Views/Settings/ProjectEditView.swift` — drives a
  `ProjectEditForm`, saves through the merge, presents the conflict alert, and
  loads once per project identity.
- `Transit/Transit/Views/Settings/MilestoneEditView.swift` — the same.

**Approach rationale:**

*Generalised rather than duplicated.* The requirement was that a user should not
meet three different conflict behaviours in one app. Three copies of a 25-line
comparison would drift; the algorithm is now written once and each editor
supplies only its field list, its snapshot and its applier. The task editor's
behaviour is preserved exactly — `TaskEditMerge` is now a typealias for the
generic type, so its call sites and its tests are untouched.

*Colour is compared as a hex string.* `ProjectEditForm` holds `colorHex`, not
`Color`, and `ProjectEditView` bridges it to `ColorPicker`. Comparing `Color`
values would compare colour spaces and floating-point components rather than what
is persisted, and round-tripping through `Color` on load would make merely
opening the editor look like a colour edit. Storage and `Color.hexString`
disagree on the leading `#` and on case, so `ProjectEditSnapshot` normalises both.

*Unchanged fields are resubmitted with live values.* `updateProject` writes all
four fields, so `ProjectEditApplier` passes the project's *current* values for
fields the user did not touch. `MilestoneEditApplier` passes `nil` instead, which
`updateMilestone` already reads as "leave this alone".

*The draft is a value type.* Holding the fields, the baseline and the loaded
identity in one `ProjectEditForm` / `MilestoneEditForm` makes `load(from:)`
idempotent by construction, keeps the editing logic out of the views, and makes
both halves of this fix testable without a SwiftUI harness.

**Conflict-surfacing behaviour (matching T-1798):** a same-field conflict
**blocks the save** and raises an alert naming the affected fields, offering
**Keep My Changes** (the save proceeds; the user's values win) and **Use Updated
Values** (the external values are loaded into the form, the baseline is re-taken,
and the editor stays open **without saving**). Edits to non-conflicting fields
survive either branch. Nothing is resolved silently.

**Alternatives considered:**
- **Duplicate `TaskEditMerge` per entity** — rejected; three copies of the same
  comparison invite behavioural drift, which is what the paired tickets asked to
  avoid.
- **A lighter conflict UX for projects** (last-writer-wins with a toast) —
  rejected; consistency across editors matters more, and silently picking a
  winner is the bug.
- **Reload only when the model changed** — rejected; it still cannot tell a
  draft from a stale load, and it would clobber drafts whenever an external write
  happened to land.
- **Per-field "dirty" flags instead of a baseline** — rejected; equivalent power,
  more state to keep in sync, and no way to detect agreement (both sides setting
  the same value).

## Regression Test

**Test files:**
- `Transit/TransitTests/ProjectEditConcurrentUpdateTests.swift` —
  `ProjectEditConcurrentUpdateTests` covers T-1817's repro
  (`externalUpdateSurvivesUnrelatedFormEdit`), git-repo survival and clearing,
  ordinary edits, and colour-format/whitespace no-ops;
  `ProjectEditDraftLifecycleTests` covers T-1880
  (`draftSurvivesReturnFromMilestoneEditor`, the baseline surviving the second
  appearance, and a different project still replacing the draft).
- `Transit/TransitTests/ProjectEditConflictDetectionTests.swift` — conflict
  granularity, same-value agreement, "Use Updated Values" re-baselining, alert copy.
- `Transit/TransitTests/MilestoneEditConcurrentUpdateTests.swift` — the
  equivalents for milestones, including that an externally set status is
  untouched by a save.

**Red phase:** before the fix these suites did not compile — production code had
no concept of "which fields did the user change" and no draft type to load twice.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/EditMerge.swift` | New — shared field/snapshot protocols and the generic three-way merge |
| `Transit/Transit/Services/TaskEditMerge.swift` | Conforms to the shared protocols; `TaskEditMerge` is now a typealias |
| `Transit/Transit/Services/ProjectEditMerge.swift` | New — project fields, snapshot, applier, draft form |
| `Transit/Transit/Services/MilestoneEditMerge.swift` | New — milestone fields, snapshot, applier, draft form |
| `Transit/Transit/Views/Shared/EditConflictAlert.swift` | New — shared conflict alert and copy |
| `Transit/Transit/Views/TaskDetail/TaskEditConflictAlert.swift` | Reduced to the task-flavoured wrapper |
| `Transit/Transit/Views/Settings/ProjectEditView.swift` | Merge-driven save, conflict alert, load-once draft |
| `Transit/Transit/Views/Settings/MilestoneEditView.swift` | Merge-driven save, conflict alert, load-once draft |
| `Transit/TransitTests/ProjectEditConcurrentUpdateTests.swift` | New — T-1817 and T-1880 regressions |
| `Transit/TransitTests/ProjectEditConflictDetectionTests.swift` | New — conflict suite |
| `Transit/TransitTests/MilestoneEditConcurrentUpdateTests.swift` | New — milestone regressions and conflicts |

## Verification

**Automated:**
- [x] Regression tests pass (25 new tests)
- [x] Full unit suite passes on macOS (`make test-quick`) — 1516 passed, 0 failed
- [x] `make lint` clean (`--strict`, 0 violations in 290 files)

**Note on the test runs:** build and test commands must be run with the session
sandbox disabled, or `xcodebuild` wedges on its XPC connection to XCBBuildService.
See `docs/agent-notes/build-sandbox-wedge.md`.

## Prevention

**Recommendations:**
- Any form editing a shared `@Model` needs a load-time baseline and a load-once
  guard. "Snapshot to `@State` on `onAppear`, write everything back on save" is
  only safe with a single writer and no child navigation; Transit has neither
  property any more.
- Prefer `EditMerge` for new editors rather than hand-rolling a comparison —
  supplying a field enum, a snapshot and an applier is the whole cost.
- `onAppear` means "appeared", not "appeared for the first time". State
  initialisation there needs an identity guard.
- Compare persisted representations (the stored hex), not the UI's richer type
  (`Color`), or loading a value will look like changing it.

## Related

- **T-1798** / PR #183 — the same defect in `TaskEditView`;
  `specs/bugfixes/task-editor-clobbers-concurrent-updates/report.md` explains the
  merge design this fix generalises.
- T-154 — the project editor's save-failure rollback behaviour, preserved here.
- T-854 — description clearing must keep working (`clearDescription`).
