# Structured MCP results: decision log

## Quick decisions

| ID | Date | Decision | Evidence / reason |
| --- | --- | --- | --- |
| Q1 | 2026-10-03 | Full spec; name `structured-mcp-results`. | User explicitly approved scope/name through parent Sentinel_efe537c782f88191b8865711b92ade59; public result contract and persisted replay warrant full workflow. |
| Q2 | 2026-10-03 | Explicit unavailable task/project links until supported navigation exists; T-572 implementation stays separate. | Live T-572 is Idea, scheme undecided; no URL registration/open handler in current source. |
| Q3 | 2026-10-03 | T-63 owns existing common files; coordinate serialization adapter and transport handoff. | User's parallel coordination instruction; approved read deadlines/publication must survive migration. |
| Q4 | 2026-10-03 | Use internal design critic followed by two independent internal peer perspectives. | External disclosure is not authorised; local peer-review-validator supplies two-peer fallback. No external AI service will receive repository/spec data. |
| Q5 | 2026-10-03 | Preserve historic T-2380 JSON/text/isError as outcome evidence; common result additions are presentation, not receipt rewrite. | Coordinator replay reads saved resultJSON/resultIsError; T-2384 requirements 4.3,5.2–5.4 align on missing/null, unknown fields, revision/retryAction and no-effect distinctions. |
| Q6 | 2026-10-03 | Move T-2383 Idea → Spec after scope approval. | Committed live update key `T2383.scope-approved.spec.20261003`, comment records approval and remaining gates. |
| Q7 | 2026-10-03 | Preserve subscription opt-in while requiring installed-client tool readiness and a conforming subscription test. | Internal API peer distinguished optional client participation from server subscription conformance; avoids blocking usable tool clients on an unrequested filter. |
| Q8 | 2026-10-03 | Request-only methods never execute notification-shaped requests. | Correctness peer identified legacy handler mutation notification dispatch; modern transport must reject that shape without effects. |
| Q9 | 2026-10-03 | Historical variants must conform to advertised output schemas; supplement names cannot overwrite source fields. | Critic and both peer perspectives confirmed preservation alone is insufficient if schema validation rejects original fields. |
| Q10 | 2026-10-03 | Both Claude Code and Claude Desktop are required readiness surfaces, alongside actual intended Codex surfaces. | User clarification “Both” through parent Sentinel_e3dcebb74f288191a3d42559f563ab5c. This clarifies 6.3, does not approve all requirements or settings changes. |

## ADR 1: Latest-only MCP protocol

**Status:** approved scope decision, 2026-10-03.

**Context:** current source supports `2025-03-26`; structured results require a reviewed protocol change. Latest official stable/current revision is `2026-07-28`, which changes transport/lifecycle substantially. Alternatives were latest with legacy compatibility and interim `2025-11-25`.

**Decision:** target `2026-07-28` only. User declined legacy support because Transit is used by Codex and Claude, and otherwise approved the expanded scope (parent Sentinel_efe537c782f88191b8865711b92ade59). Do not serve old initialization/session/GET or JSON-RPC array batches through a permissive compatibility path.

**Consequences:** modern metadata/header validation, discovery, POST subscription stream and result/cache envelopes need coordinated design with T-63. Application idempotency/snapshots remain server-minted explicit handles. Existing text JSON payloads and saved records survive protocol migration. Implementation and cutover need proof that the actual clients can use modern-only Transit; old-protocol clients receive actionable rejection.

**Client evidence and blocker:** standalone Codex `0.160.0`, bundled `0.159.2`, both read-only feature lists report `mcp_2026_07_28` false. The [exact 0.160.0 protocol-mode source](https://raw.githubusercontent.com/openai/codex/rust-v0.160.0/codex-rs/rmcp-client/src/protocol_mode.rs) includes modern lifecycle but defaults to Legacy. Binary marker inspection confirms modern methods, not enabled negotiation. [Official OpenAI MCP docs](https://learn.chatgpt.com/docs/extend/mcp?surface=cli) establish HTTP support but do not document latest-version activation. Actual desktop host overrides are unverified. Claude Code `2.1.288` has SDK2 modern symbols; cached `tengu_mcp_protocol_negotiation_http` is true, with no environment/settings override observed for MCP_SDK_GENERATION or MCP_PROTOCOL_NEGOTIATION. [Official Claude runtime docs](https://code.claude.com/docs/en/mcp#mcp-client-runtimes) describe conditional runtime selection and feature flags; this supports readiness but does not prove an active modern-only connection. Claude Desktop `2.19675.0` was inspected read-only: its `app.asar` has modern `2026-07-28` version selection, `server/discover`, `subscriptions/listen` and per-request metadata in the bundled `.vite/build/mcp-runtime/directMcpHost.js`/main SDK code. This is installed implementation evidence, not proof its active runtime/Transit connector chooses modern mode. The conventional Desktop config and MCP log show no identifiable Transit negotiation; alternate connector routes were not inferred. Official [Desktop local MCP guide](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop) establishes local MCP support but does not state the protocol revision. Both Code and Desktop remain live-negotiation verification prerequisites. No configs/server modified. Existing successful tool calls against legacy Transit prove only old-server connectivity.

**Verification path:** design/task plan must validate actual Codex/Claude surfaces against an isolated modern protocol fixture before enabling a production migration. If modern mode is disabled/unavailable, stop at the migration gate and report required approved client activation/upgrade; do not add legacy support or change client settings silently. This is a prerequisite, not permission to run an external-model agent.

## Quick decisions: design

| ID | Date | Decision | Evidence / reason |
| --- | --- | --- | --- |
| Q11 | 2026-10-03 | Requirements approved; proceed design only. | Parent verified owner message 2026-10-03T09:51:37.926279Z Sentinel_39b0ca45b1b8819180ac6d9600578f0b, “Structured MCP results requirements also approved”. |
| Q12 | 2026-10-03 | ttlMs zero/public for discovery and tool lists; deterministic name order. | Definitions depend on local availability; no personalised responses, no stale settings cache required. |
| Q13 | 2026-10-03 | Unavailable UUID-and-source-pointer link sidecar; explicit tool selector tables. | Avoid guessing IDs in unknown historical fields and preserve replay determinism. |
| Q14 | 2026-10-03 | Generated plain error text and malformed retained JSON have separate declared origins. | JSON parse failure alone cannot establish that saved evidence is an ordinary message. |
| Q15 | 2026-10-03 | Effectful maintenance prepares no-key uncertainty fallback and reconciles with scan/inspection. | Internal design critic identified post-save serialization gap in reassign_duplicate_display_ids; AC3.4 applies beyond protected writes. |
| Q16 | 2026-10-03 | Generated JSON parse failure throws; malformed retained evidence preserves text/unestablished. | Correctness peer separated capture serialization failure from historical evidence presentation. |
| Q17 | 2026-10-03 | Maintenance provider encoding failures propagate may-have-effects evidence to prepared fallback selection. | Existing inner errorResult catch could otherwise bypass the complete uncertainty fallback. |

## ADR 2: Immutable source and separate presentation envelope

**Status:** approved in T2383 design 7970a9c by Sentinel_717be95229c48191a7c41b6e5e467e4c.

**Context:** historic JSON may contain arbitrary unknown field names. Flattening category/links into that object would either overwrite saved evidence or silently change the supplemental contract. Reads also use arrays and scalar JSON values. T2384 needs nested original JSON/text/optional isError independent of aggregate diagnostics.

**Decision:** common structured contract version1 uses source.kind/payload and a separate presentation containing evidence, links, category and recovery. Text and optional isError are retained independently. A lossless immutable JSON document validates/inserts the whole original JSON fragment without a Double roundtrip; presentation never rewrites the original payload.

**Consequences:** consumers follow source.payload rather than consuming a flat structured record. Common schema constrains wrapper/source variants but intentionally permits any original JSON value/unknown historic fields. Current tool shapes are documented separately. Raw fragment insertion requires a validated complete document and targeted parser/encoder property checks. This adds parser work but avoids lossy generic AnyCodable conversion across actor boundaries. No receipt format migration or alternate canonicalizer is introduced.

**Alternatives:** flat original JSON plus reserved fields cannot satisfy collision safety; metadata-only supplements separate fields but do not supply a self-contained versioned structured contract. Re-encoding Foundation numeric values risks changing unknown historical numbers. A new persisted presentation receipt would change storage/replay semantics and create migration work outside scope.

## ADR 3: Complete response preparation before publication or write effects

**Status:** approved in T2383 design 7970a9c by Sentinel_717be95229c48191a7c41b6e5e467e4c.

**Context:** T63 can publish retained views only with a winning complete response; T2380/T2384 can commit before a response encoder fails. Calling a generic encoder again while handling its failure can hide the outcome or lose request correlation.

**Decision:** covered reads finish all text/structured/meta/modern envelope bytes before the existing atomic publication gate. Protected single/batch writes prepare a complete compact modern uncertainty/reconcile response before effects, correlated to the RPC ID and original keys, then select those ready bytes on post-effect encoding failure without invoking the failed encoder again. Fallback preparation failure blocks dispatch. Cancellation suppresses delivery but never rewrites commitment evidence.

**Consequences:** expanded retained fragments count toward existing store budgets; unsafe generic response fallbacks are excluded from may-commit paths. The common encoder offers complete-byte preparation; T2384 supplies its compact aggregate and preserves per-item effects/keys. Read physical finalizers and write durable transactions remain owned by their approved components.

## Quick decisions: task planning

| ID | Date | Decision | Evidence / reason |
| --- | --- | --- | --- |
| Q18 | 2026-10-03 | Design approved; proceed Rune task planning only. | Owner “2383 and 2384 are approved”, parent-verified Sentinel_717be95229c48191a7c41b6e5e467e4c; T2383 7970a9c, T2384 a5950e99. |
| Q19 | 2026-10-03 | Deliver synthetic-provider-tested common API before real T2384 integration. | T2384 accepts noncircular T63 handoff → common seam → batch consumer sequence; T2383 has no production batch dependency. |
| Q20 | 2026-10-03 | Keep caller-doc deliverables outside coding-only Rune tasks, with T2383 owner and final completion gate. | Task critic found schema fixtures alone do not discharge promised docs; task-review tracks exact documents/commits after15 without blocking common API delivery. |
| Q21 | 2026-10-03 | Interface1 must compile so RED fixtures fail behavior. | API task peer clarification; no task/DAG/scope change. |
| Q22 | 2026-10-03 | Task plan b58298a and implementation approved. | Parent-verified owner “Approved”, Sentinel_ba4c6123288881918042d6aeb8ba6dc5; start independent make-it-so DAG, shared ownership/test-slot gates remain. |
| Q23 | 2026-10-03 | T2384 owns write coordinator/coordinator-specific tests; defer those edits to coordinated owner. | Direct coordination confirms parent ownership grant. T2383 common result consumers remain independent; no second acceptance/recovery engine. |


### Implementation sequencing correction: protocol parser dependency

Parent confirmed task13/gpzncvx additionally depends on delivered parser3/gpzncvn. Compiler-valid declaration task1 makes protocol RED drafting parallel, but successful protocol validation must return owned lossless MCPJSONDocument and discovery must consume validated schema fragments. GREEN13 cannot pass honestly against parser placeholders; the added Rune edge prevents a duplicate parser or fabricated success. Scope/task count remain unchanged. Source3 passes and integrates before protocol GREEN13; exact shared test slots remain separately gated.
