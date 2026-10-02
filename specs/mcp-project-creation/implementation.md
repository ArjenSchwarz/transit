# T-2377 implementation and validation

Branch: `T-2377/mcp-project-creation`, based on `origin/main` merge base `3c2c6c8`. Isolated checkout: `/Users/arjen/Documents/Codex/2026-10-02/task-2/transit`. Changes remain uncommitted. No push, publication, merge, deployment or global toolchain change. Original checkout's unrelated `.kiro/` remains untouched.

## Implemented

- Core create_project schema/dispatch: required name/colorHex; optional description/gitRepo; strict strings and whole-string ASCII hex validation; ProjectService-backed trimmed-name uniqueness and persistence; UUID and project metadata usable by create_task.
- Shared metadata formatting with get_projects, preserving milestone enrichment; fallback storage mutation rejection.
- Contract/rejection/persistence/metadata/project-to-task tests, updated inventory tests; README, CLAUDE, MCP docs and feature spec.
- User-authorised Xcode 27 / Swift 6.4 support: only AsyncAlgorithms pin changes to released 1.1.3 (`9d349bcc328ac3c31ce40e746b5882742a0d1272`). Other pins and deployment targets are unchanged; no dependency-cache patches remain.
- CounterSnapshot is nonisolated and checked Sendable; async CounterStore is nonisolated and Sendable. Production CloudKitCounterStore retains MainActor isolation. Two shared counter actors move identical conformances to empty extensions; bodies, executors, allocation gate, retries and compare-and-swap behavior stay unchanged.
- Host source-literal assertion migrates from an app unit test to `tests/validation/create_task_project_schema_guard.py`, preserving marker/constraint/negative assertions. It runs before lint, test-quick, test and test-ui. Cross-platform runtime intent-description checks remain. This supersedes the temporary macOS-only source guard, because GUI-launched macOS tests also block on host-file opening.

## Final verification

| Check | Result |
|---|---|
| make lint | Passed ownership guard, source-literal guard and strict SwiftLint: 364 files, zero violations. `.codex-cache/t2377/final-lint.log`. |
| CLI source guard fixtures | Valid fixture passes; missing marker, missing end, missing project constraint and optional project identifier all reject. |
| git diff --check | Passed. |
| Xcode MCP iOS BuildProject, buildForTesting=true | Passed with conformance-extension fix; 21.291s, no errors. `.codex-cache/t2377/mcp-extension-conformance-build.json`. |
| Xcode MCP full iOS simulator unit/UI run | Fresh xcresult **1291 total, 1291 passed, 0 failed, 0 skipped**: 1270 unit tests and 21 UI tests. `.codex-cache/t2377/final-ios-xcresult-summary.json`; bundle `/var/folders/11/v0tnfm294kd9c6zll_ncmpkh0000gn/T/ActionArtifacts/default/RunAllTests/Test-Transit-2026.10.02_17-55-17-+1000.xcresult`. |
| Final Xcode MCP macOS BuildProject, buildForTesting=true | Passed after CLI guard migration; 16.183s, no errors. `.codex-cache/t2377/mcp-build-cli-guard-mac.json`. |
| Final Xcode MCP macOS full TransitTests selection | Fresh xcresult **1823 total, 1823 passed, 0 failed, 0 skipped**, including MCPCreateProjectTests and actor allocation/cancellation/gating suites. `.codex-cache/t2377/final-mac-xcresult-summary.json`; bundle `/var/folders/11/v0tnfm294kd9c6zll_ncmpkh0000gn/T/ActionArtifacts/default/RunSomeTests/Test-Transit-2026.10.02_18-20-15-+1000.xcresult`. The former 1824th source guard is now a separately passing CLI assertion, not a skipped app test. |
| Earlier make build | Passed both iOS/macOS with final production code and AsyncAlgorithms 1.1.3. `.codex-cache/t2377/xcode27-build.log`. |
| Earlier make test-quick XCBEAUTIFY= | Passed 1824 macOS tests before source-guard migration, 0 failed/skipped. `.codex-cache/t2377/xcode27-fixture-raw.log`. |
| Earlier make test / raw retry | Failed iOS test compilation on inferred nonisolated actor modifiers; corrected by final conformance extensions and superseded by passing MCP run. Separate make test-ui was not run; full MCP simulator suite included all 21 UI tests. |

MCP discovery counts retain cross-platform/no-result and dynamic-parameter entries. Its iOS summary included an old canceled source-test state. The fresh per-run xcresult and console are authoritative; both final bundles report Passed without failures.

## Recovery evidence

Clean baseline 3c2c6c8 reproduced AsyncAlgorithms 1.1.1's sending-result compiler error and original actor protocol-conformance failures. Temporary ignored-cache diagnostics were restored. Final source-controlled pin/isolation changes fix them without downgrading the toolchain.

Exact swift-frontend full-module reproduction fails in normal source order and passes fixture-first. Final empty conformance extensions also pass normal-order reproduction. Removing protocol isolation, aliasing, nesting or refining the protocol did not fix it; all experiments were reverted. `.codex-cache/t2377/final-full-typecheck.log` records the successful reproduction.

Both GUI-launched simulator and macOS test processes later blocked in Foundation source-file opening at CreateTaskProjectRequiredSchemaTests.intentParameterDescriptionMatchesStaticLiteral. Samples: `.codex-cache/t2377/ios-unit-stall-sample.txt` and `mac-unit-stall-sample.txt`. No debugger was attached. Confirmed stalls were stopped through Xcode MCP before replacements ran. Initial simulator xcresult finalized: 408 total, 83 passed, 325 canceled; every failure was Testing was canceled. The assertion now runs in the CLI process, and final app suites pass. No assertions were relaxed.

User explicitly approved the configured xcrun mcpbridge caller/worktree; tools were accessed through a local stdio client because they were not surfaced in this task. Package resolution was performed once for that workspace. Only this task's Xcode workspace/destinations were used; no physical deployment.

## Reviews and workflow

Personal `/Users/arjen/.codex/skills/transit/SKILL.md` routed the feature through requirements/design/tasks. Repository CLAUDE.md was read; no AGENTS.md or checkout .agents/skills existed. The separate peer-review-validator allowed independent subagent fallback because external peers were unavailable. Design/code/simplification/architecture reviews found no remaining feature or concurrency issues; final compiler workaround and platform guard were reviewed independently.

The user additionally requested the exact personal pre-push-review skill after implementation. Its four-role review is complete: reuse, quality and efficiency found no actionable issues; spec/documentation review found one minor rollback-versus-cleanup wording issue, now corrected. Validation snapshot/restore ran make lint successfully and touched no tracked files or new untracked paths. The Swift ecosystem registry detects only root Package.swift projects, so its JUnit/coverage recipe does not detect this Xcode repository; runner not detected is recorded explicitly. Native Xcode results above remain the verification evidence. The bundled renderer generated `pre-push-review.html` with the complete working-tree diff, blast-radius diagram, explanations, important changes and resolved finding. Renderer reported 0 failed/errored structured tests (no JUnit data); native per-run counts above are separately explicit. Phase 8 publication was omitted because the user expressly withheld publication authorisation. No unpushed commits exist; it reviews the working tree and untracked feature files against the merge base. Publication is explicitly not authorised. All implementation/review tasks are complete. T-2377 is ready for human review; no remaining code findings or implementation blockers.

## Three-level implementation explanation


## Beginner level

An MCP client can now create a Transit project before adding its tasks. It supplies a name and a color, plus an optional description and repository. Transit checks those values, saves the project, and returns its ID and details. The client can use that ID in its next create_task call.

The Mac's current Xcode toolchain also needs a newer dependency and clearer concurrency declarations. These changes allow the app and its existing actor-based tests to compile with Swift 6.4.

## Intermediate level

The core tool inventory and dispatcher now expose create_project. The handler validates required/optional string types and whole-string six-digit ASCII hex colors, then delegates trimmed-name validation, case-insensitive duplicate detection and persistence to ProjectService. A shared metadata formatter keeps get_projects and creation results aligned; discovery still enriches projects with milestones.

The dependency update changes only AsyncAlgorithms to 1.1.3. CounterStore and CounterSnapshot explicitly opt out of the application's MainActor default and use checked Sendable. Two existing test actors move their protocol conformances into empty extensions to avoid a Swift 6.4 declaration-order diagnostic. Their methods and state remain unchanged. A source-literal guard now runs as CLI preflight for lint/test commands, while the runtime description test remains cross-platform; app test runners do not open host checkout paths.

## Expert level

Creation remains a synchronous MainActor service operation, so local uniqueness validation and saving have no suspension window. Storage fallback rejects the new mutation through the existing gate. Invalid optional values, including JSON null, are rejected rather than silently discarded. Color validation checks the full regex range to reject trailing newlines; the stored color's case and prefix are preserved. Optional repository values retain the existing free-form service contract.

The response includes a persisted UUID usable by create_task. Tests cover schema discovery, validation, duplicate/read failure, metadata parity, persistence and project-to-task integration. Save-failure cleanup remains covered by the shared persistence helper rather than a new handler-specific failure seam.

The compatibility change preserves production CloudKitCounterStore's MainActor isolation and existing allocator serialization, retries and compare-and-swap behavior. Normal-order compiler reproduction and Xcode MCP build-for-testing validate the conformance-placement workaround; final runtime outcomes are recorded in implementation.md. No publication or deployment is included.

## Completeness assessment

Fully implemented: create_project contract, validation, persistence, reusable metadata, fallback gate, behavioral coverage, docs and user-authorised Xcode 27 compatibility. Full final macOS and simulator suites and CLI guard pass. No implementation requirement is partially implemented or missing. Structured JUnit/coverage is unavailable from the supplied pre-push runner registry for this native Xcode project; this review does not infer coverage. Publication remains explicitly outside the authorised scope.
