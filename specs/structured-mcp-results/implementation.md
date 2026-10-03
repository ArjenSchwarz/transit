# Structured MCP results: implementation evidence

## Authorisation and ownership

Task plan b58298a/implementation approved by parent-verified Sentinel_ba4c6123288881918042d6aeb8ba6dc5. make-it-so delegates all coding; the main worker owns bookkeeping, coordination and review. Single ready stream1 begins interface1 in place; once1 completes, pure Results/Protocol streams may use isolated worktrees.

T63 retains common handler/types/router/definitions/lifecycle ownership pending exact verified handoff manifest. Reads foundation remains shared with T2382; no blanket transfer assumed. T2384 owns MCPWriteCoordinator.swift/coordinator-specific tests; T2383 modifies only downstream consumers unless a coordinated owner patch is agreed. T2382 currently holds heavy-test slot, then T63 focused10/11, then requested short T2383/T2384 RED/GREEN slots. Source drafting holds no test slot.

Transit ticket moved to in-progress with protected committed outcome, key T2383.implementation-approved.20261003 and revision r1:98d5c0bb10c440984383379166f4c98391519018e7c1bc694a12fcc8af04bd62. Source main/origin remain verified201205bd at implementation start.

## Isolated schema test tool

Owner approved recognised-PyPI disposable local install at Sentinel_5afe0d1e8fe081919db67f470430fb2a. Created ignored `.codex-cache/schema-tests/venv`; pip isolated install from https://pypi.org/simple succeeded, Draft202012Validator import confirmed. No global packages/settings or app runtime dependency. Resolved versions:

| Package | Version |
| --- | --- |
| jsonschema | 4.25.1 |
| jsonschema-specifications | 2025.9.1 |
| referencing | 0.36.2 |
| rpds-py | 0.27.1 |
| attrs | 26.1.0 |
| typing_extensions | 4.16.0 |

Schema tasks8–9 must commit test-only pinned dependency/bootstrap instructions/code using these resolved versions for repeatable local/CI environments. Availability alone is not schema-validation completion. No production schema fixture validated yet.

## Pending execution evidence

Interface1/gpzncvl completed at `8ea94ce0b3b9a3b73fcee330aed0c9883a08e92f`: eight new Results/Protocol declaration files, throwing runtime placeholders. Targeted parse, strict no-cache SwiftLint, and standalone Swift6/default-MainActor typecheck of only new modules plus read-only MCPTypes all passed. No application build/test or shared source edit at this checkpoint. RED/GREEN evidence will name exact focused commands/results and slot ownership. Common API delivery15 requires verified local revision; no reverse dependency on production T2384. Client negotiation/activation, full pre-push/Pulsar completion review and push/merge/deployment boundaries remain explicit.


## Parallel RED preparation

Rune phase/streams retrieval after task1 reports stream1 task2 and stream2 task12 ready. Created isolated worktrees from8ea94ce under `.claude/worktrees/results-stream-{1,2}`, branches `stream/structured-results-{1,2}`. Stream1 owns lossless/source RED fixtures; stream2 owns pure modern-protocol RED fixtures. Both may draft/parse/lint only while the parent schedules exact heavy test slots. No GREEN/completion claim before meaningful RED evidence. Their task statuses are isolated until integration; the root task list remains authoritative for merged completion.

Concrete declaration-only interface sent to T63/parent and T2384: `MCPResultAdapter.source` preserves text/optional isError/origin/evidence; `present` derives separate presentation; `MCPResultEncoder.freeze` returns immutable encoded tool-result Data without RPCID, and `encode(fragment:id:)` wraps a fresh ID. `prepareMutationFallback(id:source:context:metadata:)` returns complete immutable response Data prepared before effects. T63 retains retention/publication hooks and charging; T2384 retains coordinator policy. Runtime delivery gate15 remains pending.


## Declaration review and lint

Root `make lint` passed both host ownership/schema preflights and SwiftLint: zero violations across405 discovered Swift files. This command runs no application build/tests. Internal design critic found no task1 declaration blocker, with required downstream checks: encoder accepts only valid immutable source/frozen fragments; expensive presentation/freeze/encoding honor original-operation checkpoints; recursive value equality/destruction must be stack-safe or nesting explicitly bounded. These are implementation verification obligations, not delivered runtime capabilities.


Parent confirmed mechanical dependency correction: task13 also blocked by task3. Protocol RED drafting remains parallel; its GREEN waits parser delivery/integration. Final review must reflect this corrected DAG rather than claim independently executable protocol implementation.
