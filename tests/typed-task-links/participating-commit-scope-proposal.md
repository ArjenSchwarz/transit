# Task4 proposed commit scope — unapplied owner handoff

Reviewed source base: `c2b77cc`, inherited coordinator baseline `327390a`
(tested upstream blobs `e26efd4d2ce0ba534d2e4168aadd13cac6fb0ebe`).
Updated against the T2384 owner's reviewed source
`fc1b7d9d034cdcee1af7b822d3423c8830e01722` and
`/Users/arjen/Documents/Codex/2026-10-03/task-4/reviews/t1734-participating-commit-owner-review.md`.
The owner conditionally accepts the direction, retains shared-source ownership,
and has not applied or authorized a coordinator patch through that review.
This is a concrete patch request/interface sketch, not implemented source or
a passing runtime result. The existing 15-case source job stays pinned at
`de6ea49`; this update changes no test or runner source.

The amended contract coordinates participating shared-MCP operations on MainActor.
It does not fence independent containers or platform imports. Current `commit`
already performs policy validation, apply, terminal encoding and save without an
await. Its freshness gap is that policy/apply use the long-lived registered-model
cache in `services.context`. `includePendingChanges = false` alone does not prove
scalar refresh. The new existing-policy source test requires a conflict after a
peer saved revision change without injecting a fresh custom validator; its actual
RED/GREEN result is pending the assigned runtime slot.

## Proposed exact owner paths

1. `Transit/Transit/MCP/BatchWrites/MCPBatchWritePolicy.swift`: optional commit-services
   factory, nil by default to preserve existing callers. Proposed shape:

   ```swift
   let makeCommitServices: (@MainActor (ModelContext) throws -> MCPWriteCommitServices)?
   ```

   Requested initializer order against **fc1b7d9**, preserving every existing label:

   ```text
   makeCommitServices: ... = nil,
   onPendingEditsStop: ... = {},
   validateBeforeApply: ... = existing identity validator
   ```

   The factory is first, the current typed pending-stop observer second, and
   validation last. Audit labeled and trailing-closure callers rather than
   silently rebinding a validator to the observer. Preserve default nil-policy
   and policy-without-factory behavior. Preserve the owner's Task10 invocation
   of `onPendingEditsStop` at the actual synchronous dirty-stop branch; do not
   infer it from uncertain result text or post-await `hasChanges`.
   Expiry publication must read the fresh terminal
   receipt's expiry, not the original registered acceptance model.

   Keep the existing synchronous `validateBeforeApply` callback. The feature-local
   factory captures the caller's **original instances** of task and milestone
   DisplayIDAllocator and constructs a sealed `MCPWriteCommitServices` wrapper.
   Its only construction input is `(context, taskAllocator, milestoneAllocator)`;
   it constructs TaskService, ProjectService, CommentService and MilestoneService
   internally with exactly that context and their default context fetchers.
   No initializer accepts arbitrary `MCPWriteCommandServices`, a custom fetcher,
   or independently provided services. Read-only services/context access is
   sufficient for the coordinator. Thus construction proves all four private
   service contexts; checking only the plain services struct's `.context` does not.
   Do not expose/copy private allocator fields or create replacement allocators.
   The sealed shared wrapper's placement and source delivery need the coordinator
   owner's interface agreement; T1734 owns the feature-local factory and tests,
   not an unapproved shared-type source edit. No factory is implemented here.

2. `Transit/Transit/MCP/Writes/MCPWriteCoordinator.swift`: inside the existing fresh
   validated-bindings phase, and after existing shared-context clean checks, create
   one `ModelContext(services.context.container)` when this factory is supplied.
   Disable autosave and retain that context for the whole synchronous phase.
   Require the sealed wrapper to reference that exact context and remain clean
   with autosave disabled; never trust an arbitrary struct context field as proof
   of its constituent services. The coordinator owns this context's lifetime.
   Resolve the accepted receipt in this fresh context using the existing receipt
   store and original tool/key/local scope. Validate guard receipt ID, canonical
   request payload, format version and compatible retained state before applying.
   A valid fresh terminal receipt replays its original bytes/error immediately,
   bypassing graph/domain validation. Missing, inconsistent or unreadable accepted
   evidence stops apply and requires original-key reconciliation; never invent a
   new receipt/no-effect conclusion or move the shared acceptance model across
   contexts. A failed/mismatched factory never falls back to shared apply or
   saving/rolling back UI drafts. Revalidate the existing durable binding within
   its synchronous owned phase; do not replace the guard store or reset its key.

   Proposed flow (not compilable replacement code):

   ```text
   shared context clean checks and existing reservation binding validation
   fresh same-container context + sealed factory services + fresh receipt store
   refetch/validate exact receipt; terminal -> immutable replay
   missing/inconsistent/unreadable -> original-key uncertainty/reconciliation
   validateBeforeApply(command, freshContext)
   command.apply(prepared IDs/values, using: freshServices)
   stageTerminal(freshReceipt, encodedEnvelope)
   save(freshContext, .commit)
   existing sidecar expiry publication
   ```

   All source/endpoint/edge/removal predicates and the eventual full plan are
   validated immediately before apply from this fresh saved scope. Prepared
   creation/task commands carry IDs/values and can resolve in those services.
   No ModelData/private CoreData bridge, extra save, transaction marker, global
   lock, second coordinator or new store is proposed.

   Roll back only this owned scope on encode/apply/save failure. Durable recovery
   still uses existing independently resolved receipt evidence and original-key
   semantics. Rejection must stage and save its receipt in the corresponding
   owned scope; parameterize the existing rejection helper's context/receipt
   store rather than accidentally saving `services.context`. Preserve uncertain
   recovery and don't roll back pending UI drafts or downgrade a durable commit.
   A stale acceptance model left registered in the original context must not
   authorize repeat application: retain durable-before-live replay and route
   fresh acceptance/repair/rejection lookups through the owned scope as needed.

   Required branch audit for the owner patch:

   | Existing method/branch | Scope rule and preserved behavior |
   | --- | --- |
   | `runAccepted` preparation success | Recheck shared drafts after await, then create the fresh owned final phase; prepared values contain no models. |
   | `runAccepted` preparation error | Recheck shared drafts before rejection. Rejection/refetch/save must use the selected owned receipt scope; do not save shared drafts. |
   | `commit` success | Fresh guard/receipt and all four services, saved source/endpoint/edge/removal predicates, apply, terminal encoding and exactly one terminal save with no await. |
   | `commit` catch | Discard/rollback only owned staged changes; probe durable receipt before outcome selection. Durable terminal replays unchanged; only proven accepted-but-uncommitted evidence allows rejection. |
   | `completeRejection` | Parameterize chosen context/store and stage the corresponding refetched receipt there. Encode/save/recovery failures retain uncertainty; no stale original receipt or shared-context save. |
   | `recover` | Keep original-key durable evidence and terminal replay first. Route a required accepted-only rejection through owned refetch; don't let stale shared accepted state authorize reapply. |
   | `rejectBeforeDomain` | Preserve acceptance failure/reconciliation semantics and existing no-effect proof requirements. If scope cannot be constructed, don't infer effect absence or roll back/save UI state. |
   | Every dirty stop and dirty retained replay | No factory, reserve, expiry repair, cleanup, recovery hook, domain lookup or draft mutation. Preserve typed pending-stop observer and accepted/outcome/retryAction evidence. |

   No envelope-format changes are requested. Audit/refactor the chosen-scope
   parameters in `MCPWriteCoordinator.swift` rather than expanding Outcomes
   presentation or changing historic text/optional-error semantics.

3. Later startup/adapter wiring at `Transit/Transit/TransitApp.swift`, shared
   coordinator construction near line162, and the actual link adapter callsites:
   caller-known allocator/service factory only. This requires an explicit owner
   grant and real caller integration. Do not change startup storage, sidecars,
   lifetime, isolation settings, tool schema or handler construction incidentally.

   A default-nil factory does **not** fix the actual-SUT `.init()` stale-source
   expectation. Task4 must configure the real fresh-services factory in the
   participating policy exercised by that test and every feature graph-covered
   standalone and per-item batch callsite, then rerun the same stale-source
   rejection expectation against that configured SUT. Keep legacy/default-nil
   behavior separately labeled; a link-only opt-in does not establish freshness
   for all participating graph-covered property/status/comment operations.
   Factory/coordinator source alone is not GREEN until these callers are wired.
   The current limited import has no per-item batch runner handoff. T2384 must
   identify and refresh its approved merged per-item caller paths before that
   wiring; do not invent or import a batch executor here. The standalone routing
   owner path `Transit/Transit/MCP/MCPToolHandler.swift` currently calls
   `writeCoordinator.execute(tool:arguments:)` without a policy. The later link
   adapter must configure the concrete participating policy on graph-covered
   fresh routes there, preserving retained replay and leaving no nil-policy bypass.

`MCPWriteCoordinator+Outcomes.swift` and `MCPWriteOutcome.swift` need no proposed
format changes; keep existing dirty/replay envelopes and encoder. Existing default
batch policy behavior must remain covered. T2384 retains shared-file ownership;
none of these source edits is authorized by this document itself.

## Remaining evidence and dependent work

The 15-case prepared job covers existing-SUT source revision freshness, positive
fresh endpoint/cycle validation controls, participating phase ordering, originating
domain/graph/removal/terminal save success and failures, drafts and immutable replay.
Graph staging is test-owned, not a public link adapter or complete plan implementation.
Actual graph-covered endpoint/source guards and projection diagnostics still require
tasks5/6,9/10 and later adapter/integrated tests21/22. Primitive counterexample and
abort results remain documented limits; neither is an amended completion gate.
No CloudKit or all-writer proof is required or claimed.

## Owner patch request and delivery sequence

Parent schedules T2384's sole-writer patch from **fc1b7d9 or its explicitly
refreshed owner base**, preserving the active Task9/10 chain and pending-stop
observer. Do not replace that source with the older T1734 import. Requested
delivery: coordinator/policy plus agreed sealed-wrapper interface, exact component
manifest/base and owner source review. T1734 then supplies feature-local factory
construction/guards and acceptance fixtures against that interface. Caller owner
separately wires standalone startup/routing; T2384 separately wires the actual
Task10 per-item execution seam using existing UUID validation and the per-invocation
pending-stop observer. Current declaration shell/test adapter is not that runner.
Preserve original protected arguments/key and the same receipt engine throughout.

No shared-file editing is granted by this document. This is an implementation
handoff within the amended approved contract, with no new product decision.

## Acceptance-test matrix after the interface handoff

These are future acceptance requirements; the pinned 15-case run is unchanged.
Only its actual runtime result may be reported as executed evidence.

| Fixture/control | Required observation and minimum acceptance |
| --- | --- |
| Stale registered source, actual configured participating factory | Preload original source in shared context, save a peer change, submit the unchanged old revision. Production validator **and** apply resolve fresh scope; conflict contains current saved record, no domain/graph effect, retained rejection byte-identical. No custom prevalidation callback fakes SUT freshness. |
| Separately labeled legacy/default nil | Preserve baseline semantics and replay; never count this as fresh-scope GREEN. |
| Stale registered endpoint and changed cycle before apply | Factory-backed actual guards read fresh endpoint revisions and complete saved predicate; reject before owned effects. Full plan/projection semantics await their real components. |
| Sealed service ownership | Constructor's original context/allocator inputs build all four services; callback/apply resolve the supplied fresh context. No arbitrary services/custom fetchers, mismatched context or dirty factory output is accepted. |
| Factory throws / scope construction or receipt fetch fails | No domain apply/save and no shared UI rollback/save; preserve durable acceptance and original-key reconciliation. |
| Missing, duplicate, inconsistent scope/tool/key/ID/payload/format receipt | Stop without apply or fresh-key advice; ambiguity remains uncertainty, not chosen physical receipt. |
| Fresh terminal found before validation | Replay original bytes/optional error; zero graph validation/apply and no terminal rewrite or repair caused by replay. |
| Participating final-phase order | Validation, domain/graph staging, encode and terminal save remain synchronous; queued participating MainActor operation enters afterward. No import-exclusion claim. |
| Owned success | Source fields, exact edges/removal evidence and terminal receipt appear together in independently observed saved state; historic receipts untouched and expiry published from fresh receipt. |
| Apply/encode/save failure | Owned domain/graph changes absent when accepted-uncommitted is proven; corresponding rejection saved in chosen context. If durable terminal exists, replay rather than downgrade. |
| Recovery fails / outcome unavailable | Uncertain result retains acceptance/effect evidence and original-key action; no guessed no-effect result or reapply from stale shared receipt. |
| Preparation errors, `recover`, `rejectBeforeDomain` | Exercise each chosen-scope rejection/save path, not only `commit` success; no shared draft save/rollback. |
| Dirty before acceptance and after await success/error | Preserve inserted/edited/deleted UI drafts; stop through typed observer branch where applicable, zero factory/repair/save on dirty replay. |
| Retained replay after edits/deletion/new graph faults | Original content/error/revision bytes unchanged; bypass current graph/source lookup and preserve draft state. |
| Creation allocator identity and prepared values | Use original task/milestone allocator instances; creation resolves prepared IDs/scalars in owned services without model transfer or duplicate allocation. |
| Every graph-covered standalone and per-item route | Confirm actual factory opt-in for property/status/comment/create/update consumers as applicable, original tool/key/arguments retained, no nil-policy bypass; keep per-item pending-stop notification. No whole-batch atomicity claim. |
| Outside writer after validation | Preserve committed originating receipt and observed later saved evidence; actual projections update valid status assessments and report available invalid graph evidence, with no automatic repair or historical-race diagnosis. |
