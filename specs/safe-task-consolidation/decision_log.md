# Safe task consolidation — decision log

## Approval state

| Gate | Evidence / state |
| --- | --- |
| Resume planning | Owner `Sentinel_c4dd914497c08191bc5612ccddd5449c`: “While Asterism is ongoing, start on the spec for 2381 and start planning the work for Meddy”. This branch owns T-2381 only. |
| Scope, route and name | Pending; refreshed scope document prepared for parent review. No prior T-2381 approval found. |
| Requirements / design / tasks | Not started or approved. |
| Implementation | Not authorised by this planning instruction. |
| Live bookkeeping | Paused with live MCP mutations; local records only. |

## Quick Decisions

| Topic | Decision / basis |
| --- | --- |
| Ticket identity | Cached full saved read at 2026-10-05T07:24:38.542Z verifies T-2381 “Add explicit duplicate links and safe task consolidation”, UUID F5CED508-F7C5-4AC0-B804-8945DF9B9B65, Idea/Feature, revision r1:ebd80bc9a55f82f56175f5723ad2b611ac196920bb616e41124e990b7d827a21, no comments. This is local saved evidence with unknown remote freshness. |
| Current base | Fresh origin/main 169ac244a11ebfbdacce3d4a25fcddfe395ac6d2 includes verified merged T-1734 PR #254 and the MCP foundations. |
| Preserve prior work | Original T-2381 branch/bf4f40a9 remains intact. New planning branch T-2381/safe-task-consolidation-spec carries a copy of its initial document; canonical and T-1734 worktrees are untouched. |
| Foundation ownership | Owner-approved T-1734 scope/ADR 4 is inherited as the foundation: one typed relationship implementation including duplicate-of/canonical resolution, participating local owned saves, truthful outside-writer/import limitations. T-2381 approvals are separate. |
| Quiet profile | Read-only source/docs, local Git bookkeeping and internal document review only. No heavy commands, review CLI, settings, deployments or live writes while Asterism runs. |

## Product choices pending

Group ceiling/cross-project participation, terminal-candidate closure, survivor field preservation and whole-operation undo/conflict/retention policy remain proposals in scope-assessment.md. They require requirements discussion after scope/name approval. There is no new ADR choosing a persistence architecture or expanding other tickets.

## Recovery review — 2026-10-05

Recovered and read the interrupted worker's saved scope and this log without replacing either. Verified the cached full ticket response at `/tmp/t2381-spec-source.json`, the original scope checkpoint `bf4f40a9`, current branch/base (`f791bd0d` / `169ac244`), and merged T-1734 ADR 4 plus the MCP write contract. Related task-6 T-1734 worktrees were clean at inspection. No prior T-2381 scope approval was found.

Read-only scope review found no blocking mismatch: caller-selected equivalence, preserved originals/history, canonical readback and reversible consolidation match the actual ticket; duplicate-link ownership and participating synchronous pre-save validation/owned commitment match the merged foundation. Same-project/six-total limits, status policy and undo conflicts/retention remain proposals rather than approved requirements. A full peer/critic review of requirements/design/tasks remains for those gated phases.

Next gate is unchanged: scope, full-spec route and name approval through the parent. No requirements, design, tasks, source implementation, heavy commands, live bookkeeping or maintenance were started. Existing uncommitted documents are checkpointed together; original branch, canonical main and other worktrees remain untouched.
