#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskEncodingTests {
    private typealias Fixture = MCPBatchTaskResultFixtures

    @Test(arguments: [nil, false, true] as [Bool?])
    func generatedAggregateKeepsNestedOriginalEvidenceSeparateFromOuterError(itemIsError: Bool?) throws {
        let original = Fixture.committed(version: "1.0", extra:
            #", "source":{"future":null},"presentation":{"retryAction":"untouched"},"n":1E+9999"#)
        let aggregate = try Fixture.aggregate(original: original, itemIsError: itemIsError)
        let source = try MCPResultAdapter.source(text: aggregate, isError: true,
                                                origin: .generatedJSON, evidence: .established)
        let context = Fixture.context(items: Fixture.recoveryItems())
        let presentation = try MCPResultAdapter.present(source, context: context)
        let metadata = try Fixture.metadata()
        let bytes = try MCPResultEncoder.encode(source: source, presentation: presentation,
                                                id: .string("rpc-correlated"), metadata: metadata)
        let result = try Fixture.result(bytes)
        #expect(Fixture.field("isError", in: result) == .boolean(true))
        #expect(Fixture.field("_meta", in: result) == metadata.document.value)
        let structured = Fixture.field("structuredContent", in: result)
        let payload = Fixture.field("payload", in: Fixture.field("source", in: structured))
        #expect(payload == source.document?.value)
        guard case .array(let items) = Fixture.field("items", in: payload) else {
            Issue.record("Expected the original batch-owned items"); return
        }
        let nested = Fixture.field("originalResult", in: items.first)
        #expect(Fixture.field("text", in: nested) == .string(original))
        #expect(Fixture.field("payload", in: nested) == (try MCPJSONDocument.parse(original).value))
        #expect(Fixture.field("isError", in: nested) == itemIsError.map(MCPJSONValue.boolean))
        let wire = try #require(String(data: bytes, encoding: .utf8))
        #expect(wire.contains(#""id":"rpc-correlated""#))
        #expect(wire.contains(#""n":1E+9999"#))
        #expect(wire.contains(#""contractVersion":1.0"#))
    }

    @Test func compactFallbackStripsGiantItemRecordsDiagnosticsAndEntityLinks() throws {
        let giant = "unbounded-item-" + String(repeating: "x", count: 200_000)
        let items = Fixture.recoveryItems(itemID: giant)
        let context = Fixture.context(items: items, diagnostic: giant,
            links: [.init(entityType: .task, sourcePath: "/items/0/originalResult/payload/record")])
        // Intentionally absent batch-owned builder is the encoding RED seam.
        let source = try MCPBatchTaskFallback.source(items: items)
        #expect(source.kind == .json && source.evidence == .unestablished && source.originalIsError == true)
        #expect(Fixture.field("summary", in: source.document?.value) == .string("serialization_failed"))
        #expect(Fixture.field("outcome", in: source.document?.value) == nil)
        #expect(Fixture.field("accepted", in: source.document?.value) == nil)
        let bytes = try MCPResultEncoder.prepareMutationFallback(id: .integer(7), source: source,
                                                                 context: context, metadata: nil)
        let result = try Fixture.result(bytes)
        #expect(Fixture.field("resultType", in: result) == .string("complete"))
        let structured = Fixture.field("structuredContent", in: result)
        let presentation = Fixture.field("presentation", in: structured)
        #expect(Fixture.field("evidence", in: presentation) == .string("unestablished"))
        #expect(Fixture.field("links", in: presentation) == .array([]))
        let recovery = Fixture.field("recovery", in: presentation)
        #expect(Fixture.field("direction", in: recovery) == .string("reconcile_original_write"))
        guard case .array(let mapped) = Fixture.field("items", in: recovery) else {
            Issue.record("Expected original item recovery mapping"); return
        }
        #expect(mapped.count == 1)
        #expect(Fixture.field("index", in: mapped.first) == (try MCPJSONDocument.parse("0").value))
        #expect(Fixture.field("itemId", in: mapped.first) == nil)
        #expect(Fixture.field("operation", in: mapped.first) == .string("update_task"))
        #expect(Fixture.field("tool", in: mapped.first) == .string("update_task"))
        #expect(Fixture.field("idempotencyKey", in: mapped.first) == .string(Fixture.key))
        #expect(Fixture.field("targetTaskId", in: mapped.first) == .string(Fixture.taskID.uuidString))
        let wire = try #require(String(data: bytes, encoding: .utf8))
        #expect(!wire.contains(giant) && !wire.contains("itemId") && !wire.contains("Saved task"))
        #expect(!wire.contains("new_request_new_key") && !wire.contains("no_effect"))
        #expect(bytes.count < giant.utf8.count)
    }

    @Test func preparationFailureDoesNotDispatchOrTryNormalEncoding() async throws {
        let counts = MCPBatchTaskEncodingCounts()
        let items = Fixture.recoveryItems()
        let source = try MCPBatchTaskFallback.source(items: items)
        do {
            _ = try await MCPResultProviderSelection.mutation(id: .integer(1), context: Fixture.context(items: items),
                metadata: nil, fallbackSource: source, prepareFallback: { id, fallback, context, metadata in
                    counts.record("prepare")
                    return try MCPResultEncoder.prepareMutationFallback(id: id, source: fallback,
                        context: context, metadata: metadata,
                        checkpoint: { throw MCPResultBoundaryError.resourceLimit })
                }, encodeOutcome: { _, _, _ in
                    counts.record("encode"); throw MCPResultBoundaryError.invalidJSON
                }, dispatch: {
                    counts.record("dispatch"); throw MCPResultBoundaryError.unsupportedEvidence
                })
            Issue.record("Preparation failure must propagate before dispatch")
        } catch let error as MCPResultBoundaryError { #expect(error == .resourceLimit) }
        let final = counts.snapshot()
        #expect(final.prepare == 1 && final.dispatch == 0 && final.encode == 0)
    }

    @Test(arguments: ["payload", "presentation", "envelope"])
    func postEffectFailureSelectsCompletePreparedBytesWithoutSecondEncoding(stage: String) async throws {
        let counts = MCPBatchTaskEncodingCounts()
        let items = Fixture.recoveryItems()
        let context = Fixture.context(items: items)
        let fallback = try MCPBatchTaskFallback.source(items: items)
        let normal = try MCPResultAdapter.source(text: Fixture.aggregate(original: Fixture.committed()),
                                                isError: nil, origin: .generatedJSON, evidence: .established)
        let metadata = try Fixture.metadata()
        let selected = try await MCPResultProviderSelection.mutation(id: .string("rpc-after-effect"), context: context,
            metadata: metadata, fallbackSource: fallback, prepareFallback: { id, source, fixed, meta in
                #expect(counts.snapshot().dispatch == 0)
                let bytes = try MCPResultEncoder.prepareMutationFallback(id: id, source: source,
                                                                        context: fixed, metadata: meta)
                counts.record("prepare", prepared: bytes)
                return bytes
            }, encodeOutcome: { outcome, id, meta in
                counts.record("encode")
                if stage == "presentation" {
                    _ = try MCPResultAdapter.present(outcome.source, context: outcome.context,
                                                     checkpoint: { throw MCPResultBoundaryError.resourceLimit })
                }
                let presentation = try MCPResultAdapter.present(outcome.source, context: outcome.context)
                return try MCPResultEncoder.encode(source: outcome.source, presentation: presentation,
                    id: id, metadata: meta, checkpoint: { throw MCPResultBoundaryError.resourceLimit })
            }, dispatch: {
                counts.record("dispatch")
                if stage == "payload" {
                    _ = try MCPResultAdapter.source(text: "{malformed", isError: nil,
                                                     origin: .generatedJSON, evidence: .established)
                }
                return .init(source: normal, context: context)
            })
        let bytes = try Fixture.reconciliation(selected)
        let final = counts.snapshot()
        #expect(final.prepare == 1 && final.dispatch == 1)
        #expect(final.encode == (stage == "payload" ? 0 : 1))
        #expect(bytes == final.prepared)
        #expect(final.events == (stage == "payload" ? ["prepare", "dispatch"] : ["prepare", "dispatch", "encode"]))
        let result = try Fixture.result(bytes)
        #expect(Fixture.field("_meta", in: result) == metadata.document.value)
        #expect(Fixture.field("id", in: try MCPJSONDocument.parse(bytes).value) == .string("rpc-after-effect"))
    }

    @Test func readableDepth32ReceiptOverflowsGeneratedAggregateAfterSyntheticCommit() async throws {
        let original = Fixture.committed(extra: ",\"unknownDepth\":\(Fixture.nestedArrays(31))")
        let retained = try Fixture.source(original)
        #expect(retained.kind == .json && retained.document != nil)
        let counts = MCPBatchTaskEncodingCounts()
        let items = Fixture.recoveryItems()
        let context = Fixture.context(items: items)
        let fallback = try MCPBatchTaskFallback.source(items: items)
        let selected = try await MCPResultProviderSelection.mutation(id: .integer(32), context: context,
            metadata: nil, fallbackSource: fallback, prepareFallback: { id, source, fixed, meta in
                let bytes = try MCPResultEncoder.prepareMutationFallback(id: id, source: source,
                                                                        context: fixed, metadata: meta)
                counts.record("prepare", prepared: bytes)
                return bytes
            }, encodeOutcome: { _, _, _ in
                counts.record("encode"); throw MCPResultBoundaryError.unsupportedEvidence
            }, dispatch: {
                counts.record("dispatch") // Represents one established synthetic effect only.
                let aggregate = try Fixture.aggregate(original: retained.originalText)
                do {
                    let source = try MCPResultAdapter.source(text: aggregate, isError: nil,
                                                            origin: .generatedJSON, evidence: .established)
                    return .init(source: source, context: context)
                } catch let error as MCPResultBoundaryError {
                    #expect(error == .resourceLimit)
                    throw error
                }
            })
        #expect(try Fixture.reconciliation(selected) == counts.snapshot().prepared)
        #expect(counts.snapshot().prepare == 1 && counts.snapshot().dispatch == 1 && counts.snapshot().encode == 0)
        #expect(retained.originalText == original && retained.document?.originalUTF8 == Data(original.utf8))
    }

    @Test func depth33RetainedTextAndOptionalFlagSurviveAsUnreadable() throws {
        let text = Fixture.nestedArrays(33)
        let retained = try Fixture.source(text, isError: false)
        #expect(retained.kind == .unreadable && retained.evidence == .unestablished && retained.document == nil)
        #expect(retained.originalText == text && retained.originalIsError == false)
    }
}
#endif
