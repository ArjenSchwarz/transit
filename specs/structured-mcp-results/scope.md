# T-2383: Structured MCP results — approved scope

Scope/name approved by user through parent Sentinel_efe537c782f88191b8865711b92ade59. Full Starwave workflow; feature name `structured-mcp-results`; MCP `2026-07-28` only, with no legacy protocol support. Requirements, design, tasks and implementation retain separate approval gates.

## Scope

- Document structured records/outcomes, error categories, supported link availability and saved-field normalization while preserving text payloads.
- Upgrade the protocol contract to latest stable MCP `2026-07-28`: per-request metadata/version validation, discovery, single-message HTTP, modern result/list envelopes and POST notification subscriptions.
- Preserve persisted T-2380 terminal results, frozen T-2379 pages, T-63 capture/freshness/admission/publication guarantees, and T-2382 reusable snapshot metadata and canonical comment-covered `r1`.
- Coordinate result representation with T-2384; application batch semantics stay in that ticket.

## Non-goals

Legacy initialization/session/GET transport; T-572 URL-handler/navigation implementation; T-2008/T-2129 bug implementation; App Intents redesign; portfolio/capture algorithms; receipt schema migration; remote exposure/OAuth; production implementation in this workflow.

## Evidence and ownership

Canonical `/Users/arjen/projects/personal/transit` was verified on `main`, matching `origin/main` at `201205bd4e786c7f152d8f99006b37da7da888c7`. Dedicated worktree `/Users/arjen/Documents/Codex/2026-10-03/task-3/transit`, branch `T-2383/structured-mcp-results`, uses that base; merged T-2380 is HEAD and T-2379 is its parent. Existing canonical `.kiro/` remains untouched.

Read actual local Transit/Starwave skills, `CLAUDE.md` and read-only project memories; no repository `AGENTS.md` or `.agents/skills` found. Live localhost `tools/list` and full T-2383 fetched using its actual schema. Source and running-server query surfaces differ; running app is from T-2380 worktree. Live T-572/T-2008/T-2129 are Idea; URL support is absent in current source.

T-63 remains sole writer of existing server/types/common handler/schema wiring until handoff. New serialization modules and integration patches must follow its coordinated delivery order. Approved T-63/T-2382 specs remain read-only. Modern HTTP single-message semantics replace wire-level JSON-RPC batches; preserve T-63 individual-read guarantees and do not reinterpret T-2384 tool batching as transport batching.

Per-command escalation succeeded for reads, worktree creation and phone transfer; sandbox localhost required escalation. No global permissions changed or denial bypassed. No builds/tests; T-63 owns the slot. Local spec commits only, no push/merge/deploy.

## Protocol and client readiness

Latest/current stable revision verified as `2026-07-28` from [official versioning](https://modelcontextprotocol.io/docs/2026-07-28/learn/versioning) and [stable release](https://github.com/modelcontextprotocol/modelcontextprotocol/releases/tag/2026-07-28). Latest structured content permits any JSON value; a wrapper is a contract decision. [Tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools), [version compatibility](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning), [HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http).

Installed standalone Codex CLI `0.160.0` and ChatGPT-bundled Codex CLI `0.159.2` both report `mcp_2026_07_28` disabled/under development (read-only feature listing). Modern code exists, but actual host overrides/negotiation have not been proven. Installed Claude Code `2.1.288` contains modern SDK code and its cached direct-HTTP negotiation flag is true. Official [Claude MCP runtime docs](https://code.claude.com/docs/en/mcp#mcp-client-runtimes) establish modern support with runtime/flag conditions. The user clarified that both Claude Code and Claude Desktop are required. Installed Desktop `2.19675.0` bundles modern discovery/subscription/per-request protocol code; active connector/runtime negotiation remains unverified. No client/server configuration changed. Requirements may be approved while cutover remains blocked on demonstrated client readiness; see decision log and review.
