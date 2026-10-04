# T-2382: Portfolio summaries — scope review

Status: scope, full-spec workflow, and feature name approved in parent conversation (Sentinel_3ccdbb1152c88191b673f3dde9f76e60). Behavioral proposals below are inputs to the requirements review; requirements, design, and tasks are not approved or implemented.

Transit agents currently download tasks to construct project summaries. This feature would expose compact project and portfolio counts with explicit status, time, identity, and freshness semantics, so agents can describe recorded work without interpreting counts as a release verdict.

## Scope approval record

The user approved the **full spec workflow** and feature name **portfolio-summaries**. Requirements approval, design approval, and task approval remain separate gates.

Full spec is appropriate because this adds a public MCP contract and requires decisions about compatibility, activity evidence, time windows, and inconsistent identities. The user also explicitly requested the full process. The local creating-spec skill requires scope approval before requirements; the requirements skill requires a confirmed feature name before drafting requirements.

## Verified baseline

- Canonical repository: `/Users/arjen/projects/personal/transit`; origin `ArjenSchwarz/transit`.
- Dedicated branch: `T-2382/portfolio-summaries`.
- Worktree: `/Users/arjen/Documents/Codex/2026-10-03/task-2/transit`.
- Base and locally observed origin/main: `0db453bba3b1da3b8958723947dc41c165ecf0dd` (merged T-2379 bounded batch queries).
- T-2380 remains `ef29b2b` on its existing worktree and does not contain this base. It is outside this task.
- No repository AGENTS.md or `.agents/skills` was found. Repository `CLAUDE.md` and local Transit/Starwave skills were inspected.
- `get_projects.activeTaskCount` currently counts every nonterminal task, including ideas. Its existing semantics must remain compatible unless explicitly approved otherwise.
- Tasks record creation, last status change, and optional completion dates; comments record creation dates. There is no general task/project edit timestamp. Milestones record creation/status/completion dates.
- T-2379 pagination retains serialized pages for five minutes. Continuations read the original result; they cannot recapture freshness or extend its lifetime.

## Proposed scope for requirements discussion

| Concern | Proposed behavior to approve during requirements |
| --- | --- |
| Portfolio and project scope | Return all projects, including empty projects; support project UUID and existing unambiguous name resolution. Unknown/ambiguous selectors produce explicit errors. |
| Counts | Include all eight status keys, including zero values, total task count, idea count, nonterminal count, and workflow count. Workflow count excludes ideas and both terminal statuses, and includes planning, spec, ready-for-implementation, in-progress, and ready-for-review. These are stage counts, not a claim that every included task is currently being worked on. |
| Compatibility | Preserve `get_projects.activeTaskCount` as the existing nonterminal count. Document it precisely; provide explicit new summary fields instead of silently changing existing consumers. Final field/tool names belong to the design gate. |
| Recent completions | Require an explicit UTC start/end window, with start inclusive and end exclusive. Count currently done tasks with completionDate inside that window; report abandoned tasks separately if included. This is a current-record view, not a historical transition/event count. Missing dates are reported separately rather than inferred. |
| Recorded activity | Return nullable last recorded activity with evidence kind. Proposed evidence is task creation/status change, comment creation, and milestone creation/status change. Do not label this general last modification; arbitrary edits have no recorded timestamp. |
| Milestones | Include open, done, and abandoned milestones, their recorded status, and all task status buckets. Open milestones can contain done/abandoned tasks without changing the milestone status or implying release completion. Show tasks without a milestone separately. |
| Identity problems | Preserve project UUID identity even when names duplicate. Explicitly flag duplicate display IDs, missing project references, and milestone/project mismatches; never collapse tasks solely by display ID or silently omit unresolved records. Exact diagnostic shape and reconciliation invariants need requirements discussion. |
| Reconciliation | Counts derive from one captured local view and agree with equivalent status/project filters over that same view. Independent live requests cannot promise equality across intervening changes. Design must define whether snapshot identity is informational or reusable for task queries. |
| Compactness | Return aggregate data and identity diagnostics without task descriptions/comments. Response size depends on projects/milestones/diagnostics, not ordinary task payloads. Bounds and pagination integrate with T-63; no successful silent truncation. |

## Shared contract needs sent to parent

T-63 owns bounded reads and freshness. Its preliminary contract is unapproved: `asOf` is local immutable capture time; `snapshotId` identifies the materialized view; freshness expresses locally observed import evidence and cannot prove remote completeness. Original capture metadata must be preserved across pages.

Portfolio aggregation needs one shared metadata envelope covering project, task, milestone, and any comment evidence captured for the result. Completion-window endpoints must be distinct from `asOf`. Empty and scoped results need the same envelope. Timeout/storage failure must be distinguishable from a valid empty project. Identity diagnostics and partial/incomplete outcomes must not be presented as exact reconciled totals. A snapshot identifier alone cannot establish comparison with separately captured task-query pages; requirements must settle the intended reconciliation guarantee before interfaces are bound.

T-2382 owns aggregation semantics and a dedicated summary service. T-63 owns freshness/read-budget services. Shared MCP handler/schema registration and read-only classification need a parent-coordinated owner in the design phase. No shared files will be edited before that agreement.

## Questions for the parent to surface

1. Full spec and `portfolio-summaries` name: approved.
2. Legacy `activeTaskCount` compatibility and separate idea/in-progress counts: approved in parent Sentinel_5479ed38c0cc8191a7c47a6487b6c0a1; extra combined counts remain requirements proposals.
3. Is the proposed currently-done completion-window definition sufficient, or is historical completion-event reporting needed? The latter needs new evidence/history beyond current records.
4. Use recorded status/comment/milestone activity (recommended), or narrow activity to task status changes? General edit activity requires additional persisted evidence.
5. Real externally reusable summary/task-query snapshots: approved in parent Sentinel_5479ed38c0cc8191a7c47a6487b6c0a1. Detailed retention/filter/error semantics remain requirements proposals.

## Capabilities and remaining gates

Per-command `require_escalated` is supported with automatic approval review; the isolated worktree creation succeeded. No global permission settings were changed. Xcode 27.0 build 27A266a is installed; no Xcode MCP tools are exposed. No builds/tests or simulator work were started. `send-md-to-phone` is available and will be run for this document. Local Codex memories directory is empty; no memory was changed.

Next: requirements approval after sequential critic/peer validation. The actual local peer-review-validator definition was found and its documented two-subagent fallback used; external CLI startup failed and escalated external disclosure was rejected by automatic approval review. See requirements-review.md for review evidence and the parent's disclosure approval request. Design and task planning follow only their preceding approvals. Implementation remains unauthorized at this gate. Full pre-push-review, including its Pulsar step, is required after implementation; no merge or deployment is authorized.
