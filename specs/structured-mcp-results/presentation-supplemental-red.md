# Task5 supplemental RED preparation

Status: READY fixtures against unchanged runtime source1652913. Task5/gpzncvp remains in progress; prior GREEN readiness is withdrawn. Baseline task4 RED evidence remains complete. No supplemental behavioral RED or app GREEN is claimed yet.

Read-only source audit confirms query_milestones returns a root array from milestoneToDict/MCPRecordSnapshot.milestone. The supplemental fixture requires only each saved projectId relationship at /index/projectId; milestoneId never becomes task/project entity identity, and malformed/missing project references produce no link.

Complete v1 source fixtures preserve contractVersion/tool/idempotencyKey/outcome/accepted/retryAction/error and unknown:null. Established terminal rejections with accepted:true include completion/replay timestamps. They test INTERRUPTED_BEFORE_COMMIT and INTERNAL_ERROR: known validated rejection/no-commit evidence must follow its original new_request_new_key direction even though the supplemental category is internal_failure. An accepted:false INTERNAL_ERROR preacceptance rejection also follows that source direction. accepted:true means key binding rather than a committed entity effect. Receipt validity remains provider-owned; no test or adapter creates a second acceptance engine.

Controls use complete v1 unknown-code rejection, uncertain known internal error and unestablished known terminal rejection. These must retain reconciliation and original text/isError rather than gaining a safe retry. Existing task4 fixtures remain intact. Expected additions are five declarations/seven expanded cases; only an actual xcresult can establish final counts.

Light preparation passed: frontend parse of owned test files, strict no-cache SwiftLint, and standalone Swift6/default MainActor typecheck using pure Results/Protocol/read-only MCPTypes plus unchanged baseline and supplemental test scratch copies. No app build/test ran, and runtime files have no diff from1652913.

Next exact command after a separate parent heavy-slot grant:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPResultPresentationTests'
```

Anticipated meaningful failures are the absent /index/projectId milestone selector and internal_failure rejection recovery currently choosing reconciliation. Classification/source-preservation controls must remain passing. Compiler/fixture failures would not count as RED. Do not repair runtime before supplemental behavioral RED is demonstrated. A checkpointed get_projects position-building loop remains a subsequent GREEN repair obligation, not a source edit in this draft.
