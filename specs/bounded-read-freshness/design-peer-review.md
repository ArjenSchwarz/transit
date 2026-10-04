# T-63 final design peer synthesis

Reviewed the approved requirements and proposed design after the local design-critic gate. `PERSONAL_PROJECTS=1` selects external-model mode in the actual peer-review-validator instructions, but its named external MCP reviewers are unavailable. The parent instructed us to respect the external review retry denial and use the documented fallback, so this design used two independent internal subagents with distinct correctness/feasibility and architecture/integration lenses. No new external review transmission occurred. This is internal peer validation, not cross-model validation or user approval.

## Findings and dispositions

Both peers validated the critic's three original concerns: whole-batch timeout selection must be independent of candidate serialization; unfinished aggregation must retain physical admission; successful response IDs and retained publication must commit together; and complete portfolio captures must reject missing canonical task/comment evidence. The revised mechanisms address those concerns.

Both independently identified a further intra-batch lost-update risk: two prepared whole-index versions for the same store could pass validation and then overwrite each other. Adopted correction: coalesce all selected creates/appends per store into one aggregate immutable candidate and combined reservation outside the gate; atomically transfer child reservations without a gap or double count; validate every aggregate before any commit; swap each store once. T2382's design already required an aggregate candidate and now the shared interface makes it explicit.

Architecture review confirmed `MCPRetainedViewSource` is compatible with immutable capture lookup while T2382 owns frozen scope/index/lifetime. Clarified completeness means the entire resolved portfolio/project scope plus required identity/comment closure, and forbids expanding a retained scope. Correctness review directly inspected merged `201205bd4e786c7f152d8f99006b37da7da888c7`: authoritative UUID-based comment coverage in `MCPRecordSnapshot.task` must remain unchanged even when portfolio attribution uses physical relationships. Admission/cutoff now explicitly precedes fallback preparation.

## Consensus and judgment

All three reviewers find no remaining design blocker. They agree that the isolated probes establish only timer independence, retained physical accounting, and one local history-fence case. Real HTTP/router availability, large payloads, live CloudKit history/import applicability, shared publication races, and empty-versus-purged history remain early implementation verification gates.

No substantive disagreement remains. A stronger complete-portfolio type could remove optional evidence fields internally; both peers consider validated construction/consumption adequate for design approval. A separate retention actor would simplify ownership but could schedule behind timeout delivery; short common-lock commits over prepared immutable candidates better fit the approved contract.

## Approval and next gate

The reviewed design proposes the `me.nore.ig.transit/read` metadata namespace, 4,850 ms internal cutoff plus 150 ms response headroom, supported saved-state history fencing with `incoherent_capture` fallback, explicit unknown freshness when import evidence is unavailable, and shared prepared publication machinery. T2382 separately proposes eight reusable views/16 MiB encoded retention alongside the ordinary eight/16 MiB store; their combined logical encoded ceiling is not a heap bound.

Does the design look good? User approval must be surfaced in the parent conversation. Do not create tasks or production implementation before that approval. After approval, the actual tasks skill has its own review and user approval gate; only then can production implementation begin. Align the dedicated branch to the merged foundation while preserving all other work. Coordinate heavy Xcode27/simulator gates through the parent.
