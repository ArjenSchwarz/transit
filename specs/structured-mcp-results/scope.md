# T-2383: Structured MCP results — scope review

Status: original scope direction accepted subject to the requested protocol assessment (parent Sentinel_4fd40b3fecf48191a57ce03897d3e7ec); revised protocol scope/name confirmation pending. No requirements, design, tasks or implementation have been approved.

## Recommendation and gate

Use the full Starwave spec workflow. Proposed feature name: `structured-mcp-results` (user may override). The user explicitly requested full specs; this also changes a public wire contract and its relationship to persisted replay. Scope/name approval starts requirements, followed by separate requirements, design and task approvals. Implementation needs separate authorisation.

**Remaining approval question (through parent):** Approve `structured-mcp-results` with latest stable `2026-07-28` support plus a legacy `2025-03-26` compatibility path, including the transport changes below; or select the smaller interim `2025-11-25` scope? Explicit unavailable links remain recommended while T-572 is unimplemented.

## Proposed scope

- Add documented MCP `structuredContent` for existing result-bearing tools, with identities, normalized saved values, canonical revisions where applicable, and machine-readable success/error information.
- Preserve existing text payload shapes and saved replay bytes. Latest MCP allows array-valued structured reads; object wrappers are a contract choice, not a latest-version requirement. Choose the shape and old-client presentation during requirements/design.
- Specify categories for caller errors, absent records, conflicts, retryable storage/admission failures and uncertain write outcomes. Keep existing error codes, `isError`, T-2380 `accepted`/`outcome`/`retryAction`, and JSON-RPC protocol errors meaningful. Unknown failures must not acquire a guessed retry guarantee.
- Define complete/failed read and mutation-result semantics. A failed required read must not imply an empty collection. Distinguish explicit selector-level missing outcomes from whole-read failure; do not invent partial success after a committed write or safe fresh-key retry for uncertainty.
- Document actual field normalization and equality with saved readback. Preserve exact content covered by revisions rather than introducing a new trimming pass.
- Define task/project link availability explicitly. Publish URLs only when backed by a supported entity-opening scheme. With current support absent, recommend an explicit unavailable result; T-572 owns the navigation feature. A proposed `transit://` string is not a supported link.
- Target latest stable `2026-07-28` with legacy compatibility if the revised scope is approved. Review version-aware transport/result presentation and schema wiring with T-63 before production edits.

## Latest MCP assessment (2026-10-03)

The official versioning page marks `2026-07-28` Current, and the GitHub release calls it stable. It supersedes `2025-11-25`; the user's July date is correct. The earlier `2025-06-18` citation establishes structured-result history, not the recommended latest version. [Versioning](https://modelcontextprotocol.io/docs/2026-07-28/learn/versioning), [stable release](https://github.com/modelcontextprotocol/modelcontextprotocol/releases/tag/2026-07-28).

**Recommendation:** design for latest stable with dual-era compatibility, contingent on approval of the additional transport work. Avoid advertising latest support by changing the initialization constant alone. If this ticket must stay focused on serialization, use `2025-11-25` as an interim structured-result revision and defer the modern transport migration explicitly. It is still a compatibility change, not a free constant update.

| Contract | Latest standard | Concrete repository consequence |
| --- | --- | --- |
| Version selection | Every modern request declares version/capabilities in `params._meta`; `server/discover` is mandatory; unsupported versions report supported versions. No modern initialization handshake. | Replace the single-version assumption in `MCPToolHandler.handleInitialize` with era-aware dispatch. Keep legacy initialization for existing clients; inspect modern metadata before mutation or store admission. Add discovery and version-error tests. |
| Legacy interoperation | Dual-era servers may serve both paths. Legacy clients cannot fall forward to modern-only servers. | Recommend preserving `2025-03-26` handshake/text behavior. Store legacy negotiated state separately from per-request modern metadata; select behavior before dispatch. Prove that malformed modern requests cannot silently execute through a permissive legacy route. |
| HTTP | Modern requests use matching protocol/method/name headers and single-message POSTs. Invalid required headers are rejected; GET and protocol sessions are removed. | `MCPServer.makeRouter` currently accepts POST without version headers, accepts JSON-RPC arrays and emits session IDs on initialization. Add era-aware validation before dispatch. Retain array handling only for legacy compatibility; modern requests must not enter legacy batch assembly. T-2384 application batching is one tool call and remains valid. |
| Notifications | Modern long-lived change listening is `subscriptions/listen` POST; legacy GET/session listening is separate. | Adapt `MCPServer+ToolListNotifications`, handler/settings notification registration and disconnect/lifecycle cleanup. Retain legacy tool-list-change streams. Preserve T-63 generation invalidation and physical-read accounting through either path. |
| Result presentation | Modern ordinary results carry `resultType:complete`; list results add caching fields. | Add version-aware common result/list/discovery envelopes. Pick conservative list cache policy and verify maintenance toggle changes still reach both subscription types. Do not confuse protocol cache hints with T-63 capture freshness or snapshot expiry. |
| Structured data | Latest allows any JSON value; supplied output schemas must match structured results. Text JSON compatibility is recommended. | Existing array text can have an array structured counterpart on latest. Interim `2025-11-25` uses an object-valued result; avoiding two public payload shapes may justify a shared wrapper, but that is a user/design decision. Existing `JSONSchema` and `MCPToolDefinition` lack output-schema support. Use only schema constructs needed by these tools; no generic schema engine requirement is implied. |
| Security | Origin validation remains required; localhost binding and authentication are recommended. | Current source already binds `127.0.0.1` and validates Origin/Host before body access. Preserve this. Current local unauthenticated deployment requires an explicit assessment in design; do not silently introduce OAuth, remote listening or new credentials as part of a version update. |
| Lost responses | Latest transport does not use SSE event-ID redelivery. | T-2380 idempotency keys and saved outcomes remain application recovery evidence; new JSON-RPC IDs do not mean new write keys. T-2384 item keys recover committed results when aggregate delivery/encoding fails. |

Sources for the table: [version compatibility](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning), [HTTP binding](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http), [tools and structured content](https://modelcontextprotocol.io/specification/2026-07-28/server/tools), [release changes](https://modelcontextprotocol.io/specification/2026-07-28/changelog), [interim HTTP contract](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).

Planning impact: serialization can be isolated, but latest-version transport and notification migration cannot run concurrently as another writer of T-63's existing common files. Specify integration interfaces and delivery order with T-63, retaining its sole-writer rule. Both modern and legacy encoders must honor read deadline/atomic-publication constraints; do not add a second post-publication encoding pass. Frozen captures must survive era-specific presentation without changing revisions or saved text. A response's full encoded size, including structured duplication and modern metadata, must enter the agreed retention/deadline accounting.

T-2384 coordination received: ordered per-item outcomes with nested original T-2380 result, no new durable batch-key namespace, and aggregate failure after commits must never imply no effect. This is compatible with a proposed immutable JSON-value/preserved-text adapter. Preserve `accepted`, `outcome`, `retryAction`, `isError` and historic absent/null distinctions. Category mapping must not override the source retry direction. These are coordination constraints, not an approved new batch requirement here.

No upgrade or requirements generation occurred during this assessment. Await revised scope/name confirmation before moving T-2383 to Spec. Requirements, design and tasks retain their independent approval gates.

## Exclusions

App Intents result redesign; T-572 URL registration/navigation implementation; batch mutations or dry runs (T-2384); T-2008/T-2129 bug implementation; capture/freshness/deadline algorithms; portfolio aggregation; receipt schema migration; changes to canonical revision coverage; push, merge, deployment or external review disclosure.

## Evidence and coordination

| Area | Observed contract / proposed planning constraint |
| --- | --- |
| Base | Canonical `/Users/arjen/projects/personal/transit` is on `main`; local `main`, `origin/main` and new worktree base all equal `201205bd4e786c7f152d8f99006b37da7da888c7`. T-2380 merge is HEAD; T-2379 merge `0db453b` is its parent. The supplied T-2380 commit is an ancestor of the worktree. |
| Isolation | Worktree `/Users/arjen/Documents/Codex/2026-10-03/task-3/transit`, branch `T-2383/structured-mcp-results`. Existing untracked canonical `.kiro/` remains untouched. |
| Running server | Read actual localhost `tools/list`, then full T-2383 through its actual `query_tasks {displayId}` schema. Live results are text-only; schema lacks current main's bounded-query arguments. Do not confuse installed server behavior with current source contracts. |
| T-2380 | `MCPWriteCoordinator.stageTerminal` saves `resultJSON` and `resultIsError`; replay returns saved JSON without fetching the current record. Structured presentation must derive from saved terminal evidence, including historic receipts, rather than live rereads. Replay after edits/deletion must remain stable; contract-version/upgrade behavior needs a design decision. |
| T-2379 | Query pages are encoded once and retained in `MCPTaskQuerySnapshotStore`; cursor continuation returns the saved page. Freeze structured data, text and revision identity together; never recompute a continuation from live models. |
| T-63 | Sole writer of `MCPServer`, `MCPTypes`, common handler dispatch and schema wiring. Its approved design freezes capture evidence, adds outer `_meta`, and selects complete encoded bytes plus publications before deadline. Propose an independently testable result-serialization module and a small integration patch delivered to T-63 after interface agreement. No shared-file edits before handoff. Additional serialization cost and retention charges need explicit integration tests in the eventual plan. |
| T-2382 | Owns portfolio/snapshot projection modules and reusable encoded views. Structured results must preserve captured metadata, frozen cursors and canonical comment-covered `r1` even when comment bodies are omitted. Both ordinary and reusable read serialization need the same agreed adapter boundary. Approved spec files remain read-only. |
| T-2384 | Live feature ticket is Idea. Reuse T-2380 operation outcomes and record representation; plan a result-value interface usable by forthcoming per-item outcomes without implementing batch/dry-run semantics here. |
| T-572 | Live feature ticket is Idea, proposes an undecided task URL scheme. No `onOpenURL`, `CFBundleURL` or `transit://` support found in current Transit sources. Project navigation links have no established support either. |
| T-2008 / T-2129 | Both live bug tickets remain Idea. Their descriptions refer to older paths. Current T-2380 docs already require full-query comment fetch failure to abort and status-comment evidence to be saved atomically. Audit current paths before claiming remaining bug coverage; keep separate tickets separate. |

## Workflow and capability

Read actual local Transit, creating-spec, requirements, design and tasks skills; repository `CLAUDE.md`; read-only project memories. No repository `AGENTS.md` or `.agents/skills` was found. Local peer-review-validator documentation supplies an internal two-perspective fallback. Use design-critic followed by internal peer validation in later phases; no external-model disclosure is authorised. No peer review has run at this scope gate.

Per-command `require_escalated` succeeded for a read probe, isolated worktree creation and localhost reads. Sandboxed localhost access failed to connect; the escalated read succeeded. No global permissions were changed and no approval denial was bypassed. No builds/tests ran; T-63 owns that slot. Scope approval is required before changing ticket status from Idea to Spec.

## Sources

- `CLAUDE.md`, `docs/mcp-write-contract.md`, `Transit/Transit/MCP/MCPTypes.swift`, `MCPToolHandler.swift`, `MCPToolHandler+TaskQuery.swift`, `MCPTaskQuerySnapshotStore.swift`, `Writes/MCPWriteCoordinator.swift`.
- Read-only approved specs: `/Users/arjen/Documents/Codex/2026-10-03/task/transit-t63/specs/bounded-read-freshness` and `/Users/arjen/Documents/Codex/2026-10-03/task-2/transit/specs/portfolio-summaries`.
- [MCP 2025-06-18 tool results](https://modelcontextprotocol.io/specification/2025-06-18/server/tools#structured-content): structured content is an object; text compatibility is recommended. [Earlier tool specification](https://modelcontextprotocol.io/specification/2025-03-26/server/tools).
