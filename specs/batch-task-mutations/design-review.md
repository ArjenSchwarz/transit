# T-2384 Design Review

Status: design approved in parent at `Sentinel_717be95229c48191a7c41b6e5e467e4c` for `a5950e9`; review below records the design gate package. Requirements were approved at `Sentinel_35dae4e67398819184369b41649ec75b`; task planning and implementation remain separate gates.

Review [design](design.md), [three-level explanation](explanation.md), and [decision log](decision_log.md).

## Concrete design choices

- Public tool name `mutate_tasks`, with explicit mode and nested item operations; no outer durable batch key.
- Preview uses a fresh non-saving context and returns saved local observations only. Unsaved UI inserts/edits/deletions are never copied, returned, saved or discarded. Temporary fallback records are unavailable as saved evidence. Preview is advisory; later saved changes/imports can invalidate it.
- Execution reuses the app-owned T2380 coordinator. A batch-only policy permits validated saved receipt replay/key conflicts while UI edits are pending, using existing read-only binding/durable-receipt APIs. New acceptance or unresolved recovery stops rather than flush pending UI state.
- Fresh phase checks cover acceptance, both post-await preparation branches and all save/rollback/recovery routes. Dirty detection returns before mutation-capable handlers; accepted unresolved bindings retain original-key recovery semantics.
- A synchronous batch-only identity check immediately before new domain apply rejects ambiguous UUIDs without changing standalone default behavior or historical replay.
- A complete modern recovery response is preencoded through the agreed T2383/T63 adapter before effects. Preparation failure executes nothing; postcommit encoding failure selects ready bytes without invoking the failed encoder again.
- Exact evidence checks determine advancement; current expiry does not invalidate an established commitment. Cancellation has explicit stop reason/next index/optional blocker; all committed stays all_committed after final-item cancellation, although delivery can be suppressed.

## Review mode and findings

The local design-critic reviewed first. Two internal peers then reviewed recovery/correctness and API/integration, using the documented peer-review-validator fallback. After the owner's saved-only instruction, the design was amended and all three reviewed it again. No external disclosure or app tests occurred.

| Finding | Settled resolution |
| --- | --- |
| Fallback might re-enter failed encoder | Fully deliverable modern bytes before effects; encoding-free selection. |
| Advancement predicate vague | Explicit supported v1 type/key/identity/revision/date/error checks; preserve unknown source and separate expiry protection. |
| Cancellation lacks blocker before first item | Stop descriptor with optional blocker; exact summary precedence. |
| Pending-value preview conflicts with owner | Fresh saved-only non-saving context; no pending UI exposure. |
| Receipt-blind dirty block violates approved replay | Existing coordinator read-only terminal/key-conflict inspection while dirty; unresolved/new work stops. |
| Dirty guards could enter rollback handlers | Direct-return boundary rule and explicit table for every fresh coordinator phase. |
| Mirrored enum schema could reject whole batch | Domain status/type/priority are string types with descriptive values, without enum/const constraints. |
| T2383 fallback vocabulary differs | T2384 summary serialization_failed means unestablished effect evidence; no second batch receipt outcome namespace. |

Critic and both final peers report no remaining design-gate blocker or substantive divergence. They require implementation fixtures for saved-only preview and dirty committed/rejected replay, key mismatch, missing/inconsistent sidecars, expired/unresolved evidence, and UI edits during both preparation continuations. These tests must precede shared integration in the task plan.

## Coordination and limits

T2383's draft matches complete-fallback preparation and lossless source/presentation separation; its exact common serializer design/API remains subject to its own approval. T63 remains sole writer of existing shared server/types/dispatch/schema wiring until handoff. No signature is guessed, no shared file is edited, and preview gains no covered-read five-second guarantee or cursor publication.

The design maps all 32 approved criteria to components and verification scenarios. The explanation self-review and source-level document checks were completed. No production source, guard data, recovery action, heavy build/test, client/server setting, deployment, push or merge was performed.

## Approved design gate (historical request)

**Does the design look good?**

Approval includes `mutate_tasks`, saved-only preview, read-only replay plus dirty-phase protection, the optional batch identity policy, and fully prepared response fallback. Shared integration still waits for T2383's approved contract and T63's handoff. On explicit approval, begin the Rune task plan with its own review/approval gate; implementation remains separately authorised.
