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


## RED draft readiness

Isolated stream1 draft `498d515` (afterd255562) contains JSON document/source properties plus seeded fixture/shrinker; stream2 draft `a928cb7` (after26f4dda) contains protocol/discovery fixtures. Both pass parse, targeted no-cache lint and standalone Swift Testing typecheck against pure declarations. Neither focused app test has run; task2/task12 remain in progress on their own branches. Commands queued through parent:

```sh
# results-stream-1
make test-quick TEST_TARGETS='TransitTests/MCPJSONDocumentTests TransitTests/MCPResultSourceTests'
# results-stream-2
make test-quick TEST_TARGETS='TransitTests/MCPModernProtocolTests TransitTests/MCPModernDiscoveryTests'
```

Source fixture review distinguishes decoded Unicode scalar key sequences from Swift canonical-equivalence; same-scalar escaped/literal duplicate keys still reject. Protocol duplicate metadata fixture uses withoutEscapingSlashes so its mutation actually creates duplicate keys. Depth resource-cap decision is pending owner; no assertion/production limit assumed.

T2384 identified a compact-fallback constraint: recovery context must not reintroduce giant itemId/raw records/link data into the provider's prepared serialization_failed fallback. Encoder RED6 must include synthetic giant itemId and enforce only original indexes/tool/key/UUID plus bounded diagnostics in prepared fallback presentation. Normal aggregate evidence remains complete. API delivery15 remains pending.


## Nesting measurement for owner decision

Read-only review counts JSON objects/arrays with rootcontainer1; scalars and JSON inside strings count0. Source-defined constructed shapes (not captured live responses):

| Shape | Logical source | Structured wrapper | Full RPC |
| --- | --- | --- | --- |
| Full task/comments | 3 | 5 | 7 |
| Protected full-task receipt | 4 | 6 | 8 |
| Ordinary query page | 5 | 7 | 9 |
| Selector page results/task | 6 | 8 | 10 |
| Prospective batch original receipt | 8 | 10 | 12 |

Shape authorities: MCPRecordSnapshot.swift97, MCPWriteCommand.swift261, MCPToolHandler+TaskQuery.swift86/144, TransitTask.swift49, T2384 approved design89. An independent scan parsed54 noninterpolated literals in existing MCP test sources, maximum4 (mostly requests, not a response maximum). Generated schema module remains declaration-only, so actual output schema depth is not yet measurable. Task metadata is a String:String map; arbitrary historical fields/extensions can nest without a semantic maximum. Proposed parser-input cap64 gives headroom, but remains an owner decision with explicit retained-source preservation amendment. No limit adopted at this checkpoint.


Owner approved32 (not512/64) at Sentinel_9536d4df532c81919792e70801f128fb; requirements/design/decision log amended explicitly. Source baselineRED2 complete8f9c4ce integrated locally with root task13->3 dependency preserved. Added31/32/33/wide-array cap assertions are being drafted for a separately granted RED refinement; no capGREEN claim. Protocol initial invocation failed before compile at package-resolution DNS (xcode74); same focused command is retrying once via per-command escalation for normal dependencies. That environmental failure is not RED evidence.


## Baseline RED integration

Local sub-branch integration explicitly approved at Sentinel_eafda56391a48191a3c414fef34d1307. Source baseline2 integrated from8f9c4ce: build/launch succeeded,16 declarations15failed1passed (42 expandedruns), all implementation failures notImplemented or exactexpectederror mismatch; independent shrinker passed. Protocol12 integrated fromdb8173c:22 functions/36 runs all failed solelynotImplemented, no fixture/compiler failures. Its initial sandbox-DNS invocation ranzero tests; the single escalated same-command retry produced actual behavioral evidence. Both focused pipelines drained and the exclusive short slot was released. Parent has both classifications. Rune now has1/2/12 complete;3 is the only ready stream task,13 correctly waits3.

Cap RED amendment128823d remains in isolated stream1 pending exactshortslot grant; no GREEN app run. Source/parser3 and commonAPI15 remain undelivered. No shared MCP/coordinator/Reads edits, client activation, push, main merge or deployment occurred.


Integrated `make lint` passed host guards and409 Swift files with0 violations; log `/tmp/t2383-integrated-red-lint.log`. User-requested phone helper ran from the clean ticket worktree and exited0, transferring13 changed Markdown documents including the approved nesting amendment and source/protocol RED evidence; log `/tmp/t2383-implementation-phone.log`. Transfer success does not establish that the user opened/read them. Cap RED refinement128823d is ready in stream1 awaiting an explicit next shortslot grant; no heavy process or GREEN runtime implementation is active.


## Approved cap RED execution

Parent granted exclusive source CAPRED128823d after T2384 GREEN drained. Exact same focused source command compiled and executed; make2/xcode65,23 declarations22failed1passed (50 expandedruns49failed1passed). New31/32/33/wide/retained/checkpoint cases fail against notImplemented as expected; independent shrinker passes. Evidenceed9f2fb integrated into the ticket branch, preserving owner requirements amendment and corrected task dependency. Heavy pipeline drained/released promptly to T63 repair; no GREEN app run in that grant.

Parent authorised source/parser3 GREEN source drafting while its focused GREEN test slot remains pending. Compiler-required escaping Sendable checkpoint facade may retain the callback only within synchronous parser lifetime, never within returned document/source/fragments; no renewal of original deadline. Task3 remains incomplete and API15 undelivered until their actual gates pass.


## Source GREEN3 delivered

Focused31bc425 source command firstattempt passed23declarations/50expandedruns, make0; unchanged baseline/cap RED fixtures. Pipeline/testhost drained and slot released. Critic found no grammar blocker, but required private source initializer. Final0a93930 access-only change passed negativeexternalconstructor compile (expectedprivate-access diagnostic) and full puremodule/unchangedTestingfixture typecheck/lint; it changes construction access, not runtime factory logic. No app run at0a93930 is claimed. Integrateddf3c23b, resolving expected task-status conflict to verified3complete while preserving12complete and13->3 edge.

Next ready streams4/13 drafted in fresh isolated worktrees `presentation-stream-1`/`protocol-green-stream-2` fromdf3c23b. Prior worktrees/artifacts retained for review. No heavy slot held while drafting, no commonAPI15 delivery.

## Presentation RED4 verified

Source-shape audit before execution corrected fixtures to public taskId/projectId rather than internal covered id, and added actual selector results[index].task plus retained pre-pagination root-array cases. Readiness99f8cbc passed parse/lint/pure fixture typecheck. First reservation was released unstarted for the parent's Asterism baseline; no app job ran during that quiet window. After pause ended and both suites were confirmed ready, parent granted sequential presentation/protocol RED only.

Presentation command at99f8cbc compiled/launched and produced meaningful RED:20 declarations/48 expanded runs all failed against notImplemented, make2/underlying65, no malformed fixture/build/launch failure. Seeded invariant/shrinking remains unexercised because the placeholder throws before those assertions; unchanged GREEN must execute it. Final evidence55116ca integrated into the ticket branch; task4 complete, task5 not implemented. Pipeline drained before protocol supplemental RED started; no GREEN or extra app run in this grant. See presentation-red.md for preserved artifacts/classification.

## Protocol supplemental RED and next source work

Atcf900ad the validator was restored exactly to817a80a, with the prepared correction preserved separately by SHA. Focused supplemental RED compiled/launched:26 functions24passed/2failed,40 runs38passed/2failed, no skips; all22 original functions passed. Depth32 passes, valid depth33 is wrongly classified as invalid JSON (-32700) instead of an invalid request/resource bound (-32600). Out-of-range/nonintegral numeric IDs reject but omit required string-ID guidance. Exact numeric bounds, decimal/exponent/giant-zero cases and width/body cases pass. Evidence9b2cef3 was integrated as documentation only; unverified protocol source remains isolated and task13 incomplete.

Both app pipelines drained; slot released promptly before Asterism after measurement. All CPU-heavy work paused until the parent confirmed quiet completion. Source-only task5 drafting and task13 correction now resume in existing isolated streams; lightweight parse/lint/typecheck are permitted, but no application build/test grant follows from the quiet pause ending. CommonAPI15 remains undelivered.

Protocol3cfd28a fixes the demonstrated resource/ID diagnostic failures and passes lightweight checks, but its GREEN readiness was withdrawn after internal critic found subscription filter and Mcp-Name validation defects. Current primary specification confirms resourceSubscriptions is a string array and unsupported types are omitted from acknowledgement; plain padded names require Base64, and sentinel recognition requires both exact markers. New focused RED fixtures precede those fixes. See [subscriptions](https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/subscriptions) and [HTTP value encoding](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http#value-encoding). No additional app run or completion claim.

An initially inferred direct-discovery null-ID defect was withdrawn after checking actual MCPTypes: JSONRPCId has only string/integer cases and the public helper requires it nonoptionally. No shared type expansion, guard or redundant fixture is needed; existing request validator null-ID rejection remains tested. This correction is not a new protocol policy.

From clean0dfeed2, the requested phone helper exited0 and sent16 branch-changed Markdown documents, including sourceGREEN/presentationRED/protocol supplemental evidence. Log: /tmp/t2383-red-checkpoint-phone.log. Transfer does not establish that the user opened the documents.

## Critic RED verified; focused execution approval blocked

Protocol366a1ad against unchanged3cfd28a compiled/launched:30 functions27passed/3failed;44 runs41passed/3failed, no skips. All previous26 functions and malformed resource-array control pass. Valid mixed resourceSubscriptions array rejects incorrectly, padded plain name accepts incorrectly, prefix-only sentinel rejects incorrectly. The full sentinel literal's outer encoding assertion was not reached after the prefix-only failure, so no pass is claimed. Pipeline drained/released; evidence52fea71 integrated as documentation only. Revised sourceb6b616e passes lightweight checks and targeted internal critic review; all30 fixtures unchanged, application GREEN pending, task13 incomplete.

Presentation supplemental fixtures391c159 preserve runtime1652913 and await execution. The granted focused command did not launch: automatic approval review rejected require_escalated because it treated the delegated slot grant as insufficient to override the original spec-phase heavy-build/test restriction. No process/session, retry, alternative execution path, global permission change or runtime repair followed. Parent notified, unstarted slot released, and actual owner authorisation is being resolved through the parent. This is an execution-authority blocker, not RED evidence. Task5 and commonAPI15 remain incomplete.

## Owner-authorised presentation supplemental RED

Explicit owner approval Sentinel_f061180ea7608191b7f8e54205bfdb00 authorised the exact focused presentation command with per-command escalation. One unchanged retry was accepted, with no evidence added to tool arguments or alternate invocation. At391c159 against runtime1652913, build/test launch succeeded:25 declarations23passed/2failed;55 runs51passed/4failed. All20 original declarations/48 runs pass, including seeded presentation properties. New3 controls pass and4 cases expose missing milestone project references and known complete terminal-rejection retry precedence. No compiler/fixture/launch fault; runtime unchanged, pipeline drained and slot released promptly. Evidencee3b37e3 is copied into the ticket as documentation only; task5 source repairs continue isolated and no GREEN is claimed.

Protocolb6b616e remains source-review-cleared and ready, but parent reports its GREEN delegation was rejected for missing explicit exact-suite approval. Parent requested bundled local build/lint/unit-simulator/escalation authorisation at Sentinel_8870ee330e108191b769af5f8b659855; reply pending. No protocol GREEN attempt, workaround or active heavy reservation; client activation is a separate gate. Presentation repair/lightwork may continue, while app execution waits for owner evidence and a coordinated slot.

Presentation revised sourcef4bd03a fixes the demonstrated milestone-link and terminal-rejection recovery gaps and checkpoints project-position generation before allocation/every64 entries. All25 declarations/55 runs' fixtures remain byte-unchanged391c159. Parse/lint/pure typecheck passed; targeted internal critic found no new blocker. Presentation5 and protocol13 are both source-review-cleared READY drafts in isolated streams, pending separately granted application GREEN; neither runtime draft is integrated or marked complete, and commonAPI15 remains undelivered. No active app job or heavy reservation.

## Live mutation pause and read-only duplicate observation

Parent paused all live Transit mutations/status/comments after the owner observed duplicate records. No live T2383 mutation occurred during these local source/test iterations. Last recorded write remains the protected implementation status/comment at2026-10-03T11:08:23.475Z, key T2383.implementation-approved.20261003, UUID E46FCBBA-31BA-4C53-AD13-C3A4E3209819, committed historical revision r1:98d5c0bb10c440984383379166f4c98391519018e7c1bc694a12fcc8af04bd62. Earlier scope status/comment was09:09:18.822Z, key T2383.scope-approved.spec.20261003. Historical receipt evidence is unchanged; no replay/mutation retry or guard reset follows this observation.

Using the actual running legacy query_tasks schema, read-only displayId2383 returns Duplicate task identifier detected for displayId 2383. Exact title search Return structured MCP results and navigable links returns two rows with the same UUID and displayId:

| Status | Project fields | Last status change | Observed revision |
| --- | --- | --- | --- |
| in-progress | projectId/projectName absent (not JSON null) | 2026-10-03T11:08:23Z | r1:10dc24ef6faf70f905c7fb87a8caa608907fa7ad727eb1ab6b65370850904ee7 |
| spec | projectId8491AAC4-CC6C-498C-B93D-99DD68424226, projectNameTransit | 2026-10-03T09:09:18Z | r1:7dba5935bf1f6055203ae0a0c5fdcd1546386144f8bd7e2c9733b6f504ee95ea |

Both rows report comment UUIDs C61251A5-E503-46A6-9B6C-3011C9422E30 and4C9688F8-1B48-451B-BBAD-975E538C563D with the same comment creation/revision values. This is observation, not a cause or repair conclusion. No task/project deletion, merge, reassignment, settings change or production activation occurred. Selected Results/Protocol tests are pure; TransitApp's unit-test-host source selects an in-memory/CloudKit.none configuration and skips the MCP server, but that source inspection alone does not establish the duplicate cause.

The phone helper from clean95b0d30 exited0 and sent17 Markdown documents including supplemental RED evidence; log /tmp/t2383-supplemental-red-phone.log. No user-open claim.
