# T-2383: Structured MCP results — scope review

Status: proposed scope/name; awaiting parent-mediated user approval. No requirements, design, tasks or implementation have been approved.

## Recommendation and gate

Use the full Starwave spec workflow. Proposed feature name: `structured-mcp-results` (user may override). The user explicitly requested full specs; this also changes a public wire contract and its relationship to persisted replay. Scope/name approval starts requirements, followed by separate requirements, design and task approvals. Implementation needs separate authorisation.

**First approval question:** Approve the full-spec path, name `structured-mcp-results`, and proposed scope below, including explicit unavailable links while T-572 remains unimplemented?

## Proposed scope

- Add documented object-valued MCP `structuredContent` for existing result-bearing tools, with identities, normalized saved values, canonical revisions where applicable, and machine-readable success/error information.
- Preserve existing text payload shapes and saved replay bytes. Array-valued legacy reads need a documented object wrapper in the structured channel; choose its shape during requirements/design rather than changing text arrays.
- Specify categories for caller errors, absent records, conflicts, retryable storage/admission failures and uncertain write outcomes. Keep existing error codes, `isError`, T-2380 `accepted`/`outcome`/`retryAction`, and JSON-RPC protocol errors meaningful. Unknown failures must not acquire a guessed retry guarantee.
- Define complete/failed read and mutation-result semantics. A failed required read must not imply an empty collection. Distinguish explicit selector-level missing outcomes from whole-read failure; do not invent partial success after a committed write or safe fresh-key retry for uncertainty.
- Document actual field normalization and equality with saved readback. Preserve exact content covered by revisions rather than introducing a new trimming pass.
- Define task/project link availability explicitly. Publish URLs only when backed by a supported entity-opening scheme. With current support absent, recommend an explicit unavailable result; T-572 owns the navigation feature. A proposed `transit://` string is not a supported link.
- Resolve MCP protocol compatibility: code currently negotiates at most `2025-03-26`; official `2025-06-18` defines object-valued structured results/output schemas. Requirements/design must decide negotiation and old-client behavior before schema wiring.

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
