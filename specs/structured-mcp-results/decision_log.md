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

## ADR 1: Latest-only MCP protocol

**Status:** approved scope decision, 2026-10-03.

**Context:** current source supports `2025-03-26`; structured results require a reviewed protocol change. Latest official stable/current revision is `2026-07-28`, which changes transport/lifecycle substantially. Alternatives were latest with legacy compatibility and interim `2025-11-25`.

**Decision:** target `2026-07-28` only. User declined legacy support because Transit is used by Codex and Claude, and otherwise approved the expanded scope (parent Sentinel_efe537c782f88191b8865711b92ade59). Do not serve old initialization/session/GET or JSON-RPC array batches through a permissive compatibility path.

**Consequences:** modern metadata/header validation, discovery, POST subscription stream and result/cache envelopes need coordinated design with T-63. Application idempotency/snapshots remain server-minted explicit handles. Existing text JSON payloads and saved records survive protocol migration. Implementation and cutover need proof that the actual clients can use modern-only Transit; old-protocol clients receive actionable rejection.

**Client evidence and blocker:** standalone Codex `0.160.0`, bundled `0.159.2`, both read-only feature lists report `mcp_2026_07_28` false. The [exact 0.160.0 protocol-mode source](https://raw.githubusercontent.com/openai/codex/rust-v0.160.0/codex-rs/rmcp-client/src/protocol_mode.rs) includes modern lifecycle but defaults to Legacy. Binary marker inspection confirms modern methods, not enabled negotiation. [Official OpenAI MCP docs](https://learn.chatgpt.com/docs/extend/mcp?surface=cli) establish HTTP support but do not document latest-version activation. Actual desktop host overrides are unverified. Claude Code `2.1.288` has SDK2 modern symbols; cached `tengu_mcp_protocol_negotiation_http` is true, with no environment/settings override observed for MCP_SDK_GENERATION or MCP_PROTOCOL_NEGOTIATION. [Official Claude runtime docs](https://code.claude.com/docs/en/mcp#mcp-client-runtimes) describe conditional runtime selection and feature flags; this supports readiness but does not prove an active modern-only connection. Claude Desktop remains unverified. No configs/server modified. Existing successful tool calls against legacy Transit prove only old-server connectivity.

**Verification path:** design/task plan must validate actual Codex/Claude surfaces against an isolated modern protocol fixture before enabling a production migration. If modern mode is disabled/unavailable, stop at the migration gate and report required approved client activation/upgrade; do not add legacy support or change client settings silently. This is a prerequisite, not permission to run an external-model agent.
