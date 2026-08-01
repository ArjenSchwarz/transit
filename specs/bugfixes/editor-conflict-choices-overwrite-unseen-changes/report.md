# Bugfix Report: Editor Conflict Choices Can Overwrite Unseen External Changes

**Date:** 2026-08-01
**Status:** Fixed
**Ticket:** T-1935

## Description of the Issue

The task, project, and milestone editors use a three-way merge to detect concurrent edits, but both conflict-resolution choices can still lose changes.

`Use Updated Values` copies only the fields that conflicted and then replaces the baseline with every current live value. Any untouched form field changed externally remains stale; after the baseline reset, the next save misclassifies that stale value as a user edit and writes it over the external change.

`Keep My Changes` recomputes the merge after the alert but authorizes every conflict in that recomputed merge with one Boolean. If another MCP, CloudKit, or window update changes a shown conflict or adds a new conflict while the alert is open, the save overwrites values the user was never shown.

**Reproduction steps:**
1. Open an editor and change one field locally.
2. Change that same field and an untouched field through another writer.
3. Save and choose **Use Updated Values**; observe that only the conflicting field refreshes.
4. Save again; observe that the stale untouched form value overwrites the external value.
5. Alternatively, while the first conflict alert is open, change a shown value again or create another same-field conflict externally.
6. Choose **Keep My Changes**; observe that the newly changed conflict is overwritten without a new alert.

**Impact:** High. All three editors can silently discard MCP, CloudKit, or second-window changes during the conflict flow that is intended to prevent lost updates.

## Investigation Summary

The existing T-1798 and T-1817/T-1880 reports, shared merge implementation, all three editor save paths, alert modifier, form rebasing methods, and editor merge regression suites were inspected.

- **Symptoms examined:** stale untouched fields after rebasing; conflict consent surviving changes to the alert's live state; multi-field changes across all editors.
- **Code inspected:** `Services/EditMerge.swift`, all three editor-specific merge files, all three editor views, `Views/Shared/EditConflictAlert.swift`, and the task/project/milestone concurrent-update suites.
- **Hypotheses tested:** Separate SwiftData contexts were ruled out because UI and MCP deliberately share `mainContext`. Save atomicity was ruled out because the loss occurs when selecting which values to apply, before persistence. Main-actor concurrency does not prevent the issue because the external write can run between alert presentation and button handling.

### Systematic inspection findings

1. **Data flow — incomplete rebase:** `ProjectEditForm.adoptLiveValues`, `MilestoneEditForm.adoptLiveValues`, and `TaskEditView.adoptLiveValues` copy only `conflictingFields`, then replace the full baseline with the live snapshot.
2. **State management — stale draft:** fields not edited by the user are not refreshed from live values, so they differ from the new baseline and become false user edits.
3. **Race/consent scope:** editor save methods accept `overwritingConflicts: Bool`; this carries no identity for the fields or values the user actually reviewed.
4. **Alert API:** the alert passes the shown merge to **Use Updated Values** but not to **Keep My Changes**, preventing exact-snapshot validation for one branch.
5. **Merge representation:** `EditMerge` retains only changed/conflicting field sets, not the original, edited, and live snapshots needed to validate consent or derive a correct rebase.

## Discovered Root Cause

The conflict flow treats both rebasing and overwrite consent as field-set operations when they are snapshot operations.

**Five Whys:**
1. Why can a second save overwrite an unseen external value? Because an untouched form field remains stale after **Use Updated Values**.
2. Why does it become writable? Because the baseline advances to live while the form does not, making the stale value appear user-edited.
3. Why is the form not fully rebuilt? Because adoption copies only fields classified as conflicts.
4. Why can **Keep My Changes** overwrite a later conflict? Because a Boolean suppresses conflict checks on a newly recomputed merge.
5. Why is the Boolean insufficient? Because the merge does not preserve the exact edited/live conflict snapshot shown to the user.

**Defect type:** Lost update caused by stale state rebasing and incorrectly scoped race-sensitive consent.

**Why it occurred:** T-1798/T-1817 added field-level conflict choices but encoded only which fields conflicted. The follow-up actions need the values shown at the decision point and a full-draft rebase policy, neither of which was represented.

**Contributing factors:** all actions run synchronously on `MainActor`, which makes each individual action atomic but does not prevent writes while a modal alert waits for input; project and milestone forms had testable rebase helpers, while task draft state remained embedded in the view.

## Resolution for the Issue

`EditMerge` now retains the original, edited, and live snapshots. Its shared `rebasedEdited` value starts from the complete live snapshot and overlays only user-changed, non-conflicting fields. **Use Updated Values** therefore refreshes every untouched or conflicting field while preserving only genuine non-conflicting local edits.

`hasSameConflictSnapshot(as:)` scopes consent to the exact conflict field set and original, edited, and live values shown in the alert. Both alert callbacks now receive that shown merge. Task, project, and milestone editors recompute immediately before either action; they proceed only if the current conflicts still match, otherwise they dismiss and re-present the current conflict snapshot after yielding to SwiftUI's alert lifecycle. The former `overwritingConflicts: Bool` bypass was removed.

Task, project, and milestone snapshots implement per-field replacement for shared rebasing. Each editor adopts the entire rebased draft and advances its baseline to the current live snapshot. Task milestone rebasing resolves the rebased milestone ID from the selected and current-live milestone candidates.

**Approach rationale:** Keeping snapshot identity and rebase policy in the shared merge layer gives all editors identical behavior and makes both race and rebase invariants directly testable.

**Alternatives considered:**
- Refresh only known untouched fields in each view — rejected because three hand-written policies would drift and still lack snapshot consent.
- Disable external writes while an alert is shown — rejected because MCP/CloudKit cannot be safely paused and cross-device writes are inherently concurrent.
- Accept consent for matching field names only — rejected because a second external value for the same field was not shown to the user.

## Regression Test

**Test files:**
- `Transit/TransitTests/TaskEditConcurrentUpdateTests.swift`
- `Transit/TransitTests/ProjectEditConflictDetectionTests.swift`
- `Transit/TransitTests/MilestoneEditConcurrentUpdateTests.swift`

**Tests:** Each editor has a multi-field rebase regression and an alert-race regression. They verify that untouched live fields refresh, genuine non-conflicting user edits remain pending, and both a changed value for the same conflict field set and a newly added conflict invalidate the shown alert snapshot.

**Red phase:** `make test-quick` failed while compiling `ProjectEditConflictDetectionTests.swift` because `ProjectEditMerge` had no `hasSameConflictSnapshot(as:)` member. This confirmed the required consent-scoping behavior was absent before implementation.

**Green command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/EditMerge.swift` | Retain snapshots and provide shared safe rebasing and exact consent validation |
| `Transit/Transit/Services/TaskEditMerge.swift` | Add task snapshot field replacement for shared rebasing |
| `Transit/Transit/Services/ProjectEditMerge.swift` | Add project field replacement and complete-form rebase |
| `Transit/Transit/Services/MilestoneEditMerge.swift` | Add milestone field replacement and complete-form rebase |
| `Transit/Transit/Views/Shared/EditConflictAlert.swift` | Pass the shown merge to both alert actions |
| `Transit/Transit/Views/TaskDetail/TaskEditConflictAlert.swift` | Forward the shown task merge to keep-mine handling |
| `Transit/Transit/Views/TaskDetail/TaskEditView.swift` | Recompute and validate both choices; adopt the complete rebased task draft |
| `Transit/Transit/Views/Settings/ProjectEditView.swift` | Recompute and validate both choices; re-alert on changed conflicts |
| `Transit/Transit/Views/Settings/MilestoneEditView.swift` | Recompute and validate both choices; re-alert on changed conflicts |
| `Transit/TransitTests/TaskEditConcurrentUpdateTests.swift` | Add task multi-field rebase and alert-race regressions |
| `Transit/TransitTests/ProjectEditConflictDetectionTests.swift` | Add project multi-field rebase and alert-race regressions |
| `Transit/TransitTests/MilestoneEditConcurrentUpdateTests.swift` | Add milestone multi-field rebase and alert-race regressions |
| `CHANGELOG.md` | Document the T-1935 fix |
| This report | Record investigation, implementation, and verification |

## Verification

**Automated:**
- [x] `make test-quick` — passed after the final regression assertions.
- [x] `make lint` — passed, including strict SwiftLint and the SwiftData ownership guard. `TaskEditView.swift` remains at the 400-line limit.
- [ ] `make test` — attempted twice. The first clean build and warmed retry each hit the 20-minute command timeout. The latest run built the app, launched the iPhone 17 simulator, and showed a large number of passing tests (including new project conflict tests) with no reported failure before timeout, but it did not emit a final suite result.
- [ ] `make test-ui` — not started because unrelated T-2019 and T-1768 `make test` processes remained active for more than 25 minutes on the same iPhone 17 simulator and another worktree began `make test-ui`. Those other agents' processes were intentionally left untouched.

**Manual verification:** Not performed; the merge invariants and all six task/project/milestone scenarios are exercised by the green macOS unit suite.

## Prevention

- Treat conflict consent as authorization for exact values, not a Boolean permission to overwrite arbitrary future conflicts.
- Rebase editable drafts by starting from the latest live snapshot and overlaying only known user-owned edits.
- Keep conflict policy in the shared merge layer so all editors remain behaviorally aligned.
- Keep same-field-value and newly-added-field alert races as separate regression assertions.

## Related

- T-1798 — initial task editor three-way merge
- T-1817 / T-1880 — project and milestone merge/load-once forms
