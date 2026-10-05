# T-2384 — Batch task mutations: scope review

Status: scope/name approved in parent at `Sentinel_4fd40b3fecf48191a57ce03897d3e7ec`. Requirements/design/tasks remain separate gates; no implementation is authorised. The original proposals below inform the requirements review.

## Verified starting point

- Canonical repository: `/Users/arjen/projects/personal/transit`.
- Canonical `main`, `origin/main`, and `HEAD` all resolved to `201205bd4e786c7f152d8f99006b37da7da888c7` immediately before worktree creation on 2026-10-03. This is merged T2380 (#249), following T2379 (#248).
- Dedicated branch: `T-2384/batch-task-mutations`; worktree: `/Users/arjen/Documents/Codex/2026-10-03/task-4/transit`. Its HEAD and merge bases with both main refs equal that SHA.
- Existing canonical untracked `.kiro/` and every other worktree were preserved.
- A read-only `require_escalated` probe and escalated `git worktree add` both succeeded under per-command auto-review. No global permission changes were requested.
- Live running `query_tasks` schema was inspected, then full T2384 and T2383 records were fetched. T2384 is a medium-priority feature in Idea, revision `r1:a4e89fd41bf00148d8efd03906ea61abcdb86060848ce75011c08efc1cf92a07`.

## Workflow and feature name

Recommend the **full Starwave spec process**, named **`batch-task-mutations`**. The public mutation contract, partial failure behavior, and replay semantics are expensive to reverse; atomic versus per-item application also presents a real user-owned decision. The requested substantive full-spec process independently requires this route.

The local Transit router and Starwave creating-spec, requirements, design, and tasks instructions were read. Repository `CLAUDE.md`, `.claude/rules`, merged write-safety specs/source, and the approved T63/T2382 designs were inspected. No repository `AGENTS.md` or `.agents/skills` directory was present. Local Transit memory was read without changes.

Gate sequence: scope/name approval → requirements and clarifications → requirements review/approval → design, ADRs and review/approval → Rune task plan and review/approval. Implementation remains a separate authorisation. Creating the isolated spec branch early follows the explicit delegation; it is not approval of scope or implementation.

Formal requirements/design reviews will use the documented internal peer fallback: design critic followed by at least two independent peer lenses. External model disclosure is not authorised by this delegation. No peer review has yet been claimed or performed for this scope gate.

## Recommended product scope

Provide one bounded **domain tool** for explicit task property updates, task status changes (including their existing atomic reason/comment), and standalone comments. A domain batch is a single `tools/call` carrying item operations; it is separate from an HTTP JSON-RPC array of independent requests. Existing transport batching keeps its current ordering and error behavior, and gains no transaction promise from this tool.

The motivating flow updates a caller-selected canonical task, closes caller-selected duplicate tasks with reasons, and returns saved records/outcomes in input order for verification. Matching duplicates, choosing the canonical task, duplicate links, and consolidation policy remain with the caller; T2381 is not a dependency. Task creation, project/milestone mutations, automatic compensation, and cloud-wide transactions are outside the initial proposal.

Recommend **ordered per-item commits**, rather than a whole-batch transaction. Each submitted effect uses the existing T2380 protected tool, explicit caller item key, and expected revision where that tool requires one. A status change plus its reason/comment retains the existing single-item atomic boundary. Earlier committed items remain committed if a later item fails. This reuses authoritative acceptance, durable receipts, payload binding, recovery classification, and seven-day completed-result retention; unresolved bindings do not expire under that policy.

Recommended execution policy: validate the complete outer shape before any execution; execute in caller order; stop after the first rejection, in-progress, or uncertain result; return explicit not-attempted outcomes for the remainder. This reduces the risk of closing duplicates after their canonical update failed. No rollback of earlier successes is promised. An alternative continue-on-conclusive-rejection policy can be discussed at the requirements gate.

Recommend a small explicit item bound (initial candidate: 50, to confirm in requirements), unique client item IDs, and explicit item idempotency keys matching T2380. The outer batch correlation ID is not a new durable idempotency namespace and must not imply whole-response replay. Replaying a batch recovers each retained item independently; changing item arguments under an existing key fails under T2380's binding rules. Missing responses, interrupted iteration, expired receipts, and ambiguous store scope require documented reconciliation, not fresh-key resubmission.

Recommend initially rejecting repeated resolved task identities in a batch. Same-task workflows use the existing status-plus-comment operation where possible or a later submission with the resulting revision. This avoids inventing revision chaining between items during the first version. If combined property/status/comment edits on one task are required in one submission, they need an explicitly approved item contract rather than reusing a stale pre-batch revision for multiple writes.

## Preview, outcome, and retry contracts to settle

A dry run performs no domain mutations, display-ID allocation, receipt/guard reservation, cleanup, recovery, or baseline save of pending edits. It validates supported input, resolved identities/references, current revisions, and observable domain constraints, returning proposed normalized effects and per-item diagnostics. It is advisory: a later submit revalidates against current state and cannot treat preview success as a reservation. Domain failure or unavailable storage is an explicit diagnostic, never an empty success.

Submission outcomes preserve T2380 distinctions: committed, rejected, in_progress, uncertain, plus batch-local not_attempted. Every item retains client mapping, tool/key, resolved identity when known, accepted state, machine-readable error/retry direction, and saved record/revision when committed. A rejected item can already have a retained accepted receipt; accepted is not synonymous with committed. Uncertain items must not invite a new key. Saved receipt records represent that item's commit and can differ from a later live readback.

A lost outer response is not evidence of no effects. Retry the identical retained item requests in the originating store while their guarantees apply; stop/reconcile unresolved outcomes. No automatic replay past expiry or across local-store scopes is promised. Aggregate serialization failure must not relabel committed items as rejected; outcome recovery remains item-key based even if the full response cannot be delivered.

## Integration and concurrent ownership

| Area | Proposed boundary |
| --- | --- |
| T2380 `Writes/MCPWriteCoordinator`, command, snapshots and receipts | Reuse authoritative per-item execution. Do not open, alter, reset or repair production guard stores during specs. Implementation must not duplicate recovery machinery. |
| New batch request/preview/orchestration types | Prefer feature-local MCP files; proposed design must establish a truly read-only validation boundary rather than calling write coordinator for preview. |
| T63 `MCPServer`, `MCPTypes`, common handler dispatch and schema wiring | Sole writer remains T63 until parent coordinates a handoff. Batch tool registration, nested item schema support, and dispatch must be staged as an interface request, not concurrent edits. |
| T63 read deadlines/admission/publication | Domain mutations remain writes. A dry run's read-only nature does not automatically classify it under existing covered-read deadlines; classification and immutable preview DTOs need explicit coordination. Do not reuse cursor publication as a write transaction. |
| T2382 capture and reusable snapshots | Read-only design reference. Frozen cursor/snapshot revisions remain unchanged; preview and submission use current authoritative task state. |
| T2383 serialization | Coordinate a common batch envelope and nested T2380 outcomes, structuredContent/text compatibility, error categories, normalized saved fields, and serialization failure semantics before shared wiring. Historical receipt JSON remains the source for replay; adding structured output must not rewrite receipts or remint records. |

Canonical `r1` includes comments even when response comment bodies are omitted. A preview or projected result must preserve that token rather than hash its output fields. Current text JSON payload compatibility must be retained. The task snapshot and comment fetching paths can fail; those failures cannot masquerade as a successful preview or a clean revision.

No heavy builds or tests were run; T63 owns that slot. At the initial scope gate, no production source, live ticket status, write guards, recovery actions, pushes, merges, deployments, or approved peer specs were changed. Following scope approval, the workflow status transition to Spec was committed through the authorised MCP tool with its comment and fresh key.

## First review gate (parent to ask user)

Approve **full spec**, feature name **`batch-task-mutations`**, and the initial scope: bounded explicit update/status/comment operations with a no-write dry run, ordered per-item commits, and T2380 item-level replay protection?

Recommended starting semantics are stop-on-first-unsuccessful item and one resolved task per batch; both remain proposals for requirements, not approved decisions. The parent may collect changes or an alternative name. On explicit scope approval, move T2384 to Spec using its current revision and a fresh key with the workflow comment, then begin requirements. Requirements, design and tasks each require their own explicit gate.
