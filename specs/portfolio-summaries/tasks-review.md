# Portfolio summaries: task approval review

Status: tasks approved by parent user Sentinel_c2e9343628948191b921868234aaf409; implementation authorized under the approved dependency graph. Requirements and final aligned design are approved; no production implementation has started.

Design approval: parent user “Both 63 and 2382 are approved without required changes”, Sentinel_541ceb19e7c8819193d04d23c5263041. This includes T-2382 3932e88 and T-63 5639c40 scope/publication contracts. The dedicated branch remains rooted in merged T-2380 201205bd; other worktrees are preserved.

## Execution plan and two-way handoff

Fifteen Rune-managed tasks form six adjacent test/implementation pairs, plus interfaces/schema wiring and final testing. T-63 first proves its foundation through actual admission/capture/router/transport using a synthetic read descriptor and minimal prepared-result/publication test doubles. That proof does not require T-2382 modules or T-63's remaining ordinary-read conversions. Parent supplies the foundation revision; T-2382 tasks2/3 reuse its harness and add saved-only/coherence and 2,375-task/comment-revision capture assertions before aggregation exists.

After the foundation gate passes, aggregation and retention occupy independent files/streams while T-63 completes remaining read paths. Tasks10/12 hand T-2382 descriptor/store/helpers to T-63 for shared registration and lifecycle wiring. Task13 is full cross-ticket acceptance and waits for both completed paths. It does not block the earlier foundation proof.

T-63 is sole writer of shared routing/schema/capture/freshness/deadline/publication/lifecycle files. T-2382 owns its dedicated service/store/request/projection/handler/descriptor modules and portfolio assertions. Existing passing foundation assertions are verified baseline, not manufactured failures. Design commits alone do not imply production interfaces already exist.

No scoped read claims whole-portfolio evidence. Saved-only capture never saves or rolls back pending UI edits. Retained metadata/revisions/expiry remain frozen. Selected same-store batch changes combine into one candidate/reservation and one swap; all stores validate before any commit; large retirement occurs after unlock.

## Self-check

- Rune list parses all 15 numbered pending tasks without warnings; streams and dependency references render.
- All 31 granular acceptance criteria have task references. Every GREEN item follows its paired RED item and directly depends on it.
- The dependency graph is acyclic; independent branches join into final integration. The two-ticket foundation/final handoffs avoid a mutual gate.
- Task1 supplies nonfunctional typed service/store/handler seams so RED assertions compile and fail behaviorally. Tasks7/12 replace store/handler seams. Types/schema/wiring are the skill's TDD exemptions.
- All three design risks map to executable task2/3 gates, and dependent aggregation/store work is blocked by them. App-level evidence is required; standalone timing probes remain supporting evidence.
- Parallel aggregation/store streams have separate files. Shared heavy Xcode27/simulator runs are serialized through parent. Makefile failures use Xcode MCP when available; none is currently callable, and downgrade is prohibited.
- Non-goals remain excluded: UI/App Intents, historical reporting, identity repair, persisted schema migration and deployment. No manual prerequisite is introduced by this code-only feature. T-2380 CloudKit receipt deployment remains its owner's release prerequisite.

## Review findings

Critic and two peers found registration before handler definitions; task1 now includes nonfunctional typed store/publication/handler seams. Peer feedback clarified harness reuse, verified baseline passes and foundation capture/encoding before aggregation. Final reviews passed these corrections. Parent's two-handoff clarification passed final critic and peer dependency rechecks: no circular gate or remaining must-fix.

External Codex/Kiro retries remain stopped after automatic approval review rejected delegated disclosure authorization. The permitted two-peer subagent fallback was used; no external model review is claimed.

## Subsequent workflows and approval

After implementation, run the full local pre-push-review skill including Pulsar, resolving any otherwise unauthorized publication through parent first. Frequent branch/worktree commits are authorized. Push, merge and deployment are not authorized by task approval.

The local [task skill](/Users/arjen/.codex/skills/starwave-tasks/SKILL.md) requires explicit task approval and states: “The model MUST NOT attempt to implement the feature as part of this workflow.” The parent therefore receives the next gate before production edits.

Task approval received; the planning gate is complete.
