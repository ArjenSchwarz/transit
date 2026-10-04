# Pending common result seam coordination

## Current checkpoint: task10 RED ready, app run pending

Task8 meaningful RED is reviewed and complete at `0695c7c`, retaining command exit143/unfinalized result limitations. Task9 descriptor source `a25bf99` and recovery correction `1f20e11` passed the guarded run at `2df0648`: finalized5/5 app tests and actual-export host checks876 plus3. Build/preflight/test/summary exited0, owned processes drained and slot released; runtime critic clear. Rune9 is complete. See schema-green.md and `.codex-cache/schema-recovery-conformance/results.md`.

The recovery correction permits supplemental follow_source from saved receipt evidence only for protectedWrite. Batch and maintenance retain their original-key/no-key reconciliation policies; source payload/text/isError/retryAction and original identities are unchanged. No schema relaxation or receipt rewrite. MCPResultSchemas.descriptor(tool:description:) returns owned MCPJSONDocument outputSchema without editing shared MCPTypes/definitions.

Task10 RED fixtures are reviewed at `70d103a`: pure module/macro compilation, parse, strict lint and direct boundary probe passed; ten actual notImplemented bodies and one existing barrier control completed in the direct driver. This is not an app test result. Exact guarded commands are prepared in `.codex-cache/preparation-red-readiness/`; see preparation-red.md. Task10 remains in progress awaiting the parent-coordinated slot while T2382 owns heavy verification. Task11 accounting, task14 production selection proof and task15 common provider/schema/wiring delivery remain pending. **DELIVERED15/gpzncvz is not available to T2384.** T63 retains shared wiring ownership and T2384 owns MCPWriteCoordinator/coordinator-specific tests. No app job is running here and any later app run needs its own coordinated slot. Live data/client activation remain held, and routine checkpoint deliveries stay local.

## Historical checkpoint after task7

Tasks3/5/7/12/13 have completed their focused verification. The owned source/presentation/encoder implementation is available at 3ba1cfb, with corrected encoder verification recorded at 3e9f8fe:14/14 methods passed, build/preflight/test exit0 and finalised xcresult. The test-only numeric oracle correction ffe2c33 preserves all original production source and the14 method fixtures; no source semantics changed to accommodate Foundation's numeric conversion limit.

The implemented metadata boundary is MCPResultMetadata.make(document:checkpoint:), with private construction and a validated object-root MCPJSONDocument. MCPResultToolFragment has fileprivate construction through MCPResultEncoder.freeze(source:presentation:metadata:checkpoint:); encode(fragment:id:checkpoint:) adds the current RPC ID. MCPResultEncoder.prepareMutationFallback(id:source:context:metadata:checkpoint:) produces complete bytes from a provider-owned compact logical source before effects. Its batch fallback presentation omits itemId while preserving indexes/operation/tool/original key/target UUID; normal result source remains complete. Focused tests establish these new-module semantics, not production dispatch, receipt atomicity or transport delivery.

Task8 schema RED preparation is now in progress. MCPResultSchemas remains notImplemented. Task11 preparation accounting, task14 production selection proof and task15 common provider/schema/wiring delivery remain pending. **DELIVERED15/gpzncvz is not available to T2384 yet.** T63 retains shared wiring ownership; T2384 retains MCPWriteCoordinator and coordinator-specific tests. T2382 owns the current heavy verification slot, so task8 preparation performs no app build/test. Live data/client activation remain held.

## Historical planning note before focused verification

This note records implementation questions for approved tasks6–15 while tasks5/13 wait for safe application verification. It is planning only: no new production signature, task completion, shared-file handoff or API15 delivery is claimed. Existing declarations remain placeholders. No app launch, server reconnect, live write or test-isolation implementation is authorised by this note.

## Metadata and sealed bytes

The declaration-stage MCPResultMetadata dictionary must become an ordered, validated representation before encoder delivery, as already agreed with the parent. A validated object-root MCPJSONDocument is a suitable backing candidate: it preserves original UTF8, scalar-distinct member names, number lexemes and missing/null values; its private initializer prevents callers from forging insertable fragments. The eventual metadata constructor must reject non-object roots and honour the original worker checkpoint. Exact constructor names remain pending implementation/review.

Provider-generated metadata can use known typed primitives or ordered members, but must cross the same validated boundary before raw insertion. Unknown metadata must never pass through a String-keyed dictionary or Double reconstruction. Nested extension keys may be scalar-distinct even when Swift treats their spellings as canonically equivalent. Top-level namespace validation must match the modern metadata rules rather than use an invalid extension key merely to exercise that regression.

MCPResultToolFragment also needs private construction at the encoder boundary; arbitrary Data is not evidence of a complete valid tool result. Frozen bytes contain the tool result and original metadata, never the originating RPC ID. Wrapping those bytes with a new valid ID must not renew freshness, rebuild presentation, reread models or invoke parsing under publication lock.

## Prepared mutation fallback

T2384 supplies its compact logical serialization_failed source. Before any effects, the common adapter must finish the complete request-correlated modern response, including text, structured presentation, metadata and envelope. Failed preparation means zero effects. Later selection returns already encoded immutable bytes; it does not call the failed source, presentation or envelope encoder again. Cancellation can suppress transport delivery without changing stored outcome evidence.

Batch recovery context may internally retain itemId for normal aggregate correlation. Fallback presentation must omit unbounded itemId, raw records and link data; it retains original input indexes, operation/tool, keys and target UUIDs. A synthetic giant-itemId fixture must prove this boundary without clipping or rewriting the normal source. An aggregate whose nested originals exceed parser input depth32 after effects selects the preencoded shallow fallback and makes no no-effect claim.

Protected fallback keeps original tool/key recovery. Unprotected maintenance carries no invented durable key and requires fresh duplicate scanning/reconciliation. The provider owns its logical failure payload; the common encoder owns complete delivery bytes and selection safety.

## Checkpoints, ownership and charging

Parsing, source inspection, selector allocation/sorting, string escaping, metadata validation and full encoding must use the original operation's checkpoint outside the publication gate. No checkpoint closure survives in returned documents or frozen fragments. Preparation-accounting tests must include new retained backing, decoded owned value data and fragments, preserve existing capture/index charges, and charge genuinely shared backing once. Counting only raw JSON length must not be presented as proof of complete preparation cost.

T63 remains owner of read capture, admission, retention and publication hooks until its exact recorded handoff. T2383 owns separate result/modern protocol modules and later agreed common wiring. T2384 owns the write coordinator and batch consumer; no source edits there are implied. API15 requires verified source/presentation/encoder/schema/provider seams at actual delivery commits. The current READY presentation f4bd03a and protocol b6b616e drafts are not that delivery and remain unmerged.

The next implementation edge is safe GREEN5/13 verification, then encoder/schema tasks in their approved dependency order. No app-host execution resumes until the parent clears isolation and grants the relevant test slot. Live Transit mutation pause remains independent of local source work.
