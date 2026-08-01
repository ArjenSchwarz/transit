# Implementation Explanation: Editor Conflict Choices (T-1935)

Branch: `T-1935/bugfix-editor-conflict-choices-can-overwrite-unseen-external-changes`
Range: `origin/main...HEAD` (merge-base `ac6cef9`)

---

## Beginner Level

### What Changed

Transit can be edited from more than one place at the same time. You might have a task open in the editor while an AI agent updates the same task over the MCP server, or while CloudKit syncs a change you made on your iPad. Two writers, one record.

To handle that, the editors already did a **three-way merge**. Think of it as remembering three things:

- **original** — what the record looked like when you opened the editor
- **edited** — what is in the form right now, after your typing
- **live** — what the record looks like in the database *this instant*

Comparing those three tells the app which fields *you* changed and which fields *somebody else* changed. If you both changed the same field, that's a conflict, and the app stops and asks: **Keep My Changes** or **Use Updated Values**.

The bug was that both answers could still throw away changes you never saw.

**"Use Updated Values" was too narrow.** It only refreshed the fields that had conflicted. Say the agent renamed the task *and* rewrote its description, but you had only retyped the name. The name conflicted, so it got refreshed — but the description didn't conflict, so the form kept showing the old description. Then the app quietly declared "everything on screen is now up to date." On your next save, that stale description looked like something *you* had typed, and it overwrote the agent's version.

**"Keep My Changes" was too broad.** It set a single yes/no flag meaning "the user said overwrite." But the alert box is a modal — it can sit on screen for as long as you take to read it, and writers keep writing during that time. If the agent changed the field *again* while you were reading, or created a *second* conflict, that one flag still said "overwrite everything." You authorised overwriting values you were never shown.

The fix changes both answers to be **about specific values instead of about fields**:

- "Use Updated Values" now rebuilds the entire form from the live record, then puts back only the edits you genuinely made that nobody else touched. Nothing stale survives.
- "Keep My Changes" now remembers exactly which values the alert displayed. Before saving, it re-checks. If anything about the conflict changed, it throws away the old answer and shows you a fresh alert.

### Why It Matters

Silent data loss is the worst kind of bug, because nobody notices it until much later. The conflict alert exists specifically to prevent lost updates — it was leaking in both directions. This affects all three editors: tasks, projects, and milestones.

### Key Concepts

- **Three-way merge** — deciding what to write by comparing three versions instead of two. Git does this when merging branches; here it decides which form fields to save.
- **Snapshot** — a plain frozen copy of a record's values. Not connected to the database, so it can't change underneath you.
- **Baseline** — the "original" snapshot. Everything is measured against it, which is why advancing it incorrectly caused the bug.
- **Rebase** — rebuilding your work on top of someone else's newer version, rather than beside it.
- **Consent scoping** — an approval that covers one specific thing, rather than a blanket permission. "Yes, overwrite *this* name with *that* name" instead of "yes, overwrite."
- **Lost update** — two writers, and one silently clobbers the other.

---

## Intermediate Level

### Changes Overview

The change is concentrated in the shared merge layer, with matching updates in three editors.

**`Services/EditMerge.swift`** — the generic core.

- `EditMerge` now stores `original`, `edited`, and `live` snapshots alongside the derived `changedFields` / `conflictingFields` sets. Previously it discarded the snapshots after computing the sets, which is precisely why neither follow-up action could be implemented correctly.
- New `rebasedEdited: Snapshot` — folds `changedFields.subtracting(conflictingFields)` over `live`, overlaying each surviving user edit. Starting from `live` is the key inversion: the old code started from the form and patched conflicts, so anything not classified as a conflict stayed stale.
- New `hasSameConflictSnapshot(as:) -> Bool` — compares the conflicting field *set* and, for each field in it, the `original` / `edited` / `live` values. Field-name equality alone is insufficient: an external writer can change the same field twice while the alert is open.
- The `EditSnapshot` protocol gains `replacing(_:withValueFrom:)`, implemented per editor as a small switch.

**`Views/Shared/EditConflictAlert.swift`** — `keepMine` changes from `() -> Void` to `(EditMerge<Snapshot>) -> Void`, so both buttons now receive the merge that was actually rendered. Adds `presentEditConflict(_:in:replacingShownAlert:)`, which sets the binding directly for a fresh alert, or clears and re-sets it after a yield when replacing an alert mid-dismissal.

**The three editors** (`TaskEditView`, `ProjectEditView`, `MilestoneEditView`) — the `overwritingConflicts: Bool` parameter is replaced by `consentingTo: EditMerge?`. Both `save` and `adoptLiveValues` recompute the merge from current state before acting, and re-present the alert when the snapshot no longer matches.

### Implementation Approach

The organising insight is that both operations were modelled as **field-set** operations when they are **snapshot** operations.

Putting `rebasedEdited` and `hasSameConflictSnapshot` on the generic `EditMerge` means all three editors get identical semantics for free and both invariants become unit-testable without a view. This continues the trajectory of T-1798 → T-1817: policy migrates into the shared merge layer, editors keep only the state binding.

`adoptLiveValues` also advances the baseline to `merge.live` rather than re-reading the model. Since the form is populated from `merge.rebasedEdited`, which is itself derived from `merge.live`, form and baseline are guaranteed consistent — the old code read the model twice and could observe two different states.

### Trade-offs

- **Exact-value consent is deliberately conservative.** Any change to a shown conflict revokes the answer, even a change the user would have answered identically. The alternative — matching field names only — was rejected because a second external value for the same field was never displayed.
- **`EditMerge` grew from two `Set`s to two `Set`s plus three snapshots.** Negligible for a single-user app editing one record; it buys testability and correctness.
- **Per-field `replacing` switches are duplicated three times**, mirroring the existing `differs` switches. A keypath-based accessor could state the mapping once, at the cost of closure indirection and readability. Left as-is deliberately.
- **The `edited:` parameter on the three appliers is now redundant** — every call site passes `merge.edited`. Removing it would require touching test call sites, so it was left in place.

---

## Expert Level

### Technical Deep Dive

**Why starting from `live` is load-bearing.** The old `adoptLiveValues` computed `form ∪ {conflicting fields ← live}` and then set `baseline ← live`. For any field where `live ≠ original` and the field was *not* in `conflictingFields` (i.e. the user hadn't touched it), the form retained `original`'s value while the baseline moved to `live`. The next merge therefore classifies that field as `changed` — a phantom user edit that overwrites the external value. `rebasedEdited` inverts the construction to `live ∪ {changed \ conflicting ← edited}`, which makes the post-rebase invariant provable: for every field, form value equals either `live` (so no change is recorded) or a genuine user edit (so a change is correctly recorded).

The `reduce` over a `Set<Field>` is order-independent because each iteration writes a disjoint stored property.

**Consent scoping and the modal window.** `hasSameConflictSnapshot` compares all three snapshots, but only the `live` comparison can realistically differ: `original` is reassigned solely in `load` / `adoptLiveValues`, and `edited` derives from form state the user cannot reach behind a modal alert. The `original`/`edited` comparisons are defence-in-depth against a future non-modal presentation, not live guards.

Note what the predicate deliberately does *not* cover: an external write to a field the user never edited does not enter `conflictingFields` and so does not revoke consent. That is correct — such a field is not in `changedFields`, so the applier passes `nil` for it and the external value survives untouched.

**Cross-field consistency after a field-independent rebase.** This is the subtle failure mode, and it was found and fixed during pre-push review. `rebasedEdited` merges fields independently, so it can synthesise a combination neither side ever held. Concretely: task in project P1 with no milestone; the user picks milestone M2 (in P1) and retypes the name; externally the task is renamed differently *and* moved to P3. `.milestone` is `changed` but not `conflicting` (live milestone is still `nil` = original), so it is overlaid onto a `live` that carries project P3 — yielding project P3 paired with milestone M2 from P1.

The consequences cascade: the picker's `onChange(of: selectedProjectID)` guard is `newValue != task.project?.id`, and `newValue` *is* the live project, so the auto-clear never fires. `availableMilestones` filters M2 out (wrong project), so the picker renders blank. The next save sees `changed(.milestone)`, calls `MilestoneService.setMilestone`, and throws `.projectMismatch`, caught by the generic handler as "Could not save task. Please try again." Retrying always fails — the editor is unsaveable with no indication why.

The fix re-applies Decision 6 (moving project clears the milestone) to the rebased draft, in `TaskEditView.rebasedMilestone(milestoneID:projectID:candidates:)`. It follows the existing `availableMilestones` static-helper pattern so it is testable outside the view. The candidate set `[selectedMilestone, task.milestone]` is provably exhaustive: `rebased.milestoneID` originates from either `edited` or `live` by construction.

**Alert re-presentation.** SwiftUI cannot re-present an alert on the same binding inside its own dismissal transaction, hence `presentEditConflict`'s nil-yield-set sequence. This remains the weakest part of the change — see Potential Issues.

### Architecture Impact

`EditMerge` is now a genuine value-semantics merge object rather than a classification result. That is the right shape: consent, rebasing, and conflict description are all derivable from the three snapshots, and adding a fourth editor requires no new policy — only a field enum, a snapshot with `differs` + `replacing`, an applier, and load-once draft state (a value-type form where appropriate).

The asymmetry that made this bug possible survives: `ProjectEditForm` and `MilestoneEditForm` are testable value types, while task draft state remains eight `@State` properties in `TaskEditView`. That is why the task rebase needed a bespoke view-level helper while the other two are pure form methods, and why the cross-field defect landed on the task path specifically. Extracting a `TaskEditForm` would close the gap.

### Potential Issues

- **`presentEditConflict` rests on an unverified ordering.** `await Task.yield()` resumes on the next main-actor turn; the alert's `isPresented` setter writes `nil` when SwiftUI completes dismissal. Nothing orders the two. If the dismissal write lands last, the replacement alert is swallowed and the button appears inert. It fails safe (nothing written) and self-recovers (a second Save takes the direct branch and presents correctly), but it is untested — SwiftUI alert ordering is not unit-testable, and neither `make test` nor `make test-ui` has produced a clean run on this branch. A dismissal-driven queue inside `EditConflictAlert` would remove the assumption.
- **Both alert buttons can re-present**, including the `.cancel`-role one. Under a sufficiently aggressive external writer there is no path out of the alert. Judged acceptable: the write rate required is not realistic for MCP or CloudKit.
- **Form values are now normalised on adopt.** `adoptLiveValues` populates from snapshots, whose initialisers apply `trimmedForFormInput()` (and `normalizedHex` for projects). In-progress text like `"Foo "` is silently trimmed when the user picks "Use Updated Values" on an unrelated conflict. Cosmetic, harmless — form and baseline are normalised identically — but a behaviour change not covered by tests.
- **Consent is intentionally strict.** Users on a fast-syncing device could see the alert re-present more than once. Correct by design; worth watching if it becomes noisy in practice.

---

## Completeness Assessment

**Fully implemented**

- Full-draft rebase from the live snapshot across task, project, and milestone editors (`rebasedEdited`)
- Exact-value consent scoping with re-validation at button-press time (`hasSameConflictSnapshot`)
- Both alert callbacks receiving the shown merge; removal of the `overwritingConflicts: Bool` bypass
- Recompute-before-act in all six action paths
- Cross-field project/milestone consistency on the rebased task draft
- Regression coverage: six merge/rebase/race tests (two per editor), four rebased-milestone tests, two positive consent tests

**Partially implemented**

- **Alert re-presentation.** The mechanism exists and is documented, but rests on a timing assumption with no test coverage and no clean simulator run. Recorded as a known limitation in `report.md`.
- **Testability parity across editors.** Project and milestone rebasing lives in testable form types; task draft state remains in the view, mitigated by a static helper rather than resolved.

**Not implemented (deliberate)**

- Extraction of the duplicated conflict gate repeated across the three editors
- Removal of the now-redundant `edited:` parameter on the three appliers (would require test changes)
- Keypath-based unification of the paired `differs` / `replacing` switches
