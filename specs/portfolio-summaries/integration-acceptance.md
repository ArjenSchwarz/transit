# T-2382 integration acceptance

## Prior sequential acceptance: verified source and scope

Native build/test source: `33972bde496bccee5a764a17b0bed84003f827a8`, branch `T-2382/final-verification`. The cumulative T63 integration base is `ff6286a162d9ffb0b16a0aa07d5c5d5b6195b842`. Subsequent delivery changes are documentation/task bookkeeping only. Xcode 27.0 (27A266a) was used with a guarded two-phase native macOS runner, not an unmodified Makefile full test invocation.

## Native acceptance

The finalized current bundle passed all 149 selected declarations and 221 expanded bodies, including all three seeded reconciliation cases. Native issues, runtime warnings and NIO misuse diagnostics are zero. The process drained normally, and the exact signed isolated unit host was revalidated. The full compiled inventory contains 2,277 declarations.

Root reconciliation gives each of those 2,277 declarations exactly one accepted result: current 149/221 supersede overlapping baseline results; qualified T63 reuse supplies 2,128 declarations / 2,360 expanded bodies. The union is 2,581 expanded passed bodies, with no inventory gaps. This is **not one new full-suite run**.

T63 reuse retains its qualification: Chunk05 had post-body overlap with preceding stalled Chunk04. Stalled/unfinalized attempts are excluded, and their cause remains unproved. Common source equivalence is recorded separately; the only production delta from the integrated T63 base removes an unused scaffold enum. Owned suites were rerun on current source.

The current native build contains 82 warning entries / 41 unique signatures, all matching the preserved T63 baseline. No new warnings were accepted. An initial build had one additional unused-return warning; it was fixed before the accepted build. Selector preparation initially mistook extension filenames for suite names; native enumeration corrected the selectors before test execution.

The original attempt2 job record remains marked failed by a broad log classifier. Independent read-only acceptance proves the finalized native result and accepts only the expected controlled `FallbackOutcomeFixture.InjectedFailure` log whose generated Swift type contains “unknown context”. No native test issue exists; no other unknown-context or NIO message is exempted. Original evidence was preserved, not rewritten into a pass.

## Platform qualification

No new iOS or UI suite was run. Qualified active-source reuse carries forward the finalized T2383/T63 iOS 1,310 declarations / 1,358 executions and UI 21 declarations / 24 executions. All current changed Swift files are macOS gated; active iOS source and build configuration match the accepted cumulative source. These results are not macOS coverage. Actual installed-client compatibility remains explicitly deferred to the user's MacBook after merge.

## Review and evidence

Four local pre-push reviewers assessed reuse, quality, efficiency and approved-spec adherence. The unused scaffold was removed. No unresolved must-fix finding remains; optional helper reuse and corruption-heavy/prepared-owner scaling suggestions were deferred without an established deadline violation. Caller contract, all three explanation levels and completeness assessment are included.

Native evidence is under the task-2 `t2382-review-evidence/sequential-completion` directory: `attempt2-independent-acceptance-v4.json`, `root-native-coverage-union-33972bd.json`, source-equivalence records, preserved job/native trees and finalized `.xcresult` bundle. The generic ecosystem renderer has no detected JUnit runner for this Xcode repository; no JUnit or coverage result was fabricated. Native evidence is reported explicitly in the review instead.

Final lint, review publication and remote push are recorded in the delivery handoff. The user approved GitHub pushes, external Claude review and overnight merges; PR Pilot proceeds under that approval. No merge, deployment, live write, settings change, CloudKit action or production activation was performed.

## Main reconciliation acceptance

T2383 PR250 and T63 PR251 were squash merged before reconciliation onto main `747983a7009d0015280f6e88ec811d933f4ef449`. Remaining T2382 changes are owned regression tests/fixtures, specifications and caller documentation, plus removal of the unused scaffold enum. The original reviewed branch is preserved at `T-2382/reviewed-a4a60de`; foreign documentation and the original worktree's unstaged assertion remain untouched.

Four scoped pre-push reviewers found one fixture failure-path defect: a nonfatal duplicate-cursor assertion could loop indefinitely on a pagination regression. Commit `a60e12af4b0b9f4e013b5d702c97be6f34882eba` makes it throwing. Current approval summaries were also corrected; earlier dated pauses remain historical. Optional test-decoder consolidation was deferred without assertion churn. No unresolved must-fix finding remains.

A fresh guarded Xcode27 build and focused native test run passed at that source. The finalized bundle has 149 declarations / 221 expanded bodies (19 parameterized declarations / 91 Argument bodies), including all three seeded reconciliation cases. Native issues, runtime warnings and NIO diagnostics are zero; exit0 and normal physical drain require no termination. The full compiled inventory is still 2,277 declarations. Build warnings are the exact known 82 entries / 41 signatures, with zero unmatched signatures. `make lint` passed all guards and reports zero violations in 546 Swift files.

Compiled-input comparison records 589 inputs: 588 match prior tested source33972bd, and the sole difference is the approved throwing assertion. This fresh build did not reuse the old compiled host after changing the assertion. Root independently queried the finalized bundle and reconciled 149 current declarations / 221 bodies plus 2,128 qualified common-source declarations / 2,360 bodies: exact union 2,277 / 2,581, each declaration once. This still is not a new full-suite run; all T63 overlap and iOS/UI reuse qualifications above remain binding. No new iOS/UI run or actual installed-client validation is claimed.

Evidence is retained under task-2 `t2382-review-evidence/main-reconciliation/review-fix-a60e12a`: `independent-native-acceptance.json`, `root-native-coverage-union.json`, `compiled-input-comparison.json`, inventory attestations, lint log and finalized `green-a60e12af4b0b9f4e013b5d702c97be6f34882eba/handler-tests-attempt1.xcresult`. Subsequent delivery documentation changes do not alter compiled inputs. The generic review renderer still has no detected JUnit runner; native results remain separately and explicitly reported.

Explicit user approval permits destination push, Claude disclosure and overnight merge after review/checks. PR Pilot status, review publication, PR URL and merge SHA are recorded in the delivery handoff. Installed-client compatibility remains deferred to post-merge MacBook validation before production activation. No live updates, settings changes, CloudKit action, deployment or activation occur here.
