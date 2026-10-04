# Portfolio summaries: requirements review

Status: sequential critic and two-peer validation complete, including final response-bound delta; requirements await user approval.

## Design critic

Independent read-only critic ran the local `design-critic` skill after reading the complete requirements, decisions, scope, and T-63 context.

| Priority | Finding | Disposition |
| --- | --- | --- |
| P1 | Reusable cross-tool views expand existing encoded-page snapshots and need explicit user choice. | Resolved by user approval Sentinel_5479ed38c0cc8191a7c47a6487b6c0a1. T-63 owns capture/freshness; T-2382 owns externally reusable API/lifecycle. |
| P1 | Undefined shared read budget is not testable. | Shared approved contract: produce encoded response and make it available to transport within five seconds for individual reads and entire read-only batches; explicit mixed-write-batch exception. |
| P2 | Capture consistency needs an observable guarantee across project/task/milestone/comment data. | Require one immutable internally consistent view. |
| P2 | Identity diagnostic detail can grow with every task. | Recommend exact diagnostic counts with bounded identity samples and explicit sampling labels. |
| P2 | Unrelated identity corruption could unnecessarily fail scoped requests. | Fail scoped requests only when ambiguity affects scope or attribution into it. |
| P2 | Equivalent query filters need definition. | Specify project UUID/effective status reconciliation, distinct from completion-window aggregation and malformed relationship buckets. |
| P3 | Empty scoped result wording is ambiguous. | Clarify existing project with zero tasks/milestones. |
| P3 | Scope approval record stale. | Recorded actual user approval reference. |

## Peer validation

Actual local agent definition was read at `/Users/arjen/.claude/agents/peer-review-validator.md`. `PERSONAL_PROJECTS=1`; external Codex/Kiro MCP review agents are not exposed. Installed CLI startup attempts failed under the sandbox; escalated attempts were rejected for missing disclosure authorization. Parent subsequently supplied user sharing approval Sentinel_7ba5dca061b4819183c1d6066aa1e949; the prescribed one-time retries were still rejected because automatic approval review did not recognize the delegated transcript as trusted direct user authorization. Parent informed the user; retries stopped, and no new approval request or bypass is pending here. The validator obtained two independent subagent perspectives using the definition's explicit fallback: technical correctness/edge cases and architecture/scope/maintainability. This was not distinct external-model consultation.

Technical peer verified that existing `MCPQueryFilters.matches` uses raw stored status, while the task model maps unknown values to idea. Requirements now explicitly propose model-effective status for summaries and snapshot-bound queries, with malformed-status diagnostic counts. Architecture peer requested protection of ordinary task-query behavior and fail-closed handling of unsupported snapshot options; both are explicit in the draft.

Consensus: preserve approved reuse and compatibility decisions; original capture/freshness must remain immutable; no silent data truncation or live-data substitution; five-second hard deadline needs design evidence beyond a main-actor timer. No peer reopened user-approved reuse. Remaining choices and feasibility constraints are surfaced for requirements approval and the later design gate.

Further peer findings addressed: explicitly retain descriptions/metadata for full snapshot-bound task detail, reject comment-body requests rather than reading live bodies, and expose raw and effective milestone status for unknown values. The interim success-admission proposal was not approved and has been removed. The final draft preserves the approved actual five-second encoded-response/transport-availability bound and mixed-write exception.

T-63 supplied source-backed feasibility evidence: the Hummingbird/NIO router and response formatting are nonisolated before awaiting the MainActor handler, and response/request value types are nonisolated Sendable. A separate response coordinator can arbitrate timeout without waiting for noncooperative worker completion, cap lingering operations, and reject late snapshot publication. This is a design hypothesis requiring a prototype, not an implemented or tested guarantee; a timer on the blocked actor or a structured task group waiting for its child would not suffice.

## Approval questions

Legacy activeTaskCount compatibility, separate idea/in-progress counts, real shared-view reconciliation, and the actual five-second response bound with mixed-write exception are approved. Requirements approval must settle their detailed contract, current-record completion semantics, recorded activity scope, extra combined totals, five-minute retention and refresh policy, sampled diagnostics, scoped failure isolation, effective-status rules, and full-detail/comment restrictions. Design and tasks remain separate gates.

The final critic reviewed the response-bound alignment and reported no must-fix contradiction. Both independent peers subsequently reread that final delta and passed it. The actual five-second encoded-response availability guarantee, whole-read-only-batch scope, mixed-write exception, and late-publication prohibition are consistent throughout the packet. Timeout arbitration and bounded lingering work still require prototype evidence at the design gate.

**Next parent approval prompt:** Do the requirements look good or do you want additional changes? Approval covers the remaining proposed completion/activity definitions, workflow/nonterminal totals, five-minute retained-view lifetime, refresh-if-needed policy and evidence thresholds, sampled identity diagnostics, scoped failure isolation, effective-status rules, and full-detail/comment restrictions. It does not approve design, tasks, or implementation.
