# Task 4: presentation RED draft

Status: demonstrated RED in `stream/structured-presentation-1` from verified source base `df3c23b`, with final fixtures at `99f8cbc`. Rune task 4 is complete. No task 5 GREEN implementation has started.

Parent confirmed the implementation boundary: `present` now declares `throws` and a default `@escaping @Sendable` original-worker checkpoint. Its declaration-stage body throws `notImplemented`; no category is fabricated for checkpoint failure. Future presentation must propagate cancellation/deadline errors unchanged, without retaining the callback or renewing its deadline.

The confirmed pointer interpretation uses the documented record object position (for example `/record`) and a separate direct relationship token (for example `/record/projectId`). Provider-declared positions may identify documented entity objects or UUID tokens. All lookup is against the same immutable source; no recursive guesses or current-model reads.

Draft fixtures cover:

- Task/project unavailable links, relationship pointers, source array order, duplicate display IDs with distinct UUIDs, record/currentRecord/recordBeforeDeletion, unknown nested IDs, missing/malformed identities, and unsupported milestone identity.
- Actual `batchQueryResults` selector shape uses `results[i].task` containing the serialized record directly (not another `record` wrapper). The added fixture links that task and its saved projectId, skips unsuccessful requested IDs, and keeps per-selector absence distinct from whole-read failure. Historical root task-array fixtures preserve array order and saved project relationships too.
- Source audit confirms serialized task records use `taskId`, and project records use `projectId`; canonical covered-field `id` is not the public record identity. Fixtures use actual serialized names. Pre-T2379 `handleQueryTasks`/`handleDisplayIdLookup` explicitly returned root arrays of task dictionaries, supporting the historical-array case without inventing a new provider shape.
- Typed provider object positions use those same documented record fields for their entity type, or directly point to a UUID token. Arbitrary `id` on a built-in task position is rejected. An alternate future provider identity schema must be declared explicitly rather than guessed recursively; no alternate field-selection API is introduced in this RED declaration.
- Provider positions, object ordering and scalar-exact Unicode/escaped JSON Pointer lookup, including composed/decomposed distinct member names.
- Seeded unknown fields, namespace collisions and shrinking while retaining the asserted task identity/deterministic presentation invariant. Source text and validated fragment bytes remain unchanged.
- All finite explicit categories, known historical codes, unknown codes without prose matching, accepted uncertain effects, contradictory retry evidence, original-key versus maintenance reconciliation, source-authoritative rejection retry, and read retry/restart directions.
- Original worker checkpoint propagation, including an error sharing a parser-boundary type, plus repeated checkpoints during a 2,000-record presentation traversal.

Targeted parsing, no-cache SwiftLint and standalone Swift 6/default MainActor typechecking passed, including pure Results/Protocol modules and the new fixtures with Xcode's Testing framework/macro plugin. No app build or test run is claimed.

Executed focused command, after explicit parent START:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPResultPresentationTests'
```

Build and test launch succeeded. Make exited 2; xcodebuild reported Error 65 / TEST FAILED. The xcresult summary reports 20 declarations, all 20 failed; expanded dynamic runs total 48, all 48 failed. There were no compiler/test-launch errors or malformed-fixture parse failures.

Every success/category/link/recovery case caught `.notImplemented` from the presentation declaration, including the actual nested selector and historic root-array shapes. Checkpoint assertions expected the original cancellation/boundary error and received `.notImplemented`; the repeated checkpoint assertion also showed zero worker checks. This is meaningful behavioral RED against the placeholder, not a compilation failure. The seeded property has not reached its invariance/shrinking path because presentation throws immediately; GREEN must run that unchanged path successfully.

Artifacts: `.codex-cache/presentation-red.log`, `.codex-cache/presentation-red-summary.json`, and `DerivedData/Logs/Test/Test-Transit-2026.10.03_23-12-20-+1000.xcresult`. The single pipeline and test host drained before main was notified to start protocol RED. Unrelated installed Transit app processes were left untouched; no extra app job or GREEN followed.

Only feature-local tests, declaration/comment interfaces, this evidence document and Rune task status changed. Metadata ordering and compact batch fallback tests remain later task 6/7 obligations. Common API task 15 remains undelivered.
