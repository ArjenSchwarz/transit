# T-63 task approval packet

The user approved requirements and design, including final T-63 `5639c40` / T2382 `3932e88` scope/publication contracts (Sentinel_541ceb19e7c8819193d04d23c5263041). This packet proposes implementation tasks; none have started. The dedicated branch remains spec-only and must align to merged main `201205bd4e786c7f152d8f99006b37da7da888c7` before code changes.

## Self-check and independent review

Created/updated tasks through the actual local rune skill and CLI. `rune list` renders 16 pending level-one tasks with two streams and valid dependencies, without parse warnings. All 29 acceptance criteria are referenced; the dependency graph has no cycles; every task connects to final validation. Seven adjacent red/green pairs cover capture, import policy, deadline, publication, projection, routing and diagnostics. Task 1 is types/interfaces-only; task 16 tests the integrated result. No decorative phases or trivial setup fragments were added.

The three approved design risks have early coded verification: saved/history/import-visible capture in tasks 2–3, evidence applicability/unknown fallback in 4–5, and actual router/encoding deadline mechanics in 6–7. Dependent publication/projection/routing waits for those outcomes. A failed history mechanism cannot be silently replaced: use approved incoherent_capture failure or return a changed mechanism for design approval. Unavailable live evidence is recorded honestly rather than counted as positive proof.

Independent correctness and architecture reviewers found no planning blockers. Adopted refinements explicitly test matching/omitted cursor policy, numerical reservation charge transfer/rollback, and unsupported live evidence. Architecture revalidated the final two-way handoff without a cycle. See tasks-correctness-review.md and tasks-architecture-review.md.

## Cross-ticket handoff and ownership

1. T-63 defines common types, then proves saved capture/canonical r1 (task 3), actual Hummingbird transport mechanics (task 7), and shared publication (task 9) with fixture adapters/participants. These have no T2382 module dependency.
2. Parent receives a verified local foundation commit/interface/test evidence after those gates. T2382 consumes it and implements its separate portfolio aggregation, reusable store, snapshot query and schema modules while T-63 completes the remaining covered read paths. The local handoff does not imply a remote push or publication.
3. Actual cross-ticket modules are required for task 13 integration and task 16 acceptance. Fixture-only tests cannot mark either complete. Parent records and chooses the clean dependency commit; no foreign-worktree edits or duplicated modules.

T-63 alone edits shared server routing/lifecycle, handler init/common dispatch/read-only registration, existing/common schema wiring, metadata DTOs and app construction. T2382 retains its separate helper/store/API ownership. Saved-only capture, typed declared scope plus closure, canonical T2380 r1, frozen metadata and coalesced same-store publication remain unchanged.

Import monitor files/test doubles are the only separate T-63 stream. Parallel code work does not authorize concurrent heavy Xcode/simulator execution: parent allocates exclusive heavy gates, SwiftData suites serialize, and Xcode27 is mandatory. Use Xcode MCP on Makefile failure when available; an unavailable capability must be reported, never replaced by a downgrade.

## Ancillary completion obligations

The local tasks skill excludes noncoding documentation/publication work from its checklist. Requirement 6.1 still requires an updated caller guide based on the executable examples in tasks 14–15: metadata, error mapping, default/cached policies, deadline boundary, import limitations, new-query versus cursor replay, and bounded backoff. Deliver that guide under the later implementation workflow before claiming feature completion.

The user's full pre-push-review skill, including Pulsar publication, is also a later mandatory workflow. Inspect its actual instructions then; ask the parent before any otherwise unauthorized publishing action. Frequent local commits remain authorized. No merge or deployment is authorized. No new manual prerequisite is presently known; if signing/account setup is actually needed for live evidence, surface the concrete prerequisite to parent before dependent testing.

## Next gate

Do the tasks look good? Surface this question in the parent conversation and wait for explicit task-list approval. Do not start production implementation, mark the ticket ready, or update specs overview before this gate. After approval, complete the remaining actual creating-spec steps, honoring the already approved dedicated branch and preserving all other work.
