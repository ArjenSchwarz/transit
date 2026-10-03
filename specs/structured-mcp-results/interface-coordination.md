# Pending common result seam coordination

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
