# Bugfix Report: Vanished Task Edit Project Selection

**Date:** 2026-08-05
**Status:** Fixed — validated
**Ticket:** T-2018

## Description of the Issue

`TaskEditView` enabled Save when its stored `selectedProjectID` was non-nil, even when the matching `Project` model had disappeared from `@Query` after a local or CloudKit delete. The editor then constructed a merge showing a project change, but `TaskEditApplier` silently skipped that changed field because its `project` argument was nil. The surrounding transaction saved any other edits and dismissed the editor, leaving the task in its original project.

**Reproduction steps:**
1. Open a task assigned to project A.
2. Select project B in the editor.
3. Delete or otherwise remove B before Save, leaving its UUID in the picker binding but no model in the live project query.
4. Make another edit and tap Save.
5. Before this fix, the editor dismissed and did not move the task to B.

**Impact:** An explicit project move could be silently discarded. Other changed fields could still persist, making the successful dismissal misleading.

## Investigation Summary

- **Symptoms examined:** Save availability was based on `selectedProjectID != nil`, while model resolution happened separately through `projects.first`.
- **Code inspected:** `TaskEditView`, `TaskEditApplier`, task-edit merge regressions, project-change/milestone tests, `TaskService.changeProject`, and `MilestoneService.setMilestone`.
- **Hypotheses tested:** Atomic persistence was ruled out: the view already uses one `saveOrRollback` transaction. The failure was an absent validation boundary that allowed the applier to turn a requested project move into a no-op.

## Discovered Root Cause

`TaskEditView` treated a retained UUID as a valid selection even though only the resolved `Project` model can be supplied to `TaskService.changeProject`. `TaskEditApplier` compounded this by using a conditional binding in its project branch, so a missing model silently bypassed a field the merge explicitly marked changed.

**Defect type:** Missing validation / silent no-op.

**Why it occurred:** Picker state and the current SwiftData project collection can change independently when a project is removed while the editor is open. Neither the view nor the applier encoded the invariant that a changed project ID requires a live model.

**Contributing factors:** `TaskEditApplier` correctly accepts `nil` for unchanged optional updates, but the old project branch did not distinguish that valid case from a changed project with no model.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/TaskEditMerge.swift` — Adds `TaskEditProjectSelectionState` recovery presentation values and makes `TaskEditApplier` throw `projectNotResolved` before any mutation when a merge changed the project but no matching live model was supplied. An unchanged project still accepts a nil parameter.
- `Transit/Transit/Views/TaskDetail/TaskEditView.swift` — Keeps Save disabled unless the selected UUID resolves to a current model, repeats that preflight before conflict/no-change handling, and places the shared recovery view directly below the iOS picker and in a macOS `Project error` form row. The shared macOS form width is module-visible solely for the split extension.
- `Transit/Transit/Views/TaskDetail/TaskEditView+ProjectSelection.swift` — Keeps resolution and the shared in-form `Label` presentation separate so the main view remains under the enforced file-length limit. The label is visible in error styling and has explicit VoiceOver label/hint text explaining how to re-enable Save.
- `Transit/TransitTests/TaskEditConcurrentUpdateTests.swift` — Lets the shared applier fixture pass a genuine nil project for unchanged-project tests.
- `Transit/TransitTests/TaskEditProjectResolutionTests.swift` — Adds deterministic transactional applier, selection-state, visible/accessibility recovery, and unchanged-nil regressions.

**Approach rationale:** The editor now exposes a persistent recovery state rather than relying on an unreachable alert behind its disabled Save control. A user can immediately understand why Save is unavailable and choose a remaining project; the state and its accessible metadata disappear as soon as that selection resolves. The applier independently rejects misuse from any caller. Its guard runs before `updateTask`, milestone assignment, or status changes, preserving all-or-nothing rollback semantics; merge conflict and ordinary save-error flows remain unchanged.

**Alternatives considered:**
- Enable Save just to show the existing alert — rejected because it briefly permits a known-invalid action and weakens the existing `canSave` invariant.
- Silently keep the original project — rejected because it is the existing data-loss behavior.
- Require a project model for every applier call — rejected because unchanged project fields intentionally pass nil so concurrent project changes are not overwritten.
- Clear the stale project UUID automatically — rejected because it hides the removed selection rather than explaining why Save cannot proceed.

## Regression Test

**Test file:** `Transit/TransitTests/TaskEditProjectResolutionTests.swift`

**Tests:**
- `changedProjectWithoutResolvedModelFailsWithoutSavingAnyEdits` — wraps the applier in the editor's `saveOrRollback` transaction, expects the typed error, and asserts name, project, and milestone remain unchanged.
- `changedProjectWithMismatchedModelFailsWithoutSavingAnyEdits` — proves a non-nil but wrong project model cannot bypass the edited UUID check or save an unrelated edit.
- `vanishedProjectSelectionBlocksSaveAndProvidesVisibleAccessibleRecovery` — asserts a stale UUID/no-model state remains unsaveable while exposing the exact visible recovery message and VoiceOver label/hint consumed by both platform forms.
- `resolvedProjectSelectionCanSaveAndHidesRecoveryGuidance` — asserts matching ID/model state remains saveable and removes all recovery presentation values.
- `unchangedProjectDoesNotRequireAResolvedModelParameter` — asserts unrelated edits succeed with a nil project parameter.

Existing `TaskEditOrdinaryEditTests.changingProjectClearsMilestone` continues to cover Decision 6 project-move milestone clearing; `MilestoneService` project-match validation is unchanged.

**Run command:** `make test-quick`, plus the focused iOS class shown in `CLAUDE.md`.

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/TaskEditMerge.swift` | Resolved-selection state, visible/accessibility recovery values, and fail-closed applier error |
| `Transit/Transit/Views/TaskDetail/TaskEditView.swift` | Save availability/no-dismiss preflight plus iOS/macOS recovery placement |
| `Transit/Transit/Views/TaskDetail/TaskEditView+ProjectSelection.swift` | Extracted resolution and shared accessible recovery presentation |
| `Transit/TransitTests/TaskEditConcurrentUpdateTests.swift` | Nil-preserving applier fixture |
| `Transit/TransitTests/TaskEditProjectResolutionTests.swift` | Deterministic transactional and UI-state regressions |
| `CHANGELOG.md` | T-2018 release note |

## Verification

**Automated:**
- [x] `make test-quick` — passed after the final source changes.
- [x] Focused iOS `TransitTests/TaskEditProjectResolutionTests` — passed all five regression cases after the final source changes.
- [x] `make lint` — passed, including the SwiftData ownership guard.
- [x] `make build-macos` — passed before the final split extraction; the final macOS source then compiled and passed through `make test-quick`.
- [ ] `make test` — exceeded the 120-second runner limit during the initial iOS dependency build before tests began. The build compiled both changed production files without errors; the focused iOS suite passed afterward.
- [ ] `make test-ui` — executed the UI suite but retained three pre-existing failures: `TransitUITests.testClearAll`, `TransitUITests.testEditViewPreservesTaskMilestone`, and `DataMaintenanceUITests.testDataMaintenanceGoldenPath`. The relevant `TransitUITests.testMilestoneClearedOnProjectChange` passed.

**Manual verification:** The stale-state presentation is deterministically modelled by `TaskEditProjectSelectionState` and exercised through its exact visible/VoiceOver strings. Manual UI verification was not performed.

## Prevention

- Treat picker IDs as references, not proof that a live SwiftData model exists.
- When invalid state intentionally disables an action, expose persistent visual and accessibility recovery guidance outside that action.
- Validate a changed relationship at both the view and service/applier boundary.
- Preserve `nil` as “unchanged” only when the merge confirms that field was not edited.
- Keep fail-closed guards before any deferred transaction mutation so rollback is a safety net rather than the only protection.

## Related

- T-1798 — task editor three-way merge and selective writes.
- T-1935 — conflict rebasing and project/milestone pairing safeguards.
- Decision 6 — moving a task project clears its milestone.
