# Bugfix Report: Vanished Task Edit Project Selection

**Date:** 2026-08-05
**Status:** Fixed — unit execution blocked by unrelated MCP-port compilation failures
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
- `Transit/Transit/Services/TaskEditMerge.swift` — Adds `TaskEditProjectSelectionState` and makes `TaskEditApplier` throw `projectNotResolved` before any mutation when a merge changed the project but no model was supplied. An unchanged project still accepts a nil parameter.
- `Transit/Transit/Views/TaskDetail/TaskEditView.swift` — Disables Save unless the selected UUID resolves to a current model. Save repeats that preflight before conflict/no-change handling, sets an actionable error, and returns without dismissing when the selection vanished.
- `Transit/Transit/Views/TaskDetail/TaskEditView+ProjectSelection.swift` — Keeps the resolved-project preflight separate so the main view remains under the enforced file-length limit.
- `Transit/TransitTests/TaskEditConcurrentUpdateTests.swift` — Lets the shared applier fixture pass a genuine nil project for unchanged-project tests.
- `Transit/TransitTests/TaskEditProjectResolutionTests.swift` — Adds deterministic transactional applier, selection-state, and unchanged-nil regressions.

**Approach rationale:** The view catches the stale picker state early and gives the user a recovery path; the applier independently rejects misuse from any caller. Its guard runs before `updateTask`, milestone assignment, or status changes, preserving all-or-nothing rollback semantics.

**Alternatives considered:**
- Silently keep the original project — rejected because it is the existing data-loss behavior.
- Require a project model for every applier call — rejected because unchanged project fields intentionally pass nil so concurrent project changes are not overwritten.
- Clear the stale project UUID automatically — rejected because it hides the removed selection rather than explaining why Save cannot proceed.

## Regression Test

**Test file:** `Transit/TransitTests/TaskEditProjectResolutionTests.swift`

**Tests:**
- `changedProjectWithoutResolvedModelFailsWithoutSavingAnyEdits` — wraps the applier in the editor's `saveOrRollback` transaction, expects the typed error, and asserts name, project, and milestone remain unchanged.
- `vanishedProjectSelectionBlocksSaveAndSuppliesRetryableError` — asserts stale UUID/no-model view state is unsaveable and supplies the retryable error.
- `resolvedProjectSelectionCanSave` — asserts matching ID/model state remains saveable.
- `unchangedProjectDoesNotRequireAResolvedModelParameter` — asserts unrelated edits succeed with a nil project parameter.

Existing `TaskEditOrdinaryEditTests.changingProjectClearsMilestone` continues to cover Decision 6 project-move milestone clearing; `MilestoneService` project-match validation is unchanged.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/TaskEditMerge.swift` | Resolved-selection state and fail-closed applier error |
| `Transit/Transit/Views/TaskDetail/TaskEditView.swift` | Save availability and no-dismiss preflight |
| `Transit/Transit/Views/TaskDetail/TaskEditView+ProjectSelection.swift` | Extracted resolved-selection state |
| `Transit/TransitTests/TaskEditConcurrentUpdateTests.swift` | Nil-preserving applier fixture |
| `Transit/TransitTests/TaskEditProjectResolutionTests.swift` | Deterministic regressions |
| `CHANGELOG.md` | T-2018 release note |

## Verification

**Automated:**
- [x] `make build-macos` — passed after the final source changes.
- [ ] Focused unit test — blocked before execution because the shared `TransitTests` target has unrelated MCP-port API compile failures (`MCPPortChangeState`, `MCPPortChangeCoordinator`, and `MCPServer.activePort` are missing).
- [ ] `make test-quick` — blocked by the same unrelated MCP-port compilation failures. The compiler did compile `TaskEditProjectResolutionTests.swift` before reaching those failures.
- [ ] `make lint` — the SwiftData ownership guard passed and all T-2018 files lint clean; the command remains blocked by an unrelated pre-existing `type_name` violation in `MCPPortChangeCoordinatorTests.swift`.

**Manual verification:** The stale state is deterministically modelled by `TaskEditProjectSelectionState`; manual UI verification was not performed because the app build validates the production code and the unit target cannot execute until the MCP-port branch work is reconciled.

## Prevention

- Treat picker IDs as references, not proof that a live SwiftData model exists.
- Validate a changed relationship at both the view and service/applier boundary.
- Preserve `nil` as “unchanged” only when the merge confirms that field was not edited.
- Keep fail-closed guards before any deferred transaction mutation so rollback is a safety net rather than the only protection.

## Related

- T-1798 — task editor three-way merge and selective writes.
- T-1935 — conflict rebasing and project/milestone pairing safeguards.
- Decision 6 — moving a task project clears its milestone.
