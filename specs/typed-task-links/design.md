# Typed task links — design

Deferred destination: **T-2402 — Set up isolated CloudKit integration testing**, created and freshly verified by the parent through the installed UI (Transit, Idea/Research). No duplicate live ticket write.

Status: amended design approved by owner `Sentinel_08cb318218788191a85da25d1206979f` at `a64e595c439db6d62e46c85888f37130d53269fa`, adopting the simpler guarantee selected in `Sentinel_c95239aefa6481919303c2353b8a9e9c`. CloudKit test isolation/live Development verification remains deferred to T-2402; no live verification, schema promotion or client activation is claimed.

## Overview

Add saved task-link occurrences, a value-only graph projection and standalone protected link deltas. The graph joins task revisions, ordinary captured queries and read-only native details; T-2381 consolidation remains a separate feature.

## Architecture and integration

Place `TaskLinkOccurrence.swift` and `TaskLinkRemovalEvidence.swift` in `Models`, `TaskLinkService.swift` and `TaskLinkGraph.swift` in `Services`, and wire DTO/parser code in `MCP/Links`. Native `TaskLinksSection.swift` lives in `Views/TaskDetail`. Domain graph types are available on macOS/iOS; MCP-specific adapters remain macOS-only. SwiftData models stay on their owning actor; only immutable Sendable values cross task boundaries.

Implementation starts from a newly verified compatible merged base, after T-63, T-2382, T-2383 and T-2384 owner handoffs. Compare their final interfaces and refresh the running tool schema before coding. Approved foundation specs are inputs, not files this ticket edits. T-63 owns common reads/server/types until explicit transfer; T-2384 owns `MCPWriteCoordinator`; T-2383 owns the modern result adapter. T-1734 integrates through those interfaces after transfer.

| Pattern / audited call sites | Needs equivalent | Integration |
| --- | --- | --- |
| `TransitApp.init` schema; `TestModelContainer.init`; `tests/mcp-write-probe/{Probe,ServiceProbe,CoordinatorProbe,FoundationProbe}.swift` schemas | yes | Add occurrence/removal-evidence models in every schema that exercises task snapshots/writes; retain custom limited-schema tests only when deliberately graph-free. |
| `ContainerFactory.makeContainer` | no | Receives updated schema; fallback durability restrictions remain. |
| `MCPRecordSnapshot.task(_:in:)`, `task(_:fetchComments:)`; `MCPToolHandler+TaskQuery`; `MCPWriteCommand` create/update/status/comment snapshots; probe snapshot call sites | yes | Require graph incidence input; no overload may silently mint graph-covered revisions from missing evidence. Graph-free historic fixtures explicitly use legacy coverage. |
| T-63 `MCPReadCaptureBuilder`, `CapturedReadView`, `ReadTask`, persistent-history validation/fence | yes | Capture occurrence rows and endpoint closure inside the same saved fence, including active-link and removal-evidence history changes; freeze graph projection and coverage alongside task/comment revisions. |
| T-63 prepared read / `MCPPreparedToolRead` publication | no new engine | Graph filtering, traversal, encoding and retained bytes consume the existing deadline/physical permit and publication gate. |
| T-2382 portfolio summary and reusable snapshot query | yes, compatibility only | Keep selected scope/counts and project/status filters. Preserve current revisions when captured; missing graph coverage is explicit. Reject graph options without live enrichment. |
| `MCPWriteCommand.validate`, create/update prepare/apply; `MCPWriteCoordinator.execute` and all acceptance/recovery/post-await paths | yes | Parse deltas; generalize the merged clean-context policy for standalone graph writes. Preserve receipt-first behavior and one commit owner. |
| T-2384 batch parser/preview executor | yes, rejection only | Reject `linkChanges` and endpoint preconditions before any item/key acceptance. Preview uses current graph-covered task revisions but gains no graph mutation. |
| `TaskService.findByID`, UUID resolver paths | yes for graph/protected identity | Count complete UUID matches for all selected/affected tasks; never use first-match. Unrelated App Intent parity is excluded. |
| `TaskDetailView` iOS Form/macOS `LiquidGlassSection`; Dashboard sheet; `TaskDetailWindowView` UUID window | yes | Saved DTO section; revalidate unique destination before navigation and in window resolution. iOS pushes saved destination using existing detail view. |
| Task/milestone deletion, task sharing/export, App Intents, copying | no new capability | No cascading link deletion, new exports or mutation parity. Scalar references retain dangling evidence. |
| Tool definitions and T-2383 result encoder | yes | Add ordinary query/standalone input schemas and graph fields; preserve frozen result parity and historical receipt bytes. |

Audit baseline is source SHA `201205bd4e786c7f152d8f99006b37da7da888c7` plus the approved foundation worktree contracts. Repeat this table against the implementation base to include any new call sites.

## Persistent model and migration

`TaskLinkOccurrence` is an immutable active CloudKit-synced entity in the same store as tasks and receipts. Scalar fields have defaults: `id: UUID`, `kindRawValue: String`, `sourceTaskID: UUID`, `targetTaskID: UUID`, `createdAt: Date`. `TaskLinkRemovalEvidence` is a second entity in that same store with defaulted scalar fields: `id: UUID`, `edgeId: UUID`, the immutable occurrence values/`occurrenceRevision`, and `removedAt: Date`. No unique attributes, required relationships, task backreferences, delete cascades or new store. New instances always receive an explicit fresh UUID/time; defaults support schema compatibility, not semantic validity.

| Public input | Stored kind / orientation |
| --- | --- |
| A `blocks` B | `dependency`, A → B |
| A `blocked-by` B | `dependency`, B → A |
| A `relates-to` B | `association`, UUID lexical minimum → maximum |
| A `introduced-by` B | `attribution`, A → B |
| A `duplicate-of` B | `duplicate`, A → B |

Endpoints/type/id are immutable after insertion. Removal deletes the precisely identified active row and inserts removal evidence in the same protected local save; a re-add inserts a distinct occurrence. Active rows alone define incidence. Fetch all physical rows and retain their `LocalRecordKey` in captured values. Different UUIDs for equivalent active relations are conflicts, not automatic deduplication. Multiple physical rows with the same occurrence UUID make exact repair unavailable; do not expose an arbitrary row as actionable. An active row accompanied by matching removal evidence is explicitly conflicting imported evidence, not a valid relation or an automatically deleted row.

Repair-evidence retention is **seven days after removal**, matching the established write-receipt lifetime. This is a convenience horizon for recognizing exact removed occurrences and no-op retries, not a sync safety window, audit trail or undo history. Logically expired evidence cannot authorize repair/no-op; exclude it from projection regardless of cleanup timing. Expiry can end a conflict diagnostic whose only evidence was that removed-occurrence record, and can therefore change derived blocker/canonical assessments for an already present imported active row. It never inserts/reactivates that row or changes active incidence/content tokens, and never certifies remote correctness. A small maintenance hook deletes expired evidence only in an owned clean autosave-disabled context, never a read/preview or the UI context. Defer malformed dates/ambiguous evidence identity. Deleting evidence cannot reactivate a link because its active occurrence was already deleted at the protected commit. After expiry, unknown removal selectors are repair unavailable; original-key retries still follow independent receipt rules.

SwiftData/Core Data owns synchronization of actual occurrence deletion and its internal history/tombstones. T-1734 does not purge framework history, rebuild its CloudKit records or add an application tombstone protocol. [Apple describes deletion transactions and cautions that history must not be purged before consumers finish](https://developer.apple.com/documentation/coredata/consuming-relevant-store-changes). This supports using platform deletion, not a proof of remote convergence in this application's sync edge cases. Delayed/conflicting imports still receive diagnostics and do not imply global remove-wins; the repair-evidence horizon never controls framework deletion propagation.

Migration adds these two entities without rewriting `TransitTask`, comments or receipts. Existing tasks have empty incidence. Update all container schemas consistently. Validate an on-disk pre-feature store upgraded to the new schema before building dependent features; CloudKit development schema verification and production promotion are separate authorized release steps, never application-launch side effects in this spec. [Apple's sync guidance](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) establishes additive production schemas, optional relationships and lack of unique enforcement; it does not prove this migration against the user's store.

## Graph projection and algorithms

`TaskLinkGraph.project(tasks:occurrences:removalEvidence:evaluationInstant:budget:) throws -> TaskLinkGraphView` consumes captured values indexed by UUID **to all physical matches**. A unique UUID resolves; zero/multiple matches produce separate missing/ambiguous diagnostics. Index incidence by both scalar endpoints. Normalize input orientation before equivalent-relation lookup; preserve raw malformed imported rows as diagnostics. Use one frozen evaluation instant for expiry across MCP/native projections. Malformed, missing required fields or ambiguous removal-evidence identities produce diagnostics and cannot authorize a no-op; no actionable occurrence is invented. Sorting is deterministic by kind, source UUID, target UUID, occurrence UUID and physical key for diagnostics.

Compute dependency strongly connected components once in O(V+E) using every recognized dependency occurrence with structurally valid, uniquely resolved endpoints. Preserve repeated/equivalent physical occurrences and their diagnostics; never remove cycle evidence by deduplicating them. Unresolvable dependency endpoints stay invalid direct evidence outside SCC membership. Cycle members fail unblocked selection. For a candidate outside a cycle, inspect direct blocker evidence only: every incoming dependency must be unique, valid and resolve to raw/effective Done; unknown raw status fails. Do not follow duplicate aliases or recursively propagate a Done blocker's ancestry errors. An unresolved candidate dependency or multiple equivalent occurrences makes its blocker assessment unavailable/blocked, not unblocked. Association/attribution/duplicate edges never block. `blockerAssessment` is `unblocked` for complete valid Done/no-blocker evidence, `blocked` for complete valid direct evidence containing a known non-Done blocker, or `invalid` for cycle/identity/occurrence/unknown-status faults. Acquisition failure is a failed read, not an assessment. Missing retained graph coverage is `unavailable`.

Duplicate resolution walks the unique outgoing chain from the selected task, retaining an ordered UUID path and visited set. Zero outgoing means that task is canonical; one valid edge continues; missing/ambiguous endpoint, conflicting occurrence, multiple outgoing edges or repeated identity produces no canonical result and a typed diagnostic. Done/Abandoned status does not stop the walk. No path flattening or write redirect occurs.

`TaskLinkPlan.validate(delta:source:preconditions:savedGraph:)` evaluates the complete proposed result. Additions touching an invalid affected graph cannot certify cardinality/cycle safety and reject. Removing exact occurrences with no additions is the repair path: require unambiguous existing affected endpoints and exact row evidence, but allow incremental reduction without demanding unrelated corruption be repaired. Duplicate retarget is removal plus addition validated on the resulting graph; mixed field updates remain in the same local commit and do not weaken graph guards.

Every loop checks the supplied operation deadline; graph size/bytes are charged to the existing capture budget. Use iterative traversal rather than recursion. Stop on repeated identity and fail the whole requested read if the required closure cannot be captured within budget. Do not introduce an unbounded independent fetch/traversal engine.

## Wire contracts and protected writes

Use public type strings exactly `blocks`, `blocked-by`, `relates-to`, `introduced-by`, `duplicate-of`; there are no alternate spellings. Existing camelCase schema field conventions remain.

```text
linkChanges: [
  { action: "add", type: <public type>, targetTaskId: <UUID> },
  { action: "remove", edgeId: <UUID>, occurrenceRevision: <opaque token> }
]
endpointPreconditions: [{ taskId: <UUID>, expectedRevision: <r1 token> }]
```

Maximum 50 total directives. A remove and add of the same normalized logical relation in one request is rejected, including an already-present add combined with removing its occurrence; use separate protected requests for re-add. Removing one duplicate target and adding a different target is the approved retarget exception. Create permits additions only; update requires source `expectedRevision`, even for a no-op. Endpoint preconditions have unique task IDs and no source duplicate. Require precisely the other existing endpoints whose active incident membership changes; extra or contradictory guards reject. Already-present additions require source revision but do not change membership of the opposite task. Shape validation rejects unknown fields/actions/type spelling, malformed UUID/token, oversize arrays and syntactically detectable contradictions before key acceptance. Conflicts that require mapping a saved edge selector to semantic endpoints are domain validation after retained replay/key acceptance, together with reference, cardinality and cycle validation. Omitted `linkChanges` leaves links unchanged.

An `occurrenceRevision` is `l1:<SHA256>` over canonical id/kind/source/target/creation values, excluding removal-evidence timestamps. It is issued only for a uniquely identified physical occurrence. Removal requires the row be incident to the source and the selector match immutable values; same occurrence UUID collisions are never resolved by the token. Matching unexpired removal evidence whose original occurrence was incident to the selected source and whose fingerprint matches yields the protected no-op without a new timestamp/removal record. Missing identity after retention or token mismatch yields repair unavailable/conflict; it does not remove by endpoints or semantic equivalence.

Use merged T-2384 coordinator policy as `MCPWriteExecutionPolicy` with clean-context guard and synchronous pre-apply validation, rather than a second coordinator. Its batch caller behavior remains intact. For graph directives, order is:

1. Validate shape, tool enablement, durable store and exact tool/store key binding. Inspect retained exact outcome before current task/link lookups, graph validation or fresh revisions. Dirty-context replay uses read-only durable receipt/sidecar inspection; never recover/repair/save during it.
2. For a new accepted operation require a clean shared context before any baseline/acceptance save. Refuse without domain effects if not clean. Acceptance receipt/sidecar rules remain T-2380's.
3. Perform existing asynchronous preparation/display-ID allocation. Check clean-context policy on **success and failure after every await**, before any save or rollback. Dirty state after acceptance reports uncertain/reconcile as the foundation defines and preserves UI edits.
4. Capture saved task/comment/occurrence evidence in a fresh autosave-disabled context, validate unique source/affected endpoint identities, compare graph-covered revisions and build the full plan. Immediately before apply, in one synchronous MainActor phase, re-fetch/refault authoritative affected rows and graph from saved evidence, validate current saved revisions and complete proposed invariants, then apply and stage/save without awaits. A changed or unavailable validation observation rejects/conflicts before domain effects. Independent writers or imports may still commit after this validation; subsequent saved projections report inconsistent evidence.
5. Insert/update task fields, delete/insert precisely attributable occurrences and insert removal evidence and terminal receipt, encode the terminal result, and save them once in the same local store. No endpoint task timestamp is bumped merely for an incident link; its covered token changes from incidence. On pre-save failure, rollback only coordinator-owned changes from a proven clean entry. On uncertain durability retain original-key reconciliation, never fabricate no-effect.

Participating writes are standalone and per-item batch executions routed through the shared `MCPWriteCoordinator` on its MainActor. Their synchronous validation/apply/encoding/domain-save phase has no await; asynchronous preparation remains outside it and every post-await path checks for dirty context. Native/UI work using the same shared MainActor context cannot interleave that phase, and unsaved drafts remain protected by the clean-context rules. Independent containers, App Intent/native paths outside this context, and platform sync/import writers are outside this coordination guarantee. Do not infer their participation from being part of Transit; no all-writer lock or new persistence owner is introduced.

The originating local save commits its task fields, attributable edge/removal evidence and terminal receipt together. Immediate saved validation provides an observation, not an atomic predicate fence against outside writers. Such a writer can invalidate an endpoint, insert a cycle/duplicate target or change exact repair evidence before this save, temporarily leaving inconsistent links that can remain until explicit repair. Valid endpoint status changes update blocker/canonical assessments; historical race attribution is not inferred. Graph projection preserves and reports available invalid evidence on subsequent saved reads under requirements 2.3/3.4/5.3–5.5; notification refresh uses existing saved/import invalidation, while retained captures keep their original evidence. No post-commit rollback, automatic repair or downgrade of a retained committed receipt occurs. Retained exact outcomes continue to replay after later conflicts/deletion. See ADR 4 for the guarantee boundary.

## Task revisions and output

Extend the one task snapshot builder with required incidence evidence and `revisionCoverage: "task-fields-comments-links-v1"`. Canonical covered fields add `linkContract: "task-links-v1"` and a sorted `incidentLinks` array, including `[]`; each active physical occurrence contributes id/kind/source/target. Do not normalize conflicting rows into one valid identity. For malformed/colliding evidence include deterministic multiplicity/raw endpoint/type evidence sufficient to prevent changes being hidden by the hash; preserve explicit diagnostics. `r1` syntax remains unchanged. Old tokens conflict for every fresh preconditioned task status/property/link write; project/milestone/comment token contracts retain their entity coverage.

Labels, endpoint status, duplicate path, blocker assessment and removal-retention timestamps are separate observation fields. They never enter a source task's incidence hash. Require full comment evidence for authoritative task revisions even when comment bodies are omitted. No task snapshot overload may label absent graph evidence as an empty incident set.

Full detail adds `links` (edgeId, occurrenceRevision when actionable, stored endpoint IDs, public type, outgoing/incoming direction, observed label), `linkDiagnostics`, `duplicateResolution` and `blockerAssessment`, with `graphCoverage`. Summary/body omission preserves coverage/token where that surface already supplies an authoritative revision; omission is not empty incidence. Capture metadata supplies the common snapshot/asOf boundary for labels/status and derived assessments. Historic receipt text/bytes remain immutable; T-2383 may report graph coverage unavailable in supplemental presentation without relabeling or reminting the original result.

## Saved captured queries and native details

Ordinary query options add `hasLinks: Bool`, `linkType`, `linkDirection: outgoing|incoming`, `linkTargetTaskId` and `unblocked: Bool`. Reject opposite-endpoint/direction without a type; reject direction on dependency/association types, whose named views fix orientation. Type/target filters require a matching valid edge; `hasLinks` reports recorded active incidence including invalid evidence, while detailed diagnostics distinguish validity. Combine predicates conjunctively with existing selectors; `unblocked:false` matches certified `blocked` assessments only; `invalid`/`unavailable` assessments match neither Boolean value and remain visible through diagnostics in ordinary unfiltered detail. Reusable T-2382 queries reject all these options before snapshot lookup/publication.

Extend the T-63 selected capture to include graph occurrence values plus required endpoint/status/identity closure. Selection membership is fixed before closure; closure tasks cannot become selected rows or change counts. Whole dependency graph evidence is required where imported-cycle membership cannot otherwise be established; bounded failure replaces incomplete success. The builder uses a fresh read context with `includePendingChanges = false`, freezes values and verifies its persistent-history/generation boundary including occurrence/removal-evidence inserts/updates/deletes. [Apple documents the fetch flag](https://developer.apple.com/documentation/swiftdata/fetchdescriptor/includependingchanges); it is not a substitute for a fresh context/fence.

T-63 prepares/freeze-encodes the complete tool result before late-publication checks; T-2383 consumes that frozen fragment. Added DTOs, graph indexes/closure, encoded results and retained graph evidence count toward the existing five-second read and 16-MiB/eight-view/five-minute retention policies. Cancellation does not release a lingering physical slot early. Cursor/snapshot publication remains behind the existing gate. A retained view lacking graph coverage yields explicit unavailable graph data; no live endpoint join.

`TaskLinkService.savedDetail(taskID:)` returns a value-only saved projection for native details using the same graph semantics. An unsaved source has no saved relationship section; explain it as unavailable until saved. For existing tasks, use saved endpoint names/statuses even while draft editors are open. Refresh on saved store/import notifications; cancel stale completions by selected task/generation, never replace a newer section with older output.

Match `TaskDetailView`'s iOS `Section/LabeledContent` and macOS `LiquidGlassSection/FormRow` patterns. Group incident views by public type and label incoming attribution/duplicate edges explicitly. Show unresolved identity/canonical diagnostics inline. On click, re-resolve exact UUID uniquely from saved state; macOS calls the existing UUID task window, whose resolver also rejects multiple matches; iOS pushes the existing detail view after revalidation. No guessed URL, inline editor, merge, close or undo action.

## Failures

| Boundary | Outcome / effects |
| --- | --- |
| Unsupported type/options, malformed or oversize delta | Existing invalid-input shape failure, unaccepted key, no effects. |
| Missing/ambiguous source or existing affected endpoint, unknown exact occurrence | Identifiable identity/repair unavailable; no domain effects. |
| Fresh task/occurrence precondition mismatch | Conflict with current saved graph-covered evidence when establishable; no domain effects. |
| New cycle, duplicate cardinality or uncertifiable affected graph | Accepted domain rejection; saved protected outcome, no domain effects. |
| Saved capture failure/deadline/capacity/fence failure | T-63 typed failure, no partial graph success or late publication. |
| Dirty UI context / uncertain commit or delivery | Foundation unavailable/uncertain with acceptance/reconciliation evidence; preserve drafts, retry original key. |
| Imported invalid graph | Read diagnostics; dependency/canonical assessments fail closed; exact removal-only repair remains available where identity is established. |

## Risks verified during authorized implementation

- Risk: additive SwiftData/CloudKit migration differs on production-shaped stores | Verify: first implementation spike opens a copied/synthetic pre-feature disk store; live Development schema/export/deletion verification is deferred under the owner amendment | If wrong: stop rollout and revise migration; never reset/delete the user's store. Local success does not certify remote compatibility or authorize production promotion.
- Risk: coordinator-owned task/link/removal/terminal-result changes do not save together or dirty drafts leak through | Verify: disk-backed participating-write, saved-validation, dirty-context and save/encoding failure tests before graph integration | If wrong: keep affected writes unavailable and fix the owned-save boundary.
- Risk: complete cycle/closure capture exceeds existing limits at realistic graph size | Verify: early bounded-read scaling fixture under the unchanged budgets | If wrong: return typed capacity/deadline failures and optimize bounded projection; no larger budget or partial unblocked guarantee without approval.

## Verification plan and traceability

No build/test/runtime validation occurs in this design phase. The implementation phase uses owning `TestModelContainer`, serialized Swift Testing and explicitly granted heavy-job slots. Start with migration, participating-write coordination and owned-save failure cases before dependent UI/query work. Keep independent-writer counterexamples as documented-limit tests, not an all-writer atomicity gate.

| Requirements | Component / meaningful verification |
| --- | --- |
| 1.1–1.5 | Normalizer/index/wire parser: all directions, reversed association idempotence, malformed/self links, same/different UUID collisions, cross-project identity and labels. |
| 2.1–2.4 | SCC/direct blocker projection: Done vs Abandoned/unknown, imported cycles, valid Done blocker with unrelated bad ancestry, no alias traversal. |
| 3.1–3.5 | Attribution and duplicate projection/plan: multiple sources, retarget, chains and terminal states, branching/dangling/cycles, no field/status redirection. |
| 4.1–4.6 | Parser/coordinator/plan: 50 bound, endpoint guards, mixed fields/edges, no-op, race after allocation, replay-first, exact tool/store binding, dirty context success/error/recovery and crash/delivery evidence. |
| 5.1–5.6 | Snapshot/occurrence/migration: empty-set token transition, incoming-token changes, excluded labels/status/removal times, removed re-add identity, expiry token stability plus changed derived diagnostics/assessments and frozen-view preservation, active/removal imports in both arrival orders, expiry/cleanup timing, malformed/ambiguous evidence deferred from cleanup, precise incremental repair, historic bytes preserved. |
| 6.1–6.6 | Capture/filter/encoding: direction predicates, closure scope, pending insert/edit/delete exclusion, failed fetches, frozen replay, missing coverage, retained bytes/deadline/lingering limits and structured/text parity. |
| 7.1–7.4 | Saved native section/window and schemas: saved labels, destination collision/revalidation, consistent native styling, batches reject graph input before acceptance, caller guidance. |
| 8.1–8.3 | Disk and multi-context integration fixtures spanning preceding rows; no store reset or global convergence claims. |

Use deterministic generated small graphs with seeded generators in Swift Testing (no new PBT library) to compare normalized incidence, SCC membership and duplicate resolution to a simple independent reference. Properties: inverse/reversed normalization equivalence; permutation-invariant projection/hash; cycle insertion rejection; valid exact removal changes only the selected occurrence; re-add identity differs; raw retained replay is invariant under later graph edits. Example fixtures cover dirty-context/crash/migration timing that generated pure graphs cannot establish.
