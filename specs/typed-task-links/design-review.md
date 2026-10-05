# Typed links — design review and approval gate

Requirements approved at `748f474517d420498ccd9e54cf79f777e7763f57` by owner `Sentinel_36dc8dafea7c81919e7b060518fc9009`. Local approval record is `eedfc95`; initial design/self-validation is `35d47c8`. Design was approved by owner `Sentinel_775be6f4fc6c8191a9d7ccf1d0c04557` against reviewed checkpoint `56e9ad5`, including seven-day recognition and early feasibility gate.

## Review method and findings

Applied the actual starwave design, explain-like and design-critic workflows. The documented peer-review-validator internal fallback supplied two independent read-only perspectives because external reviewer tools were unavailable. No source disclosure, review CLI, test/build, live ticket call or implementation occurred.

| Reviewer | Material finding | Resolution |
| --- | --- | --- |
| Design critic | MainActor/history checks do not close validation-to-save races with peer contexts/imports. | Explicit early implementation enablement gate: demonstrate a supported mechanism before dependent graph-write work; failure keeps writes unavailable and returns design for review. No safety proof claimed. |
| Design critic | Repair expiry semantics could silently imply stable diagnostics. | Separate active deletion from bounded recognition. Expiry may end evidence-based conflict warnings/change derived assessments, never create/reactivate rows or change active content tokens. |
| Design critic | Projection omitted removal evidence/evaluation instant; removed-edge no-op lacked source incidence; same-relation remove/add unclear. | Frozen evidence/time inputs, retained incidence/fingerprint check, same-relation replacement rejected except different duplicate target retarget. |
| Design critic final | Saved-state semantic contradictions cannot be shape validation before replay. | Syntactic contradictions reject before acceptance; saved lookup-dependent conflicts validate as domain outcomes after retained replay. |
| Correctness peer | SCC and `unblocked:false` semantics need precision. | Structurally resolvable dependency rows enter SCC without hiding physical conflicts; assessments distinguish unblocked/blocked/invalid/unavailable. False selects certified blocked only. |
| Scope peer | Test trace must cover expiry/import arrival order and cleanup ambiguity. | Explicit verification includes changed diagnostics/stable active tokens/frozen views, both import orders, expiry/cleanup timing and deferred malformed/ambiguous cleanup. |

Critic confirmed its five gaps addressed for presentation with the validation classification refinement above. Both peers found no blocking contradiction or scope absorption. No material review disagreement remains. The early commit mechanism is an enablement blocker, not implemented or proven by these reviews.

## Retention choice

The owner challenged arbitrary30days (`Sentinel_69d82973f3b4819185f45cfc084147ea`); that question approves neither30 nor7. Recommend **seven days of optional exact-removal recognition**, matching existing write receipts as a convenience reference. Actual active occurrence deletion happens immediately in the protected local commit; SwiftData/Core Data owns deletion propagation/history. The app does not purge that history on the evidence horizon or invent a distributed tombstone protocol.

After evidence expires, an unknown old removal selector is unavailable. A conflict diagnostic whose sole basis was the evidence can expire, affecting derived assessments of an already imported active row; expiry cannot recreate a deleted row. A frozen retained view uses its original evidence/time. No horizon establishes remote convergence or remove-wins.

## Evidence and limits

Local source audit covers schema factories, task snapshot consumers, native destination resolution and foundation interfaces. Official Apple documentation supports additive production schemas, lack of CloudKit uniqueness/relationship atomicity, saved-fetch flags and platform persistent history/deletion. None proves migration against the user's store, atomic graph validation/save or remote deletion convergence. Early authorized implementation must verify disk migration and a supported commit mechanism before dependent feature work.

Implementation also waits for compatible merged T-63/T-2382/T-2383/T-2384 foundations, shared-file ownership transfer, a refreshed live schema and its own tasks/implementation approvals. All live Transit mutations are paused by the parent while the owner investigates duplicated records; no repair/status/comment/delete/guard reset is authorized.

## Exact next approval through the parent

**“Does the T-1734 typed-task-links design look good? Please choose the bounded removal-recognition horizon (recommended seven days) and explicitly approve the design, including the early migration/commit-boundary feasibility gate. Approval authorizes tasks planning only; graph writes cannot be enabled by MainActor/generation checks alone.”**

Do not create tasks until that approval. Phone transfer outcome is reported separately from document approval.

## Design gate outcome

Owner `Sentinel_775be6f4fc6c8191a9d7ccf1d0c04557` approved reviewed checkpoint `56e9ad5`, including seven-day removal recognition and the early migration/atomic-save feasibility gate. This authorizes task planning only. The approval question above is historical; next gate is task-plan approval through the parent.
