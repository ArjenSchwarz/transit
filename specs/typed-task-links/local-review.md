# T-1734 final local review

## Verdict and provenance

Ready for publication review. All 22 tasks and all 39 acceptance criteria in the approved local scope are implemented; no mandatory fix remains. Final application/test source is `bbe3a2560584f7fb822aa8006b20f08d22284ce4`, based on freshly verified `origin/main` `e04c1268ee37bd4ae925d4d686954cf2121005c7`. Review covered the full branch at cf33cb25 plus corrective deltas through 81f78e7 and the five-file native delta at bbe3a25. Later documentation commits do not change the tested application/test/Makefile content.

The pre-push-review skill supplied four independent read-only perspectives: reuse, code quality, efficiency, and specification/documentation. Root also reviewed the actual runtime failures, corrections and final native result trees. The pre-push peer reviews were internal. The subsequent PR Pilot workflow publishes this branch diff to GitHub and its configured Claude action under owner approval. The original worktrees, historical evidence and canonical `.kiro` remain preserved.

## Findings and resolutions

| Finding | Outcome |
| --- | --- |
| Advertised schema named nonexistent `batch_task_mutations` | Fixed to shipped `mutate_tasks`; caller contract and wire guidance agree. |
| Graph refetched task population before selected serialization | Fixed by reusing the already fetched complete population inside the capture fence. Original selected malformed-canonical assertion is unchanged and passes. |
| Five legacy project/milestone error surfaces were bypassed | Restored discarded compatibility checks in capture validation order; successful live model values never select returned records. |
| Eight old read fixtures seeded only pending/mock values | Explicitly inserted/saved only intended read seeds; every original assertion, cursor/fetch-count check and dirty-write helper remains intact. |
| Project shape validation could lose precedence to a storage hook | Fixed using the existing extracted selector parser before the hook, with newline normalization. Three actual handler controls assert zero hook calls and exact expected outcomes. |
| Duplicate status catalog, unused apply parameter, repeated preparation scaffolding | Optional low-severity maintenance suggestions; current behavior agrees and cleanup is not required for this feature. |
| Global diagnostic scans | Optional bounded optimization opportunity; existing deadlines/caps remain intact. |
| Native refresh bursts and incoming attribution/duplicate wording | Fixed at bbe3a25: invalidation precedes cancellable 100-ms notification wait; provider/publication guards preserve full saved graph freshness. Incoming labels are Introduces / Duplicated by; association and unknown raw kinds retain their meaning. |

The initial full macOS run's 14 failures and all compile/invocation-only attempts remain preserved. Focused corrective verification passed 170 cases before the final full runs. No test expectation, capacity cap, retry guarantee or unsaved-data policy was relaxed.

## Final verification and evidence

| Platform | Expanded case executions | Native declarations | Outcome |
| --- | --- | --- | --- |
| macOS units | 3,265 passed; five intentional skips | 2,530 passed; five skipped | build/run 0; no timeout; host drained |
| iOS units | 1,403 passed | 1,326 passed | build/run 0; no timeout; host drained |
| iOS UI | 26 passed | 23 passed | unchanged signed products; run 0; no timeout; all hosts drained |

Aggregate: 4,694 passing case executions across final platform runs at bbe3a25, zero failures. Runtime warning arrays are empty. Root independently parsed summary/tree leaf outcomes and exit/drain records. Full lint passed 652 files with zero violations; ownership, create-schema, development configuration and final registration guards passed. Build warnings are pre-existing and retained in the handoff.

The five macOS skips are the two opt-in primitive diagnostics, process-separated closed-store stage, development schema precheck and outside-writer observation. Their earlier targeted evidence or explicit deferral remains separately recorded. The current final iOS run recovered two first-attempt census timeouts with bounded diagnostic retries, retaining the original absolute deadline, ownership checks and fail-closed non-timeout errors. All owned simulators were shut down/deleted. See [pr254-native-corrections.md](pr254-native-corrections.md) for current artifact roots, pins and counts; [final-handoff.md](final-handoff.md) preserves the earlier source separately.

Generic JUnit/coverage data is unavailable: the review ecosystem only detects SwiftPM through a root Package.swift, while this is an Xcode project. No unrelated SwiftPM recipe was executed and no coverage or JUnit was fabricated. Actual native xcresult evidence establishes the platform outcomes above.

## Final critic questions — closed

1. Is published caller guidance accurate? Yes: `mutate_tasks` is the batch tool; link directives remain standalone-only and batches reject them before item/key acceptance.
2. Are final gates evidenced at the actual source? Yes: the original focused compatibility checks passed at 81f78e7, and fresh native focused/build/lint/guard/full-platform checks passed at bbe3a25; later changes are documentation only.
3. Are concurrency and native observation claims truthful? Yes: participating owned local saving is implemented; independent containers/imports can race. Native saved value projection/cancellation is distinct from a fenced retained MCP capture. There is no certified inter-fetch native coherence claim or global CloudKit atomicity claim.
4. Are deferred product boundaries preserved? Yes: live CloudKit verification remains T-2402 and consolidation remains T-2381. Installed-client activation/production promotion is not performed by this local implementation.

## Acceptance-criterion traceability

The independent specification review mapped all 39 criteria to production symbols and behavioral fixtures. The table below preserves that mapping; its formerly pending final checks are now established by the outcomes above.

| AC | Implementation / verification evidence | Assessment |
| --- | --- | --- |
| 1.1 | TaskLinkType, TaskLinkWireRequest closed parser; WireTests exact public spellings, malformed shapes, self-link rejection | Implemented |
| 1.2 | QueryProjection public orientation and QueryBoundaryTests both saved endpoints; native Incoming/Outgoing labels | Implemented |
| 1.3 | Normalized TaskLinkRelation and Plan.validate; inverse/association normalization, already-present no-op, incompatible remove/add, physical multiplicity tests | Implemented |
| 1.4 | OwnedPlan source/endpoint UUID uniqueness and graph all-matches indices; missing/colliding identities, foreign graph closure and cross-project integration controls | Implemented |
| 1.5 | QueryProjection edge UUID/stored endpoints/type/direction/observed label/physical identity; native saved labels | Implemented |
| 2.1 | GraphIndex.assessment direct Done-only blockers and complete evidence; GraphTests Done/Abandoned/unknown status | Implemented |
| 2.2 | Complete proposed graph validation and iterative dependency SCC; PlanTests cycle-closing rejection | Implemented |
| 2.3 | Cycle membership includes physical dependency rows; invalid direct evidence; doneBlockerDoesNotPropagateItsBadAncestry | Implemented |
| 2.4 | Frozen graph retained in capture; QueryBoundaryTests actual modern cursor after endpoint/incidence edits; no duplicate alias traversal | Implemented |
| 3.1 | Separate stored attribution/association kinds; mixed field/link integration tests preserve independent task field authority | Implemented |
| 3.2 | Complete proposed duplicate graph and at-most-one outgoing validation; cardinality and same-request retarget tests | Implemented |
| 3.3 | DuplicateResolution ordered source-to-terminal path/canonical UUID; chain and terminal-state graph fixtures | Implemented |
| 3.4 | DuplicateResolution missing/ambiguous/cardinality/cycle/invalid occurrence diagnostics; acquisition errors throw | Implemented |
| 3.5 | Scalar edges, no redirects/flattening/task closure; incomingDuplicateVisibilityDoesNotRedirectOrdinaryTaskIdentity and protected integration | Implemented |
| 4.1 | Closed wire directives, max50, creation additions-only, exact edge/l1 identity; WireTests and precise repair fixtures | Implemented |
| 4.2 | OwnedPlan validates source/current endpoint snapshots and full proposed graph immediately before synchronous apply; source/endpoint preparation-race and exact affected-guard tests | Implemented within approved participating boundary |
| 4.3 | TaskLinkOwnedApply stages in retained sealed context before terminal snapshot/receipt save; OwnedPhase/OwnedScope/WriteIntegration save and encode failure controls | Implemented |
| 4.4 | Existing coordinator receipt binding/replay retained; dirty retained replay, exact full binding matrix, retained bytes after incidence edits, foundation recovery tests | Implemented |
| 4.5 | Clean shared-context checks before acceptance and after preparation success/error; fresh owned context; pending draft and safe replay controls | Implemented |
| 4.6 | Capability guard, existing protected tool dispatch/durable-store restrictions and recovery outcomes; no reset/deletion API introduced | Implemented |
| 5.1 | Required explicit incidence input, canonical physical tuples plus empty linkContract, current revisionCoverage; RevisionTests old tokens, no-link property/status conflict, labels/removal exclusion | Implemented |
| 5.2 | Exact active row deletion + separate immutable evidence; fresh re-add UUID; exact fresh-key no-op; expiry/content-token stability tests | Implemented |
| 5.3 | Graph missing/ambiguous endpoint diagnostics; exact dangling repair without nonexistent guard; physical edge selector collision rejects | Implemented |
| 5.4 | All physical multiplicity/raw rows retained; exact removal-only repair preserves other rows and unrelated corruption; matching invalid removal evidence remains conflict | Implemented |
| 5.5 | Caller contract explicitly excludes independent writers/import atomicity; allowed outside-writer observations and later available graph diagnostics; valid status assessment is not called historical race | Implemented within ADR4 |
| 5.6 | Additive scalar models in schema parity audit; process-separated closed legacy store upgrade/reopen; explicit legacy nil incidence/missing graph coverage; historic receipt replay bytes unchanged | Implemented locally; live CloudKit deferred |
| 6.1 | TaskLinkQueryOptions conjunctive valid-type/orientation/target/unblocked predicates before ordering/page; ordinary/query boundary fixtures; reusable graph options rejected | Implemented |
| 6.2 | Full links/diagnostics/resolution/blockers and explicit graphCoverage; omitted bodies preserve covered token; missing graph null/unavailable fixture | Implemented |
| 6.3 | MCPReadCaptureBuilder fresh saved context and history/generation fence wraps task/graph/comment capture; draft exclusion and fetch failures; default handler uses saved capture | Implemented for covered MCP queries |
| 6.4 | Frozen retained graph and fixed selected membership; cross-project closure excluded from selectable scope/totals; reusable rejection and retained byte/index accounting fixtures | Implemented |
| 6.5 | Original operation deadline threaded through graph/capture/body picker/filter/encoding; repeated-identity stop; deadline/capacity/publication and existing read-service limit tests | Implemented; final platform checks passed |
| 6.6 | Original retained metadata and modern frozen payload parity; no guessed navigation URLs; modern actual cursor test | Implemented |
| 7.1 | Saved native DTO, TaskLinksSection and source-relative TaskLinkNativeLabels in existing native detail patterns; source/endpoint draft exclusion and actual UI diagnostic fixtures | Implemented |
| 7.2 | Saved unique destination at click and TaskDetailWindowView resolver; nil for missing/ambiguous/unsaved/pending-delete; actual iOS UUID navigation UI test | Implemented |
| 7.3 | Existing field/status/comment paths use new current coverage; batch parser removes/rejects link fields before keys; real foundation batch/portfolio integration | Implemented |
| 7.4 | Write/result contracts and input schema describe normalizations/guards/no-op/expiry/coverage/history/local boundary | Implemented; tool-name correction verified |
| 8.1 | Graph/Generated/Plan/Wire/Write suites cover public directions, multiplicity, seeded independent SCC reference, repair and duplicate cases | Appropriate behavioral tests present |
| 8.2 | Participating/Protected/OwnedScope/OwnedPhase suites exercise dirty contexts, source/endpoint races, all-or-none domain/receipt, replay binding, uncertainty; historical independent-writer counterexamples retained | Appropriate behavioral tests present |
| 8.3 | Migration/ReadCaptureBoundary/QueryBoundary/RemovalEvidence/Native/Foundation suites cover lifecycle integration; actual UI source pins and lost-exit limitation documented honestly | Appropriate tests present; final platform evidence passed |


## Local review artifact

The standard review renderer generated the complete branch diff and blast-radius artifact from landed base e04. `pulsar publish` validated its metadata and archived the HTML locally at `/Users/arjen/CodeReviews/2026-10/2026-10-05-github-transit-branch-t-1734-typed-task-links-final.html` (exit 0). This operation moved a local file; it did not push source, publish a PR or contact an external reviewer. Review inputs and four peer reports remain at `/tmp/t1734-final-review.qjczlb7m`.

## PR #254 corrective review and verification

Configured Claude reviews posted at remote heads 452e3d3 and 0714ce01; both explicitly disclosed limited inspection and no independent execution. Root validated every suggestion through the PR Review Fixer overview comments. The second review's merge recommendations led to the native five-file correction at bbe3a25. All four internal reviewers independently inspected that exact delta with no mandatory finding; prior native assertions remain unchanged. Ten label contracts and two burst/cancelled-start controls join the existing eight focused native cases, all 20 passing. Complete macOS, iOS unit and iOS UI suites were rerun at the revised source; root independently parsed trees, exit and cleanup records into `/tmp/t1734-final-review.qjczlb7m/root-audit-bbe3a25.json`.

CLAUDE.md's directory map and the CHANGELOG's MCP-only authoring statement are corrected. The entity count was already eight; all schema registrations remain verified. Literal centralisation, encoder reuse, narrower/off-actor pure-value projection and display polish are optional follow-ups, without relaxing full graph closure or unknown-kind diagnostics. Production CloudKit promotion remains blocked on T-2402's deferred live verification; this PR workflow authorises repository merge only. There are no live task-record, CloudKit or client-setting changes.
