# Task5 supplemental RED preparation

Status: meaningful supplemental RED demonstrated at fixtures391c159 against unchanged runtime source1652913. Task5/gpzncvp remains in progress; prior GREEN readiness is withdrawn. Baseline task4 RED evidence remains complete. Supplemental RED is verified below; no app GREEN or runtime repair is claimed.

Read-only source audit confirms query_milestones returns a root array from milestoneToDict/MCPRecordSnapshot.milestone. The supplemental fixture requires only each saved projectId relationship at /index/projectId; milestoneId never becomes task/project entity identity, and malformed/missing project references produce no link.

Complete v1 source fixtures preserve contractVersion/tool/idempotencyKey/outcome/accepted/retryAction/error and unknown:null. Established terminal rejections with accepted:true include completion/replay timestamps. They test INTERRUPTED_BEFORE_COMMIT and INTERNAL_ERROR: known validated rejection/no-commit evidence must follow its original new_request_new_key direction even though the supplemental category is internal_failure. An accepted:false INTERNAL_ERROR preacceptance rejection also follows that source direction. accepted:true means key binding rather than a committed entity effect. Receipt validity remains provider-owned; no test or adapter creates a second acceptance engine.

Controls use complete v1 unknown-code rejection, uncertain known internal error and unestablished known terminal rejection. These must retain reconciliation and original text/isError rather than gaining a safe retry. Existing task4 fixtures remain intact. Expected additions are five declarations/seven expanded cases; only an actual xcresult can establish final counts.

Light preparation passed: frontend parse of owned test files, strict no-cache SwiftLint, and standalone Swift6/default MainActor typecheck using pure Results/Protocol/read-only MCPTypes plus unchanged baseline and supplemental test scratch copies. No app build/test ran, and runtime files have no diff from1652913.

Next exact command after a separate parent heavy-slot grant:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPResultPresentationTests'
```

Anticipated meaningful failures are the absent /index/projectId milestone selector and internal_failure rejection recovery currently choosing reconciliation. Classification/source-preservation controls must remain passing. Compiler/fixture failures would not count as RED. Do not repair runtime before supplemental behavioral RED is demonstrated. A checkpointed get_projects position-building loop remains a subsequent GREEN repair obligation, not a source edit in this draft.

## Executed supplemental RED

The first per-command escalation was rejected before process launch because approval review could not establish an exception to the original no-heavy-tests instruction from delegated context. Direct owner approval Sentinel_f061180ea7608191b7f8e54205bfdb00 explicitly approved the exact focused command. One retry of the same command/escalation was accepted; no alternate invocation or bypass occurred.

```sh
make test-quick TEST_TARGETS='TransitTests/MCPResultPresentationTests'
```

Make exited2/xcodebuild65. Build/test launch succeeded. xcresult reports25declarations:23passed/2failed, expanded55runs:51passed/4failed. Original20declarations/48runs all pass unchanged, including seeded64-source invariance, scalar-exact pointers and original checkpoint propagation. New5declarations/7runs contain3passing controls (unknown code, uncertain outcome, unestablished known rejection) and4 meaningful failing cases:

- Milestone query links were empty instead of the two saved project references at /0/projectId and /1/projectId.
- INTERNAL_ERROR accepted:false, INTERNAL_ERROR accepted:true and INTERRUPTED_BEFORE_COMMIT accepted:true each produced reconcile_original_write instead of original-source follow_source.

There were no compiler, malformed-fixture or test-host-launch failures. These are the critic's two actual semantic gaps. Runtime diff from1652913 remains empty. Task5 is still in progress pending repairs and separately granted unchanged-fixture GREEN.

Artifacts are ignored .codex-cache/presentation-supplemental-red.log, presentation-supplemental-red-summary.json and presentation-supplemental-red-tests.json, plus DerivedData/Logs/Test/Test-Transit-2026.10.04_00-13-34-+1000.xcresult. Session15636/pipeline and testhost82536 drained; read-only process inspection confirmed no remaining test pipeline/host (unrelated installed Transit7496 untouched). Parent received immediate RELEASE before artifact extraction/bookkeeping. No additional app run or runtime edit followed.
