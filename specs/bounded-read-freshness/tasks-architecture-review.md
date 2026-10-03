# T-63 tasks review — architecture and sequencing

Reviewed `tasks.md` against the actual local `starwave-tasks/SKILL.md`, approved requirements/design and recorded design approval `Sentinel_541ceb19e7c8819193d04d23c5263041`. This is planning review only. No implementation, external calls, builds, tests, commits or changes to the task/design/source files were performed.

## Conclusion

No planning blocker found. The 16 flat tasks form meaningful coding/test units, preserve single-writer integration ownership, and defer production work until the task gate. The explicit T2382 delivery gate must remain enforced during implementation; fixture-only integration is not acceptance.

## Skill and dependency checks

- Ran `rune list specs/bounded-read-freshness/tasks.md`: all 16 tasks render as pending with stream and valid dependency references; no parsing warnings appeared. The rendered dependency graph is acyclic and every task joins the implementation chain.
- Adjacent red/green pairs are 2–3, 4–5, 6–7, 8–9, 10–11, 12–13 and 14–15. Task 1 explicitly limits itself to types/interfaces and injection seams, qualifying for the skill exemption. Task 16 is testing only; behavioral repairs return to the owning pair rather than bypassing red tests.
- Stream 2's evidence monitor/policy files and test doubles can run independently after shared contracts. Capture, coordinator, publication and shared routing stay in stream 1. The plan does not invent separate streams for edits to the same shared files; heavy test execution remains serialized even when file work is parallel.
- Risk verification is early: history feasibility is tasks 2–3 before publication/projection; independent deadline feasibility is tasks 6–7 before publication/full routing; import matching uses injected proof and the approved unknown fallback in tasks 4–5, with actual capture integration waiting for both streams in task 10. Final integrated task 16 checks the live/unsupported outcomes without claiming prototypes prove them.
- All 29 granular acceptance criteria appear in the task references. Requirement 6.1 has executable caller examples and code-level advertised limits in tasks 14–15; the ancillary caller guide remains an explicit delivery obligation outside the skill's coding-only checklist.

## Architecture and integration assessment

Task 1 aligns the dedicated branch with merged foundation `201205bd4e786c7f152d8f99006b37da7da888c7` while preserving spec commits and other worktrees. Tasks 3 and 10–11 preserve the merged canonical comment-covered r1, saved-only capture and ordinary UUID selector behavior. Scope completeness and identity/comment closure are enforced at construction and consumption, with no totals expansion by attribution-only closure.

Tasks 8–9 directly cover the peer review's same-store lost-update correction: aggregate immutable candidates, atomic reservation transfer, validate-all-before-commit, one store swap and preencoded rejection selection. These are substantial coherent units, not file/stub/wiring fragments. The ordinary cursor store migrates under T-63 ownership; T2382's reusable store stays with its worker.

Tasks 12–13 explicitly gate actual shared wiring on parent-delivered T2382 helper/schema/store modules. T-63 remains the only editor for routing, handler/common schema/types and app construction. The external dependency cannot be represented as a local completed task: task 13 must remain blocked in practice until those actual approved modules are available and their contract tests pass. The described parent-selected clean dependency commit prevents duplicate implementation or foreign-worktree edits.

Task 16 requires Xcode27, parent coordination for an exclusive heavy build/simulator slot, serialized SwiftData suites and the Xcode MCP fallback only when available. The later full pre-push-review/Pulsar workflow is acknowledged separately and does not authorize merge/deployment or an otherwise unauthorized publication.

## Concrete execution refinements

1. Keep task 1 genuinely interface-only: metadata encoding behavior or publication behavior belongs in its corresponding tested pair; interface exemption must not absorb runtime code.
2. Preserve task 2's signed-store harness as executable observation/assertion code. A missing import or inability to prove history applicability must produce the recorded unsupported/inconclusive result, not a passing claim of remote coherence. If it requires human remote edits or signing changes, surface that actual prerequisite to the parent before dependent verification.
3. Record the accepted T2382 dependency commit at task 13 and run against actual helpers before marking it complete. Avoid a mutually blocking handoff: T-63 publishes contracts first; T2382 builds separate modules from those contracts; T-63 performs common-file integration last.
4. Treat the caller guide and full pre-push-review as ancillary completion obligations, despite their intentional absence as noncoding checklist tasks. Task 16 alone cannot declare complete feature delivery while those obligations remain outstanding.

These are execution clarifications rather than required changes to the approved design or new implementation scope. The parent should present the task packet for its separate explicit approval and stop at that gate.

## Foundation handoff revalidation

Re-read the clarified tasks 3, 7, 9 and 12. The two-way dependency is now explicit and acyclic: actual SwiftData saved/canonical capture verification (3), actual Hummingbird router/encoded-response verification using fixture read work (7), and shared publication/ordinary-retention verification (9) need no T2382 modules. Their verified local foundation commit and evidence go through the parent to T2382, which can implement its separate modules while T-63 advances the later local work. Actual helper integration at 13 and integrated acceptance at 16 still require those modules. The handoff authorizes no remote publication. This clarification adequately resolves the cross-ticket circular-gate concern; no new planning blocker found.
