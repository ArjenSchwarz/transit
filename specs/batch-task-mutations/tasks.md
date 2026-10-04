---
references:
    - requirements.md
    - design.md
    - decision_log.md
metadata:
    approval: Sentinel_edf7fd12288c819192ad45a04154372a
    status: approved; conditional implementation
---
# T-2384 Batch Task Mutations Implementation Tasks

- [x] 1. RED: Specify saved-only observation and every dirty coordinator boundary <!-- id:eptphz2 -->
  - Create MCPBatchTaskSafetyTests.swift with owning persistent TestModelContainer fixtures and independent durable readback. Unsaved insert/edit/delete never appear in a private read context; shared values, hasChanges, autosave and pending edits survive success and fetch failure without save/rollback/refresh.
  - Extend MCPWriteCoordinatorTests.swift with batch-policy fixtures: dirty committed/rejected terminal replay, payload mismatch, absent sidecar with independently valid receipt, inconsistent binding, expired/missing/unresolved receipts and active keys. Spy forbids reserve/recordExpiry/repair/cleanup/recover hooks/domain reads on dirty retained inspection.
  - Inject UI edits during both preparation success and exception/cancellation continuations. Require direct uncertainty return preserving accepted binding and UI edits; table-drive acceptance failure, commit failure and terminal-rejection failure routes so dirty states cannot enter rollback handlers. Standalone nil-policy behavior remains equivalent.
  - Test synchronous pre-apply UUID callback: zero/multiple matches and fetch failure reject new apply; inject ambiguity after preparation before commit, validate no suspension through lookup/revision/apply, and ensure historical replay bypasses deleted/ambiguous target. Use @MainActor, import Foundation, serialized Swift Testing and owning custom persistent fixture with cloudKitDatabase none.
  - Separate dirty admission/post-await fixtures from failures inside an already-clean synchronous phase. MainActor UI edits cannot interleave within that phase; save fault hooks exercise only its own staged-change rollback, never manufacture impossible mid-phase UI edits.
  - Initially fail against absent batch context/policy. Execute targeted tests only after implementation authorisation and T63 releases heavy slot; use isolated test stores, never production guard/recovery actions.
  - Stream: 1
  - Requirements: [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.5](requirements.md#4.5), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: Transit/TransitTests/MCPBatchTaskSafetyTests.swift, Transit/TransitTests/MCPWriteCoordinatorTests.swift, Transit/TransitTests/TestModelContainer.swift, design.md

- [x] 2. GREEN: Implement private saved-read context and optional batch execution policy <!-- id:eptphz3 -->
  - Create feature-local MCP/BatchWrites saved-read context factory over the persistent container with autosave false and pending changes excluded; no saved evidence from in-memory fallback. Wire this factory into the later preview path, not UI services.
  - Modify MCPWriteCoordinator optional internal batch policy, default nil: existing validated binding and durable receipt APIs establish terminal replay/key reuse read-only while dirty; no stores/schema/expiry algorithms/new recovery engine edits. Missing sidecar repair is skipped, inconsistent/unreadable evidence stops.
  - Apply direct clean-phase guards before every fresh save/recovery/rollback-capable route and after both preparation continuations. Never throw dirty detection into catch; accepted dirty stop retains unresolved binding, original-key reconciliation, no no-effect inference. Own synchronous staged changes may proceed.
  - Add synchronous pre-apply UUID uniqueness callback in fresh commit after clean baseline, bypassed by historic replay. Pass no model/Any values across actors. Stop feature availability if fixtures cannot prove boundary; no flush or discard fallback.
  - Blocked-by: eptphz2 (RED: Specify saved-only observation and every dirty coordinator boundary)
  - Stream: 1
  - Requirements: [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.5](requirements.md#4.5), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: Transit/Transit/MCP/Writes/MCPWriteCoordinator.swift, Transit/Transit/MCP/BatchWrites/, design.md

- [x] 3. RED: Prove complete fallback preparation and source evidence fidelity <!-- id:eptphz4 -->
  - Create MCPBatchTaskEvidenceTests.swift and MCPBatchTaskEncodingTests.swift using delivered T2383 source/encoder interfaces and synthetic batch aggregates. External seam prerequisite in task-review.md applies; no invented common signatures. Require DELIVERED T2383 task15/gpzncvz commit/interface with tasks3/gpzncvn,5/gpzncvp,7/gpzncvr,9/gpzncvt; task approval alone is insufficient.
  - Inject fallback preparation failure before any executor call, and final payload/adapter/envelope failure after synthetic commit. Require correlated complete ready bytes with RPC ID and modern text/structured/metadata; selection invokes no encoder. Exercise large production-shaped historic records and compact index/tool/key/UUID fallback omitting unbounded itemId/records.
  - Test full unknown JSON, absent/null optional fields and original text/isError; strict committed predicate: numeric1/1.0 versus Boolean/string, exact tool/key, task/comment identities, revision syntax, status reason comment, timestamp/expiry relation, error contradictions. Expiry crossing classification time never downgrades proven commitment. Malformed/unsupported evidence stops, categories cannot override retryAction.
  - After delivered common source/encoder APIs, test approved 32-container cap (root object/array1, scalar0): retained over-cap keeps raw text/isError unestablished; individually readable source nested into over-cap generated aggregate selects already prepared shallow serialization_failed bytes after effects. Giant itemId/raw records/entity links in normal context never reappear in compact fallback. No new no-effect/fresh-key inference.
  - Initially fail against absent batch evidence classifier/fallback builder. Use synthetic source only; T2383 common API delivery is not blocked by this consumer test.
  - Blocked-by: eptphz3 (GREEN: Implement private saved-read context and optional batch execution policy)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [4.3](requirements.md#4.3), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: Transit/TransitTests/MCPBatchTaskEvidenceTests.swift, Transit/TransitTests/MCPBatchTaskEncodingTests.swift, design.md, task-review.md

- [x] 4. GREEN: Implement batch evidence classifier and ready fallback adapter <!-- id:eptphz5 -->
  - Create MCP/BatchWrites evidence and encoding components consuming approved delivered lossless T2383 JSON/source/encoder types. Preserve source independently of supplemental diagnostic and aggregate isError; no receipt rewrite/live reconstruction/second serializer.
  - Build generated serialization_failed source with effect evidence unestablished and original input indexes/operation/key/UUID reconciliation. Prepare entire deliverable modern bytes before effects; absence/failure of adapter blocks dispatch. Selection returns ready immutable bytes without encoding and retains T63 cancellation/HTTP ownership.
  - Wire classifier/fallback into feature-local coordinator construction as required dependencies; later executor cannot bypass readiness. Resolve serialization resource risk now before further execution integration.
  - Blocked-by: eptphz4 (RED: Prove complete fallback preparation and source evidence fidelity)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [4.3](requirements.md#4.3), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: Transit/Transit/MCP/BatchWrites/, design.md

- [x] 5. RED: Specify whole-request parser and nested operation schema boundaries <!-- id:eptphz6 -->
  - Create MCPBatchTaskRequestTests.swift with 0/1/50/51 items, explicit mode/operation, unknown/missing fields, actual JSON type checks including Boolean versus numbers, UUID/revision/key patterns and itemId duplicates.
  - Use seeded generated permutations/collisions to prove normalized UUID uniqueness while retaining original spelling and original operation arguments; duplicate tool/key pairs and same-task aliases reject whole shape before key acceptance.
  - Assert status/type/priority invalid strings and missing conditional status-comment author remain per-item domain errors, never schema enum/const rejection; add_comment does not require/accept invented revision precondition. Nested schema descriptor uses delivered richer common schema types; registration deferred to shared owner.
  - Blocked-by: eptphz5 (GREEN: Implement batch evidence classifier and ready fallback adapter)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [4.1](requirements.md#4.1), [6.2](requirements.md#6.2)
  - References: Transit/TransitTests/MCPBatchTaskRequestTests.swift, requirements.md, design.md

- [x] 6. GREEN: Implement bounded request parser and schema descriptor <!-- id:eptphz7 -->
  - Create MCP/BatchWrites request/parser/schema descriptor for mutate_tasks with explicit dry_run/execute, 1–50 ordered items, only three operation shapes and additionalProperties false.
  - Preserve original arguments for coordinator binding; normalize only collision mapping. Produce indexed input diagnostics before any executor/receipt call. Domain value lists are descriptive strings without enum/const constraints.
  - Use batch-local descriptors consumed in final common tool registration; never add mutate_tasks to protected/revision tool sets or create an outer durable key.
  - Blocked-by: eptphz6 (RED: Specify whole-request parser and nested operation schema boundaries)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [4.1](requirements.md#4.1), [6.2](requirements.md#6.2)
  - References: Transit/Transit/MCP/BatchWrites/, design.md

- [x] 7. RED: Specify pure normalization and all-item saved preview parity <!-- id:eptphz8 -->
  - Create MCPBatchTaskPreviewTests.swift; extend CommentServiceTests and existing MCPCommentTests/TaskUpdateValidator coverage. Check description trim/empty-clear, name/metadata/milestone precedence, author/content trimming, same-status no-op, blank comment and conditional author errors against actual protected operations.
  - All-item preview mixes valid/invalid/unavailable without stopping; missing/ambiguous UUID, failed task/comment fetch, stale revision and persistence fallback remain distinct. Snapshot includes comment-covered r1 before comment projection; no hash from visible fields.
  - Spy forbids constructing mutation Comment models, allocating new effect UUIDs/display IDs, generating proposed commit timestamps, assignments and saves/rollback/receipt/cleanup/recovery; parsing existing UUIDs and formatting saved dates/revisions remain allowed; return saved_local_store, keyState unchecked/advisory, proposed symbolic effects only. Reuse early pending-state fixtures, verify later independently saved revision invalidates preview.
  - Blocked-by: eptphz7 (GREEN: Implement bounded request parser and schema descriptor), eptphz3 (GREEN: Implement private saved-read context and optional batch execution policy)
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [5.1](requirements.md#5.1), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.2](requirements.md#6.2), [6.4](requirements.md#6.4)
  - References: Transit/TransitTests/MCPBatchTaskPreviewTests.swift, Transit/TransitTests/MCPCommentTests.swift, Transit/Transit/Intents/TaskUpdateValidator.swift, design.md

- [x] 8. GREEN: Implement pure operation helpers and saved-only preview handler <!-- id:eptphz9 -->
  - Create Services/CommentInputValidation.swift shared cross-platform pure normalizer; CommentService retains mutation/save/errors, including UI/intent/maintenance callers. MCP-specific status/author validation stays MCP/BatchWrites/MCPTaskMutationValidation.swift and MCPWriteCommand consumes pure parity helper.
  - Create MCPBatchTaskPreview using private saved-read factory and read-only validator services. Require exactly one UUID result, pure TaskUpdateValidator.validate, full authoritative snapshot then projection. No apply/addComment/updateStatus, no model returned across actor boundary.
  - Wire request parser and preview into feature-local handler with aggregate preview validity/errors. Preserve standalone service/intent behavior and existing status timestamp semantics; no freshness/deadline/cursor claim.
  - Blocked-by: eptphz8 (RED: Specify pure normalization and all-item saved preview parity)
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [5.1](requirements.md#5.1), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.2](requirements.md#6.2), [6.4](requirements.md#6.4)
  - References: Transit/Transit/Services/CommentInputValidation.swift, Transit/Transit/Services/CommentService.swift, Transit/Transit/MCP/Writes/MCPWriteCommand.swift, Transit/Transit/MCP/BatchWrites/, design.md

- [x] 9. RED: Specify ordered per-item durability, retries and cancellation <!-- id:eptphza -->
  - Create MCPBatchTaskCoordinatorTests.swift with injected executor and seeded generated outcome/cancellation sequences. Calls form prefix ending at first noncommit/unreadable/pending stop; one normal result per index, blocker optional before-first/between-items, exact summary precedence after last commit and unsuccessful result plus cancellation.
  - Exercise real app-owned coordinator fixtures: canonical description then distinct status+reason items, stale/ambiguous target, references/comment fetch failure, atomic reason comment, shared key concurrent submissions, regrouped/direct-tool identical args, changed payload rejection, restart/later edit/deletion replay.
  - Cover retained rejection correction versus transient retry, unresolved original-key retry, response loss with unknown expiry/receipt removal and expired key may execute anew, store scope limitations, historical canonical replay does not certify current contents. No automatic key rotation/compensation/detached continuation.
  - Blocked-by: eptphz9 (GREEN: Implement pure operation helpers and saved-only preview handler), eptphz5 (GREEN: Implement batch evidence classifier and ready fallback adapter)
  - Stream: 1
  - Requirements: [1.5](requirements.md#1.5), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3)
  - References: Transit/TransitTests/MCPBatchTaskCoordinatorTests.swift, Transit/TransitTests/MCPWriteCoordinatorTests.swift, design.md

- [x] 10. GREEN: Implement ordered coordinator using original protected commands <!-- id:eptphzb -->
  - Create MCPBatchTaskCoordinator: full shape validation, prepared fallback prerequisite, observed cancellation checks, existing app-owned coordinator once per item with exact original args/optional batch policy. No live preflight ahead of receipt replay and no receipt-blind outer dirty block.
  - Capture immutable original evidence immediately, classify before advancement, preserve commits independently. Represent stop reason/nextUnstartedIndex/optional blocker and not_attempted mappings; noncommitted evidence wins cancellation diagnostic, all_committed survives after-last cancellation.
  - Wire preview/execute mode selection into local handler. No outer durable store, whole-batch transaction, automatic retries or T2381 logic. Existing T2380 recovery remains authority in clean contexts.
  - Blocked-by: eptphza (RED: Specify ordered per-item durability, retries and cancellation)
  - Stream: 1
  - Requirements: [1.5](requirements.md#1.5), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3)
  - References: Transit/Transit/MCP/BatchWrites/, design.md

- [x] 11. RED: Specify logical aggregate, error flags and modern adapter parity <!-- id:eptphzc -->
  - Extend MCPBatchTaskEncodingTests with actual loop output: normal itemId/index/tool/key/task mapping, each complete originalResult/raw text/optional flag, absent/null/unknown fields and receipt completion/expiry unchanged. Aggregate isError independent from nested isError and source categories/retryAction.
  - Assert same logical semantic batch JSON in text and structured source under approved collision-free wrapper; arbitrary historical field collisions remain nested. Not_attempted has no new accepted/record/receipt/expiry claims. Shape error versus item domain error stays distinct.
  - Inject final encoding/delivery loss after real committed item, verify ready serialization_failed fallback original recovery identifiers without no-effect/fresh-key claims and durable receipts survive. HTTP cancellation may suppress delivery, not undo effects.
  - Blocked-by: eptphzb (GREEN: Implement ordered coordinator using original protected commands)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: Transit/TransitTests/MCPBatchTaskEncodingTests.swift, design.md

- [x] 12. GREEN: Wire aggregate source adaptation and encoding-free response selection <!-- id:eptphzd -->
  - Implement batch logical aggregate/output schema in feature-local result component, using preserved immutable item sources and batch-local diagnostics. Compatible JSON text uses same data; modern common encoder wraps source once.
  - Integrate normal response encoding with prepared fallback selection at agreed T2383/T63 response boundary, retaining request correlation and cancellation ownership. Unsupported/unreadable evidence preserves available text/flag; no live reread/source rewrite.
  - Do not apply read admission/retention or five-second coverage to either mode. Complete fallback preparation failure remains no-effect dispatch block.
  - Blocked-by: eptphzc (RED: Specify logical aggregate, error flags and modern adapter parity)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: Transit/Transit/MCP/BatchWrites/, design.md

- [x] 13. RED: Specify real tool registration and standalone/read regression contracts <!-- id:eptphze -->
  - Extend MCPToolHandlerTests/core tools schema tests and modern server contract tests with one real mutate_tasks request. Verify deterministic tool registration, nested schemas, request-only notifications never execute, preview fallback availability and execute existing per-item write availability, no outer protected-tool reservation.
  - Run final automatic motivating consolidation fixture through real descriptor/dispatch; preview no effects then canonical description and distinct closure reasons with saved records/UUIDs, stop/retry and structured/text semantics.
  - Regression fixtures cover standalone write raw text/optional flags, status comment atomicity, CommentService/App Intent/UI/maintenance normalization, frozen cursors/snapshots and canonical omitted-comment r1. Keep modern client fixture capability-off failure explicit; tests must not toggle settings or activate real client.
  - External prerequisites: T63 coordinated shared-file handoff and T2383 delivered source/encoder/schema/provider registration seam; heavy suites wait T63 slot. T2383 common delivery/smoke is never blocked by these real batch tests.
  - Blocked-by: eptphzd (GREEN: Wire aggregate source adaptation and encoding-free response selection)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.2](requirements.md#2.2), [2.5](requirements.md#2.5), [3.3](requirements.md#3.3), [4.2](requirements.md#4.2), [5.4](requirements.md#5.4), [5.6](requirements.md#5.6), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: Transit/TransitTests/MCPToolHandlerTests.swift, Transit/TransitTests/MCPWriteContractTests.swift, Transit/TransitTests/MCPNotificationDispatchTests.swift, Transit/TransitTests/MCPTaskQuerySnapshotStoreTests.swift, Transit/TransitTests/MCPRecordRevisionTests.swift, design.md

- [x] 14. GREEN: Integrate mutate_tasks through the coordinated shared owner patch <!-- id:eptphzf -->
  - Provide one agreed integration patch to T63 (or edit only after explicit handoff) for existing MCPToolDefinitions/MCPTypes/MCPToolHandler/MCPServer/app injection. Consume delivered rich schema/immutable source/full encoder contracts; no independent shared edits or competing transport implementation.
  - Register and inject app-owned services/coordinator/container, dispatch batch before broad mutation fallback, keep outer tool outside protected/revision/covered-read sets and leave modern transport checks to T2383.
  - Make final contract/regression fixtures pass after heavy-slot release, use installed configured toolchain. Client readiness remains T2383 prerequisite; feature activation/config changes, push/merge/deploy and production guard recovery are outside task scope.
  - Blocked-by: eptphze (RED: Specify real tool registration and standalone/read regression contracts)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.2](requirements.md#2.2), [2.5](requirements.md#2.5), [3.3](requirements.md#3.3), [4.2](requirements.md#4.2), [5.4](requirements.md#5.4), [5.6](requirements.md#5.6), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: Transit/Transit/MCP/MCPToolDefinitions.swift, Transit/Transit/MCP/MCPTypes.swift, Transit/Transit/MCP/MCPToolHandler.swift, Transit/Transit/MCP/MCPServer.swift, Transit/Transit/TransitApp.swift, design.md
