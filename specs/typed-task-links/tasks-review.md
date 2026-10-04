# Typed links — task-plan review and approval gate

Current contract: owner `Sentinel_c95239aefa6481919303c2353b8a9e9c` approved participating Transit writes with pre-save validation and outside-writer conflict reporting (decision_log.md ADR 4). The historical all-independent-writer/import validation-to-save fence and persistence-redesign completion gate below are superseded. Original tests, failures and approvals remain historical evidence; owned same-store domain/receipt saving and T-2402 deferral remain unchanged.

Design checkpoint `56e9ad5` was approved by owner `Sentinel_775be6f4fc6c8191a9d7ccf1d0c04557`, including seven-day recognition and early migration/atomic-save feasibility. Local approval record is `1b82a48`; task draft is `da415e1`. Task checkpoint `18a268f` and conditional implementation were approved by owner `Sentinel_d1ba9360969c81918777711b2420bfc7`. Technical foundation/feasibility dependencies remain; no further readiness approval is required.

## Plan and verification

Rune created and managed 22 flat numbered tasks: 11 adjacent Red/Green pairs in one stream. Shared services, snapshots, capture and coordinator wiring make a sequential stream appropriate. Every downstream task directly declares the relevant migration (2), atomic-save (4) and bounded-capture (8) gates, in addition to incremental dependencies.

`rune list specs/typed-task-links/tasks.md` parsed all tasks/dependencies without warnings. A lightweight check confirmed all tasks pending, adjacent Red/Green ordering, valid acyclic dependencies, direct gate links, and all **39 granular acceptance criteria covered before the final integration pair**. No app tests/builds, test fixture execution or implementation occurred. The plan uses owning test containers, serialized Swift Testing and seeded generated graph/reference properties during later authorized implementation.

## Critic and independent peer review

Read the actual local starwave-tasks, Rune, design-critic and peer-review-validator instructions. The documented internal fallback supplied two independent read-only peers because external review tools were unavailable; no source disclosure.

| Review | Finding | Resolution |
| --- | --- | --- |
| Critic | Intermediate parser/schema wiring could expose directives before protected apply integration. | Tasks11–12 test and enforce fresh-link unavailability until task14 passes; no accepted-and-ignored directives. |
| Critic | Local migration/schema-shape tests were not development CloudKit verification. | Tasks1–2 include opt-in isolated development schema/deletion fixture. Full gate2 requires both disk and development evidence; prerequisites name clearance/setup. |
| Critic | Requirement7.4 needs executable caller guidance. | Wire/query Red/Green pairs test and implement schema/output descriptions covering direction, guards, no-ops, removal expiry, local-only guarantees and historic coverage. |
| Critic | ADR2 retained stale pending wording. | Recorded the approved seven-day decision consistently. |
| Correctness peer | No blocking issue; make foundation pre-coding conditions easy to track. | Standalone prerequisite checklist includes all four handoffs, verified merged base and refreshed live schema. |
| Scope peer | No blocking issue; specify missing development-schema setup ownership. | Parent designates authorized development operator; initialize only development schema from task2 models, verify in CloudKit Console, keep task2 incomplete until confirmed. |

Both peers validated the critic's refinements and found no task-approval blocker. No material disagreement remains. The selected commit mechanism is not proven: task4 must demonstrate closure of validation through save against peer-context/import commits; failure keeps writes unavailable and returns design for review before dependent work. Tests cannot mark that task green by weakening the invariant or skipping the race.

## Boundaries and prerequisites

Implementation needs a separate approval and compatible merged T-63/T-2382/T-2383/T-2384 foundations with ownership handoffs. Early gates use synthetic/copied disk stores and an explicitly cleared development CloudKit environment. Development setup and heavy-job scheduling are external prerequisites, not production deployment tasks. No framework history purge, global convergence promise, task deletion, guard reset or production schema promotion is included.

Consolidation T-2381, regression/workflow T-1732/T-1733, copying T-649, native link editing and batch link mutations remain excluded. Live Transit mutations/status/comments stay paused; all bookkeeping is local. The broader testing approval does not authorize T-1734 implementation or a heavy-test slot during spec planning.

## Exact next approval through parent

**“Do the T-1734 typed-task-links tasks look good? Please explicitly approve this task plan. Approval completes task planning only; implementation remains a separate approval and stays blocked by foundation handoffs and the migration/atomic-save/capture feasibility gates.”**

No tasks are claimed or started. Phone transfer outcome is reported separately; it does not constitute approval.

## Task gate outcome

Approved with conditional implementation by owner `Sentinel_d1ba9360969c81918777711b2420bfc7` against checkpoint `18a268f`, relayed by parent. The question above is historical. Live writes/client activation/deployment remain held; tests need the parent queue slot.
