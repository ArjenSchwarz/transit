# T-2382 integration acceptance

## Verified source and scope

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

Final lint, review publication and remote push are recorded in the delivery handoff. PR creation and external Claude review remain paused pending disclosure approval. No merge, deployment, live write, settings change, CloudKit action or production activation was performed.
