# Structured result schema implementation readiness

Task9/gpzncvt is in progress and GREEN-ready at source `1f20e11` after descriptor implementation `a25bf99`. App GREEN has not run; the next parent-coordinated slot follows the current T1734 job and queued T2382 GREEN. DELIVERED15/gpzncvz remains pending. No routine phone/upload delivery is performed.

## Descriptor and source-only proof

MCPResultSchemas.descriptor(tool:description:) returns an owned validated MCPJSONDocument with explicit Draft202012, local definitions only and maximum container depth 7. The supplemental wrapper is closed, while JSON source.payload accepts every original JSON value and unknown historical field/type. JSON requires payload, text requires a string payload, unreadable prohibits payload and requires unestablished presentation. UUID/escaped JSON Pointer/link/category/recovery constraints match the approved contract; no URI or maintenance durable key is introduced.

The actual source-only fixture export passes 12 descriptors against 36 actual encoder-produced results and 37 malformed variants: 876 host assertions. Supplemental pointer controls pass 7 valid/6 invalid cases and reject UUID trailing newline. Parse, strict targeted no-cache lint (zero violations), pure actual Results/MCPTypes/read-metadata module and unchanged fixture typechecks pass. Pinned test-only bootstrap is committed with shell syntax checked; no new install/global/runtime dependency change occurred. These are pure direct-method/source checks, not app/Swift Testing counts.

Evidence .codex-cache/schema-green-source/source-results.md and pure-proof.json records the initial descriptor proof. The original task8 fixtures/host validator remain byte-exact912ddbc and historical evidence is preserved.

## Review correction and supplemental regression

Critic found that known receipt-shaped rejection evidence could make the adapter emit follow_source for applicationBatch or unprotectedMaintenance contexts, incompatible with their approved schema/reconciliation shapes. Before fixing it, actual source exports and actual schemas reproduced two rejections, with a protected-write control accepted. The one-condition classifier change at1f20e11 permits follow_source only for protectedWrite. Batch retains original-item reconciliation; maintenance retains its original tool and no invented key.

Post-fix all three supplemental results conform. Whole wire bytes differ only in those two direction values; the protected control is byte-identical. Original payload/retryAction/text/isError/evidence/category and item index/operation/tool/key/itemId/target UUID remain unchanged. Original876 assertions still pass. The new three-method MCPResultSchemaRecoveryTests and committed validate_mcp_result_schema_recovery.py provide repeatable app-export/host checks using the existing strict decoder/validator. Reason-sensitive controls reject nonzero exit, incomplete role sets, changed original keys and missing descriptors.

Internal critic clears final `1f20e11` and exact GREEN preparation. Reviewed SHA256 prefixes: classifier `bcb1564c3c9a`, supplemental fixture `2bff256da3df`, host checker `5578743c83d9`; schema remains `ebb3af861af6` (full SHA is recorded in pure-proof.json). This is conformance and representation proof; schema validation does not establish receipt commitment, provider identity authenticity or batch transaction/order semantics.

## Exact next guarded run

Use .codex-cache/schema-recovery-conformance/guarded-commands.json, guarded-build-command.txt and host-preflight.py; these supersede the initial original-suite-only preparation under schema-green-source. Fresh SchemaRecoveryGreenBuild.xcresult/SchemaRecoveryGreen.xcresult and T2383SchemaRecoveryGreen.xctestrun preserve prior artifacts.

Build/preflight/serial test selects only MCPResultSchemaTests and MCPResultSchemaRecoveryTests (five methods). Preflight verifies signed me.nore.ig.Transit.development, no CloudKit/push/AppGroup entitlements, unit-test persistence, isolation-smoke/exact-host guards and no UI targets. After actual normal exit and drain, copy the original app-owned export plus exactly three recovery role exports. Run the original host checker for876 assertions and the supplemental checker for three actual descriptor/results, both with the actual process exit. No fabricated exit/descriptors, schema weakening, diagnosis suppression or repeat solely for teardown.

Task9 completion requires its guarded GREEN evidence and runtime review. Task11 accounting, task14 production response selection and task15 common wiring delivery remain pending. T63/T2384 shared ownership and live/client-activation holds are unchanged.
