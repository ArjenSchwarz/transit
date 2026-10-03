## Overall assessment

The critic’s six findings were valid and the draft responses are directionally correct. Findings 3 and 5 are substantially resolved at the requirements level; findings 1, 2, 4, and 6 still leave approval or observable-contract blockers. The requirements should not advance to final approval yet.

## Requirements blockers

1. **P0 — Batch deadline semantics remain incomplete and the mixed-batch exception is unapproved** (`1.1`, `1.3`, `1.5`, `6.1`, `6.2`).  
   - For read-only JSON-RPC batches, “complete encoded batch response” is appropriately stronger than per-read production, but admission is underspecified: whether elements are admitted atomically, how the eight-slot limit applies to a batch, and when rejected elements’ clocks begin.
   - “Batch” also ambiguously refers to both JSON-RPC batches and `query_tasks` batch mode.
   - For mixed batches, producing a read result internally is not caller-observable if HTTP delivery waits 30–50 seconds for a write. It therefore does not provide the bounded endpoint response promised by Story 1.
   - **Suggested edit:** distinguish “JSON-RPC batch” from “task-query batch mode”; define one decoded-batch timestamp, per-element capacity handling, and whether aggregation/envelope serialization is included. Present the mixed-batch choices for approval: accept unbounded combined delivery with explicit documentation, reject mixed batches, or define another transport behavior. Do not make the current caveat final without approval.

2. **P0 — Additive metadata may contradict preservation of existing payload shapes** (`2.1`, `4.3`, compatibility contract).  
   Every success, including an empty array, must carry one result-level metadata object. The supplied documents identify no backward-compatible extension point for existing top-level arrays. Wrapping an array changes its shape; attaching metadata to elements fails for empty results and duplicates view-level evidence.
   - **Suggested edit:** clarify that “preserve payload shape” means preserving the existing data value within an approved outer MCP result extension, or explicitly approve an envelope/schema change. Exact field placement may remain design work, but the permitted compatibility boundary must be settled in requirements.

3. **P0 — “Coherent,” “relevant,” and “visible to the selected view” are not yet observable invariants** (`2.1`–`2.6`, `3.2`, `5.1`, `5.3`).  
   The critic correctly caught import relabeling, and `2.6` improves the draft, but it does not define what proves a multi-entity capture is one view. Nor does it define which store/import event is “relevant” or how an import is shown to precede the captured store version.
   - **Suggested edit:** require all selected entities, relationships, and totals to derive from one immutable store/context version or equivalent capture boundary, and require import evidence to be associated with a version no later than that boundary. Leave the SwiftData mechanism to design.

4. **P1 — Failure and latency diagnostics are insufficiently defined** (`1.2`, `2.6`, `4.1`, `6.1`, `6.2`).  
   `READ_FAILED` versus an existing error remains open, while `2.6` merely says “defined read failure.” Acceptance cannot be tested until a stable category or compatibility mapping is selected.
   
   Stage-level diagnostics are also a missing observable requirement **if explaining the existing 30–50-second delays remains an objective**. “Exhausted phase when known” has no phase taxonomy and permits no useful evidence. A response emitted at five seconds also cannot reveal when lingering work eventually completed.
   - **Suggested edit:** define stable phases such as admission/queue, refresh wait, capture/fetch, transformation, serialization, and batch aggregation. Require the timeout error to identify the active phase and monotonic elapsed time when determinable. If root-cause diagnosis is in scope, separately require correlated structured diagnostics for late completion/discard; this needs user approval because it adds an observability requirement. It need not change successful payloads.

5. **P1 — The eight-operation rule is not a complete resource contract** (`1.3`, `1.6`, `6.2`).  
   The critic response correctly adds disposal and retained-slot tests, but eight operations do not bound per-operation fetch/result memory. Permanently blocked work can also leave the endpoint permanently returning `READ_BUSY`.
   - **Suggested edit:** call this an “admission/concurrency bound,” not a general resource bound. Define JSON-RPC batch slot allocation and shutdown behavior. Ask the user whether operation-only bounding is acceptable or whether transient-byte/result-size limits are required. The value eight remains unapproved.

6. **P1 — Refresh precedence is improved but the observation window remains ambiguous** (`2.5`, `3.2`, `3.3`, `3.6`).  
   The success/failure/timeout/unavailable priority is useful, but the contract does not say when observation begins, whether a pre-existing in-flight import qualifies, which of multiple store events is relevant, or what happens when no refresh wait time remains.
   - **Suggested edit:** define the refresh-attempt observation interval and store identity. State that zero remaining refresh budget yields `timeout` only when a supported trigger or relevant in-flight import exists; otherwise `unavailable`. Event-source feasibility remains a design gate.

## Design and feasibility questions—not requirements blockers once semantics are fixed

- **Independent deadline path:** `1.4` cannot be met if a synchronous MainActor/SwiftData fetch blocks the executor needed to encode and transport the timeout. Design must prove an independent response timer/path and suppression of late publication.
- **Immutable capture feasibility:** prove SwiftData can provide the required cross-entity captured view while preserving saved local-write visibility (`2.6`, `3.4`).
- **Import evidence:** verify CloudKit events identify the running store/context in headless operation and distinguish success, failure, unrelated imports, and process-start uncertainty (`2.3`–`2.5`).
- **Cursor retention:** prove exact metadata and frozen page data can be replayed under existing byte, capacity, and expiry limits (`5.1`, `5.2`).
- **T2382 integration:** API/lifecycle and storage mechanics remain design work owned by T2382; T-63 only needs to preserve shared capture identity and freshness semantics (`5.3`).

## Critic-response validation

1. **Batch boundary:** partially resolved; read-only behavior is stronger, but mixed delivery and batch admission still block approval.  
2. **Consistency invariant:** partially resolved; correct intent, insufficient observable definition.  
3. **T2382 ownership:** resolved by the approved allocation and `5.3`.  
4. **Resources:** partially resolved; disposal/testing added, transient memory and permanently lingering work remain risks.  
5. **Cursor policy:** resolved well in `5.4`, including malformed-policy and cursor-resolution precedence.  
6. **Refresh outcomes:** mostly resolved; temporal/store relevance still needs definition.

## Document contradictions and approvals needed

- `contract-proposal.md` first says the **5,000/2,000 ms limits and shared capture ownership are unapproved**, but later sections and the decision log correctly record them as approved. Update the stale statements; only the 30,000 ms threshold, detailed integration, and remaining semantics are pending.
- Normative `1.5`, `2.2`–`2.3`, and `1.3` currently embed proposals explicitly marked unapproved. That is acceptable in a draft, but they must not be represented as final.
- User approval is still needed for: **30,000 ms recency**, **eight-operation admission limit and whether operation-only resource bounding is acceptable**, **mixed-batch delivery caveat**, **final error/metadata compatibility semantics**, **whether stage/late-completion diagnostics are required**, and **the final requirements as a whole**.
- Do **not** reopen the already approved scope/name/full-spec type, additive metadata, `refresh_if_needed`, 5,000/2,000 ms budgets, deferred refresh/maintenance tools, or shared saved-snapshot ownership split.
