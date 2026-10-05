# Task 7 saved-only preview RED source review

Reviewed source: `46363eecd2a929d452297c1abd851cf188efa278`, based on finalized Task 6 `6eae0f30e82263a337d078367463d9419c4587f9`. Internal independent root critic review; the implementation child drafted the source. No external peer service or disclosure was used.

Disposition: source preparation is ready for the exact focused RED run after parent exclusive START. Task 7 remains in progress. This is neither a runtime RED result nor Task 8 implementation authority.

## Boundary and parity findings

- `CommentInputValidation` is a cross-platform pure value declaration. MCP status validation and saved preview remain MainActor; only immutable Sendable JSON/value results leave the boundary. All three new behavior methods explicitly throw `notImplemented`. Existing service and protected-command behavior is unchanged.
- The preview takes only the container, persistence state and saved-read seams. It has no write-coordinator, reservation, receipt or mutation-service dependency. Its descriptor hooks expose task/comment/milestone `includePendingChanges` checks and private-context autosave/no-changes checks. The later implementation must set pending exclusion itself, including milestone descriptors; the fixture never silently repairs a descriptor.
- Owning persistent fixtures use CloudKit-disabled temporary stores and independently reopen them. They compare canonical covered task/comment/milestone fields, including dates and identities, and six entity counts; pending task/comment/milestone insert/edit/delete objects and original shared autosave settings are checked after both normal and failed-read paths. Deferred verification reports readback exceptions rather than swallowing them. A marker and absent receipts supplement these checks without constructing any coordinator or sidecar.
- Tests require every mixed item to receive an ordered valid/invalid/unavailable outcome. UUID cardinality, task/comment/milestone fetch failures, an empty-comment read failure, persistence fallback and revision conflicts stay distinct. Full saved comments contribute to canonical r1 before projection; later independently saved comment evidence invalidates an earlier preview. The actual protected error code is `REVISION_CONFLICT`.
- Pure and integrated status cases retain conditional author semantics: invalid status precedes author validation; any supplied comment requires a nonblank author even when its content is blank; absent comments ignore unused blank authors. Same-status comments do not produce timestamp transitions. Real transitions describe last-status/completion actions symbolically, including terminal-to-terminal and leaving-terminal behavior.
- Comment trimming and distinct content/author errors, task description trim/clear, metadata clear, and milestone clear/display/name precedence are grounded in actual protected/service validators. Normalized proposed effects contain no generated comment identity, commit timestamp or display ID. The static effect guard is supplemental source evidence; it is not a global runtime interception claim.

## Verification and exact run contract

Independent root checks confirmed all six source/test hashes, exact changed-file boundary, and unchanged protected service/command/coordinator/App/project/Makefile source. Earlier parser/schema and evidence/fallback fixtures remain unchanged. Source declaration names match the readiness inventory:

| Suite | Declarations | Intended cases |
| --- | ---: | ---: |
| MCPBatchTaskPreviewTests | 15 | 33 |
| MCPTaskMutationValidationTests | 6 | 20 |
| MCPTaskMutationBaselineTests | 4 | 15 |
| Total | 25 | 68 |

Targeted strict lint, syntax parse, full repository lint (444 Swift files) and staged whitespace checks returned 0. Syntax parse is not typechecking. No app build, signed-host launch, enumeration or runtime test was executed in this task preparation.

The `.codex-cache/task7-red-readiness` package specifies serial private incremental Debug build, fresh `Task7RedBuild.xcresult`, freshly verified signed isolated unit-test host and `T2384Task7Red.xctestrun`, exact 25-declaration enumeration, then only the three suites above with fresh `Task7Red.xcresult`. Config/source/hash/signature/inventory failures block launch. Old results are preserved. Expected runtime evidence is 53 failures at the explicit new placeholder boundaries and 15 independently passing existing-service/protected-command controls. Compiler failures, zero-match success or unrelated runtime failures do not establish meaningful RED.

Before Task 8 proceeds, answer with actual result evidence: Did all 68 cases execute with the intended 53-placeholder/15-control split? Did saved-read/pending-state checks stay clear, including failure continuations? Did the owned runner/host/build workers drain, and was RELEASE reported before extended extraction? If teardown is abnormal, record attempts, signals and artifact finalization separately; do not turn it into a clean-exit claim.

T2383 retains the next heavy priority. No new feature approval gate is introduced; the remaining scheduling prerequisite is the parent's explicit exclusive slot START. Shared result/transport wiring and coordinator ownership are unchanged.
