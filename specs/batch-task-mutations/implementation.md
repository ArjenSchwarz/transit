# Batch task mutations: implementation explanation

This explanation describes the completed feature-local implementation and modern MCP integration at runtime source `5c42c7e059e8c810e89d366f0889aef132adf5c5`. Fresh native macOS, isolated iOS unit, and UI acceptance all passed. Publication and client activation remain separate approval/readiness boundaries.

## Beginner Level

### What changed

`mutate_tasks` lets a caller submit a plan containing 1–50 explicit task edits, status changes, or comments in one tool call. Each item names one task and supplies its own retry key. Update and status items also supply the revision they expect to edit. A task can appear only once in a plan.

### Why it matters

A caller can preview a canonical description update and several duplicate closures before submitting them. Preview reads saved local records and describes normalized proposed effects without saving anything or reserving retry keys. Execution processes items in order and stops at the first unsuccessful or unverified result. Earlier successful items remain saved.

### Key concepts

A revision detects edits made since an earlier read. A retry key identifies one exact operation in the originating local store. A retained receipt records the original result, so retrying identical arguments can return that result without repeating the effect. The batch has no shared receipt or all-or-nothing transaction: retrying the batch can replay its completed prefix and continue previously unattempted items.

## Intermediate Level

### Changes overview

The feature lives in `MCP/BatchWrites`. Its parser validates the entire bounded request before privately constructing an executable plan. It preserves original argument spellings for the existing protected write coordinator. A saved-read factory provides a private, autosave-disabled context for preview. The batch coordinator invokes the existing protected operation once per attempted item and advances only after authoritative committed evidence.

### Implementation approach

The optional batch policy guards every relevant shared-context phase. Pending UI edits prevent new acceptance, mutation, save, rollback, or unresolved recovery through that context. Read-only retained terminal replay and key-conflict inspection remain available. Standalone writes keep their default policy. Comment validation is shared with the existing comment service, and status-plus-comment remains one protected transaction.

The batch result is one generated logical source. Every returned attempted-item result retains original text, optional `isError`, and available original JSON separately from the aggregate's classification. Common structured presentation adds task-identity link entries outside that source; the delivered common contract explicitly reports navigation unavailable pending its separate foundation. Before any effect, the handler prepares a complete response containing request correlation and compact original index/tool/key/UUID recovery mappings. Later encoding failure selects those ready bytes without running the encoder again.

### Trade-offs

The bounded list reduces round trips while retaining per-item transactions. It does not provide a CloudKit transaction, automatic duplicate selection, or compensation. Saved-only preview avoids disturbing pending edits but cannot certify imported freshness or future write availability. Existing receipt replay preserves historical results even when the target later changes or disappears; it does not certify current canonical contents.

## Expert Level

### Technical deep dive

Shape validation rejects unknown fields, safety-format errors, wrong JSON types, normalized UUID collisions, duplicate tool/key pairs, and exact caller-ID collisions before any item is attempted. Numeric integer fields are checked from original decimal tokens, avoiding floating-point rounding. Domain strings and conditional status-comment authors retain existing per-item validation semantics. Original UUID argument spelling stays part of T2380 payload binding.

The evidence classifier verifies receipt version, tool/key identity, types, target identity, revisions, terminal dates, and optional error flag before treating an item as committed. Unreadable or unsupported evidence cannot prove no effect. Cancellation is observed between attempts; it does not undo committed effects or turn a caller timeout into observed cancellation. An unstarted item has no acceptance attributable to this submission.

Original retained JSON is inserted through validated raw fragments rather than reparsed through Foundation dictionaries. Missing and null fields, unknown fields, numeric lexemes, and exact original text remain preserved. The common parser's 32-container cap can reject a generated aggregate whose individually readable nested receipts were shallower; that post-effect failure selects the preencoded shallow fallback. Compact fallback excludes giant caller labels, raw records, and entity links. Normal result context may carry explicit task UUID source positions while the prepared fallback context stays link-free.

### Architecture impact

The application batch remains one modern `tools/call`, outside protected single-operation key registration, covered-read admission, snapshot retention, and the five-second read contract. Its router must preserve the original JSON argument subtree before the older `Any` bridge. App-owned services, coordinator, and container are injected; no second receipt engine, guard format, or recovery action is introduced.

### Operational limits

Retry guarantees are local-store and retention scoped. Callers retain original arguments, keys, returned expiries, and original submission time when the first response is lost. Removed or expired receipts do not prove the original effect never happened; a removed key can execute as new under the existing write contract. Unknown commitment requires reconciliation with original keys, never automatic key rotation. A retained canonical update may replay while duplicate closures remain unattempted, so callers needing a current canonical-state condition reconcile it before those closures.

## Completeness Assessment

All 32 approved acceptance criteria are implemented and mapped in the internal spec review. Parsing, saved preview, dirty-context safety, authoritative ordered execution, original-evidence aggregates, complete fallback preparation, real tool registration, app injection, and caller documentation are complete. Fresh finalized verification passed: macOS 2,409 declarations / 3,049 cases; isolated iOS units 1,289 / 1,334; UI 21 / 24. All had zero failures, skips, expected failures, and native runtime warnings, normal exits, and complete owned-process drain. Focused integration 17 / 22 also passed and overlaps the full macOS result; these are not added into a unique total. No matching JUnit/coverage runner was detected for this Xcode project; native xcresult artifacts establish these results.

Modern installed-client compatibility and activation remain unverified and deferred to owner MacBook validation. Common link entries remain explicitly unavailable pending T572 navigation support; this batch does not invent URLs. The later T1734 participating-commit factory is separately coordinated; this feature does not claim a global import fence. The owner has resolved the earlier publication/disclosure holds and explicitly approved pushes, configured Claude review and eligible overnight merge. PRPilot review and merge are the next publication steps; deployment and client activation remain outside this workflow. No production writes, client configuration changes, or installed-app restart occurred.

## Evidence and historical checkpoints

Fresh reconciled acceptance is in [publication-verification.json](publication-verification.json): full macOS 2,409/3,049 and iOS units 1,289/1,334 at `b90e6f8`; corrected full UI 21/24 at `b8f9fc7`. Only reviewed UI fixture corrections separate those pins; production/configuration/unit sources are identical. The first UI attempt had four genuine fixture failures and a sampled runner-only finalization termination; it remains explicitly failed/unfinalized. The corrected full rerun passed normally. Original-worktree acceptance and artifact hashes remain historical in [task14-green-actual.json](task14-green-actual.json). See [final-handoff.md](final-handoff.md) and [final-critical-review.md](final-critical-review.md) for current completion and publication boundaries.

The following checkpoint notes preserve the original observations and restrictions at their recorded stage. Pending-task and slot statements below are historical and superseded by the final acceptance above.


## Task 1: intended RED confirmed

Executed the parent-granted focused command on 2026-10-03:

```sh
make test-quick TEST_TARGETS=TransitTests/MCPBatchTaskSafetyTests
```

The sandboxed attempt failed before compilation on dependency/Xcode access. The per-command escalated retry reached compilation. Explicitly typing the saved-read callback's ModelContext removed a cascading inference error; the final focused rerun failed only on the planned absent production seams:

- `MCPBatchWritePolicy` type and initializer.
- Coordinator `batchPolicy` argument.
- `MCPBatchSavedReadContext` at both factory call sites.

Final make exit: 2; Xcode exit: 65. No test bodies ran because this is an intentionally uncompilable RED against absent interfaces. This establishes the RED task, not passing behavior or implementation correctness. Full output is retained at `/Users/arjen/Documents/Codex/2026-10-03/task-4/verification/t2384-safety-red.log`.

After the final run, escalated `pgrep -fl 'xcodebuild|swift-frontend|swift-build|TransitTests|XCBBuildService'` exited 1 with no matches. The exclusive heavy slot was immediately released through the parent. Targeted strict SwiftLint and whitespace checks pass. The suite drafts 28 cases with persistent owning fixtures; unrelated production interfaces, shared serializer delivery and GREEN implementation were untouched.

Task 1 is complete; further test execution requires a new slot grant. T2383 delivered task 15 remains a prerequisite for later result/schema consumers.

## Task 2: focused GREEN confirmed

Under the approved DAG and sole coordinator ownership, Task 2 now implements the private synchronous saved-read factory and optional batch policy. Dirty admission uses existing validated binding and durable receipt inspection without repair, expiry writes, cleanup, recovery or domain fetch. Both accepted preparation continuations return directly when unrelated UI changes are present. The fresh synchronous apply callback validates exactly one saved task UUID; standalone callers retain the default nil policy.

Unchanged outcome helpers moved to `MCPWriteCoordinator+Outcomes.swift` so coordinator phase code remains within lint limits. Fixtures now consume the production identity validator and additionally cover retained payload conflict with malformed receipt and a direct missing-UUID callback. The safety suite has 30 cases.

The parent granted the exclusive focused GREEN command:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPBatchTaskSafetyTests TransitTests/MCPWriteCoordinatorTests'
```

The per-command escalated run compiled and exited 0, with no fixes or reruns required. The result bundle reports 36 executed cases passed: 30 batch safety cases and six standalone coordinator regressions. There are 19 test declarations, including nine parameterized tests with 26 runs; no failures, expected failures, skips or runtime warnings. The full log and xcresult summary are retained in `/Users/arjen/Documents/Codex/2026-10-03/task-4/verification/t2384-safety-green.log` and `t2384-safety-green-summary.json`.

Escalated process inspection again returned exit 1/no matches for the build/test worker patterns after the job. The heavy slot was immediately released through the parent before read-only xcresult analysis. Full `make lint` passes all ownership/schema guards and 402 Swift files; whitespace checks pass.

Tasks 1 and 2 are complete. Task 3 remains blocked on delivered T2383 task 15. No result/schema consumer, common server wiring, guard-store format or recovery-engine change is included. These focused results establish the Task 2 safety and standalone-coordinator boundary, not whole-feature readiness.

The root's read-only source critic reported no Task 2 blocker after auditing dirty phase entries, both preparation continuations, retained association and repair-free replay, binding conflict precedence, synchronous identity validation, historical bypass, default nil policy and fallback saved-context refusal. The external consumer gate is delivered T2383 task 15 (`gpzncvz`), including source 3 (`gpzncvn`), presentation 5 (`gpzncvp`), encoder 7 (`gpzncvr`) and schema 9 (`gpzncvt`); approvals or declarations alone do not satisfy delivery.

## Task 3: RED fixture draft ready; isolated execution pending

Read DELIVERED15 handoff `b21e358c8a5ea1e287afe332c1fc50d83303ce19`, source checkpoint `543c4a757e4cb7f9f73c973d7cb1be5725c8f342`, and the actual source/runtime dependency manifests read-only. Root imported the exact common consumer files in `fe1c57f`, with evidence `7d8ba36`; this worker neither imported nor edited those files. Draft uses the delivered source, presentation, metadata, JSON value, encoder and provider-selection APIs directly. The only intentionally absent seams are batch-local evidence assessment and compact fallback source construction for Task 4.

New `MCPBatchTaskEvidenceTests.swift`, `MCPBatchTaskEncodingTests.swift` and `MCPBatchTaskResultFixtures.swift` contain 13 declarations / 52 synthetic cases. They cover strict numeric/type/identity/revision/time evidence, original text/optional flags/unknown fields/null/numeric lexemes, retained retry direction, giant item ID and context stripping, original recovery index/tool/key/UUID, preparation failure before dispatch, payload/presentation/envelope failure after a synthetic effect, encoding-free ready-byte selection, depth-32 readable evidence overflowing its generated aggregate and retained depth-33 unreadable evidence. All effects are counters; no models, live writes or receipt/recovery actions are used.

Targeted strict SwiftLint, Swift frontend **parse only** and whitespace checks pass. A lightweight fixture check confirms all 15 exact mutation fragments change the baseline and preserve JSON syntax. No typechecking, build or app test ran; meaningful RED is unverified and Task 3 remains in progress. The coordinator and existing safety production files are unchanged.

Intended focused inventory is exactly `MCPBatchTaskEvidenceTests` plus `MCPBatchTaskEncodingTests`. This is a selector specification, not a runnable legacy `make test-quick` command. Before execution, parent must select the isolated development-host foundation, coordinate containment-owner App/project changes, establish signed smoke/preflight and exact enabled inventory, then grant an exclusive focused slot. No isolation edits, common integration, GREEN implementation or later task is included in this draft.

## Task 3: meaningful runtime RED verified; teardown limit preserved

Parent explicitly granted the bounded exclusive sequence. Inspected and imported containment commit `bbdb9df64c87fb52bd62490d39c3bc9727f876a9` as `8be35ea`, preserving the complete MCP tree, existing coordinator/App constructor wiring and receipt schema. All owner checkpoint hashes match. Declaration-only RED shells `0512d99` preserve original source with canAdvance false and throw notImplemented for fallback; they implement no GREEN semantics. Their source bytes were already present at smoke build launch; the subsequent commit changed bookkeeping only.

Offline isolation checks, dedicated fresh smoke build, signed-host preflight and one isolated smoke body all passed (exit0). Smoke observed memory-only storage, effective CloudKit disabled, disabled counters and a temporary development-container sidecar. The fresh shared Debug build, signed host/explicit unit-test launch preflight, enumeration and exact13 declaration inventory also passed (exit0). No unverified/production host or live settings/data action ran. Shared compilation emitted existing test/scheme warnings, preserved in the raw log; no zero-warning claim.

Both selected suites executed all13 declarations and52 bodies (48 parameter cases plus4 standalone bodies). Console recorded16 issues exclusively at the intended false commitment/notImplemented fallback shells. This establishes meaningful RED, not passing feature behavior. Test finalization stalled after the complete body summary. Both exact owned processes (runner66051, host66059) were sampled successfully before signaling. Identity-checked TERM stopped only runner66051; the host drained without a signal. A cleanup poll encountered the transient zombie runner and stopped its identity assertion; the session reaped it, then final ps confirmed both absent. Test exit143 and the unfinalized xcresult are explicit limits. No teardown-only replay was performed. Heavy slot released immediately after drain, before evidence analysis.

Task3 is complete. Actual summary is `task3-red-verification.json`; raw commands, signed host proofs, inventory, logs, samples and local summary remain in `.codex-cache/task3-red-readiness/`. Offline log remains `/Users/arjen/Documents/Codex/2026-10-03/task-4/verification/task3-offline-isolation.log`. Task4 GREEN and further app runs have not started; future heavy execution requires a fresh parent slot grant.


## Task 4: GREEN source checkpoint; runtime verification pending

Task4 is in progress under parent source-only authorization. The batch classifier consumes immutable delivered source evidence and preserves all text, JSON, optional flags and retry fields. Commit advancement requires exact decimal contract version one, scalar-exact tool/key, supported saved identities/revisions, canonical UTC millisecond dates with expiry strictly after completion, accepted true and no non-null contradictory error/retry fields. Supported unsuccessful evidence additionally requires typed error and outcome/accepted/retry consistency; incomplete or contradictory evidence is unavailable. No current clock, domain reread or receipt mutation is used.

The compact generated fallback retains original indexes/operation/tool/key/UUID only; it excludes unbounded item IDs, records and links. MCPBatchTaskPreparedResponse has a private initializer and constructs a usable capability only after the delivered encoder prepares complete correlated modern bytes. It retains fixed context and immutable ready bytes, and selection delegates to the common provider selector with a callback returning those bytes rather than reencoding. Later executor construction must require this capability; no executor is introduced in this task.

Original Task3 test files and 13 declarations /52 cases are unchanged. Separate prepared-response and evidence-boundary suites add eight declarations /32 cases: preparation blocks dispatch, ready encoding precedes effects, post-effect provider/encoder failures select exact bytes without repeating preparation, giant IDs/context stripping and correlation/metadata, adjacent decimal and equivalent numeric versions, normalized invalid dates, opaque scalar identities, and supported versus malformed failure contracts. Focused GREEN inventory is four suites, 21 declarations /84 intended bodies. These supplemental cases are drafted but not executed.

Targeted strict no-cache SwiftLint, Swift frontend syntax parse and git whitespace checks pass. No app build, test or typecheck was executed for Task4. Root independent source review and a new parent exclusive heavy-slot START grant precede signed host preflight, exact inventory and focused GREEN execution. Task4 remains in progress; no later task was started. The prior accepted RED run's exit143/unfinalized result limitation remains unchanged.

Final compatibility review permits absent or explicit null error/retryAction on otherwise valid commitment, preserving saved optional-field distinctions. Non-null contradictory error/direction remains unavailable. Four supplemental cases exercise this boundary without changing the original13/52.

## Task 4: finalized isolated GREEN verified

Parent granted START for reviewed source `85bec71` (implementation `28bee6a`). Configuration guard, private incremental Debug build, signed isolated development host preflight, enumeration and exact four-suite21-declaration inventory all exited0. All21 declarations and84 bodies executed and passed:14 parameterized declarations with77 parameter cases plus7 standalone bodies. Finalized xcresult is Passed, zero failures/issues/skips and empty runtimeWarnings. Original13/52 fixtures remained unchanged; supplemental8/32 exercised exact decimal/date/opaque/null/failure-contract boundaries and the required prepared capability.

Test exit0; owned runner81469 and isolated host drained normally, confirmed by scoped process inspection. Slot immediately released before extraction. No cleanup sample, signal or replay was required. Default sandbox xcresult summary extraction exited64 on its report-cache write; the per-command escalated read/extraction exited0, without rerunning tests. Existing build warnings and the Xcode matching-destination warning remain in raw logs; no zero-console-warning claim. Prior task3 exit143/unfinalized limits remain historical evidence, not overwritten.

Task4 is complete. This delivers pure strict saved-evidence classification, shallow provider-owned fallback and the private prepared-response capability required by later executor construction. Source and supplemental independent review are in `task4-green-review.md`; actual summary in `task4-green-verification.json`. Local command/preflight/inventory/build/test/result/drain evidence remains `.codex-cache/task4-green-readiness/`, with fresh Task4Green result paths and the prior RED preserved. No live writes, client activation, push/merge/deployment or subsequent app job occurred.


## Task 5: request and schema RED draft; runtime execution pending

Parent accepted finalized Task4 GREEN at 011660e and authorized Task5 fixture preparation under the approved DAG. Rune task5/eptphz6 is in progress on sole stream1; Task6 has not started. Read actual request design, requirements, task review, MCPWriteCommand.validate and its existing public operation schemas. Existing Int/Bool helpers already reject Boolean-number/string coercion; standalone metadata validation is object-only, while batch additionally requires string values.

Batch-local MainActor MCPBatchTaskRequest.parse consumes the delivered lossless MCPJSONDocument and declares valid request versus indexed INVALID_INPUT diagnostics. Items retain exact logical original arguments and an existing validated MCPWriteCommand, preserving opaque caller identity and original strings while keeping normalized UUID mapping separate. No service/coordinator/store or admission callback is reachable from parsing. MCPBatchTaskSchema declares a rich input MCPJSONDocument only, with registration deferred to the current shared owner. Both declaration-only methods throw notImplemented; no parsing or schema GREEN semantics have been introduced. These shells permit actual compiled runtime RED instead of absent-symbol failure.

Separate request/schema suites contain 17 declarations /109 intended bodies. Coverage includes 0/1/50/51 bounds, exact explicit mode/operation, closed outer/item/argument fields, indexed usable caller diagnostics, UUID/key/revision safety including newline anchors, strict JSON types and nested metadata values, no-op update, untouched original numeric lexeme and scalar/UTF8 spellings, domain strings/conditional status author shape admission, opaque IDs versus normalized UUID/tool-key collisions and four deterministic shuffled collision plans. A malformed last item admits zero earlier items. Rich schema tests assert closed nested branches, exact public fields/required sets, UUID/key/revision formats, bounded array, domain descriptions without enum/const restrictions, no conditional status-author constraint and add_comment without revision.

All prior84 evidence/encoding fixtures, common source files and coordinator/App/project files remain unchanged. Targeted strict no-cache SwiftLint, Swift syntax parse and whitespace checks pass; full lint is recorded after the draft. No app build, runtime test or typecheck has been run for Task5. Root independent source review and an explicit parent START are required before signed pinned development host preflight, exact17 declaration discovery and actual109 body execution. Source-only checks do not establish meaningful RED or Task5 completion.


Task5 runtime RED is now meaningful and independently cleared. Attempt1 at reviewed1edc6b9 stopped at build65 on one unrelated heterogeneous Any ternary fixture compiler issue, with no host/body execution; its workers drained and all artifacts are preserved. The narrow equivalent switch correction is f428f94. Parent/root explicitly authorized the same focused retry with fresh attempt2 paths, preserving attempt1.

Attempt2 sourcef428f94 passed serial build0, signed isolated development/unit-test preflight0, enumeration0 and exact17 declaration inventory0. All109 bodies ran (105 parameter cases +four standalone); all109 issues were the intended caught notImplemented from parser/schema declaration shells. Root independently counted starts/issues and cleared meaningful RED, with no unrelated runtime issues.

The Xcode runner stalled after bodies, so owned runner93600 and isolated host93608 were sampled successfully before bounded cleanup. Identity-checked TERM went only to runner93600; host93608 drained without any signal. Session89516 exit143 and unfinalized xcresult are explicit limits, not a clean finalized test failure. Final escalated inspection proved no owned workers remain; RELEASE was immediately sent through root before this minimal bookkeeping. No teardown-only replay was performed. Raw attempt2 evidence remains .codex-cache/task5-red-attempt2; structured copy is task5-red-verification.json. Task5 complete; Task6 source awaits continued coordination and has not begun.


## Task6: GREEN source checkpoint; runtime verification pending

Approved Task6/eptphz7 is in progress on sole stream1 after meaningful Task5 RED. The parser accepts a delivered document or its original validated JSON value, before any Any conversion; shared modern routing must bind that raw subtree at coordinated Task14 integration. The entire bounded closed shape, typed fields, safety formats and duplicate item/tool-key/normalized UUID identities are established before a privately constructed request can escape. Exact UTF8 comparison covers structural names as well as opaque caller IDs. Each item preserves its original logical arguments and existing validated MainActor MCPWriteCommand; no model/service/coordinator, key store or receipt access occurs here. Domain strings and conditional status-comment authors remain per-item validation; no-op update and standalone add_comment semantics are preserved.

Integral JSON numbers are validated from decimal mantissa/exponent with checked arithmetic and exact Int range, never Double/Decimal. Fractions rounded toward an integer or underflowing toward zero cannot pass; mathematically equivalent integral spellings retain their original numeric tokens alongside the exact Int bridge. Zero, negative integers and integral scientific notation remain allowed shapes, with no new positivity restriction.

The schema derives field types/required safety from actual nonisolated protected core definitions and emits a feature-local rich MCPJSONDocument; it closes outer/item/argument objects, bounds items1...50, fixes mode/operation discriminators and UUID/key/revision formats, describes actual captured enum values without applying enum/const to domain strings, and constrains metadata values to strings. Shared registration/transport files are untouched.

Metadata names that would collapse in Swift's canonical-equivalent String dictionaries are rejected as indexed whole-input INVALID_INPUT before command construction. This mirrors the delivered latest-only MCPModernWire.requestValue representability check (a8fcc715): its UnsupportedArguments sentinel is rejected by modern preflight as RPC invalidParams/-32602 before protected key admission, rather than an item-domain failure. This is inherited bridge compatibility, not a new transport policy or historical receipt rewrite; the original document is unchanged. Raw structural duplicate guards remain active on the value overload.

Original Task5 17declarations/109cases and earlier84 evidence/encoding cases are unchanged. Separate RequestBoundaryTests add4declarations/23cases:15 exact numeric edges,2 metadata representability cases,3 scalar-exact structural names and3 raw duplicate positions. Focused GREEN inventory is three suites21declarations/132bodies. Root independent source critic cleared parser/schema/private construction, actor-safe captured definitions and supplemental scope. Targeted strict no-cache lint, Swift syntax parse, whitespace and full make lint pass; no Task6 app build, typecheck or runtime job has run. Task6 remains in progress until signed source-pinned host/exact inventory and actual GREEN after parent slot grant. T1734 currently owns heavy slot; Task7 has not started.


Task6 focused GREEN is now finalized and independently cleared. Parent START pinned reviewed5066a06/source565c336; source/owned/protected/artifact hashes and fresh paths verified, with no source changes during the job. Serial isolated build0, signed development/unit-test host preflight0, enumeration0 and exact three-suite21 declaration inventory0 all passed. Actual finalized Task6Green.xcresult reports132 cases passed (128 runs across17 parameterized declarations plusfour standalone), zero failures/skips/expected failures and no runtime warnings. Test job session5411 exited0 normally, with no fixture correction, rerun, signal or cleanup. Root independently confirmed console21/132/no issues.

Final escalated process inspection showed no owned runner/host/build workers. RELEASE was sent immediately before off-slot readonly xcresult extraction; result finalized normally, unlike the separately preserved RED teardown limitations. Task6 complete. Raw commands/logs/signed host proof/exact inventory/unchanged fixture hashes/finalized summary remain .codex-cache/task6-green-readiness; structured result is task6-green-verification.json. Shared routing/raw argument binding, actual batch execution and later preview tasks remain outside this checkpoint. Task7 has not started and requires root Rune retrieval/delegation; no live writes, activation or extra app jobs occurred.
