#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// This synthetic driver proves readiness/selection of actual encoder bytes.
/// It does not prove production dispatch, receipt atomicity or transport delivery;
/// real provider/response selection integration is task14's separate obligation.
@MainActor
struct MCPResultEncoderFallbackTests {
    private typealias Fixture = MCPResultEncoderFixtures

    private func selectAfterSyntheticEffect(
        prepare: () throws -> Data, effect: () -> Void, finalEncoding: () throws -> Data
    ) throws -> Data {
        let completeFallback = try prepare()
        effect()
        do { return try finalEncoding() } catch { return completeFallback }
    }

    private func protectedContext() -> MCPMutationRecoveryContext {
        .protectedWrite(MCPProtectedRecoveryKey(tool: "update_task", idempotencyKey: "original-\"\\\n-key"))
    }

    private func failureSource() throws -> MCPResultSource {
        try Fixture.source("{\"outcome\":\"uncertain\",\"accepted\":null,\"retryAction\":\"reconcile\"}",
                           isError: true, evidence: .unestablished)
    }

    @Test func protectedFallbackIsCompleteBeforeEffectsAndSelectedWithoutReencoding() throws {
        let id = JSONRPCId.string("protected-\"\\\n")
        let source = try failureSource()
        let context = Fixture.context(protectedContext())
        let metadata = try MCPResultMetadata.make(document: MCPJSONDocument.parse(
            "{\"com.example/request\":\"original\",\"com.example/number\":-0}"))
        var effects = 0
        var preparationCalls = 0
        var failedEncoderCalls = 0
        var prepared: Data?
        let selected = try selectAfterSyntheticEffect(prepare: {
            preparationCalls += 1
            let bytes = try MCPResultEncoder.prepareMutationFallback(id: id, source: source,
                                                                     context: context, metadata: metadata)
            let result = try Fixture.result(bytes, id: id)
            #expect(try Fixture.originalText(result) == source.originalText)
            #expect(Fixture.field("isError", in: result) == .boolean(true))
            #expect(Fixture.field("_meta", in: result) == metadata.document.value)
            #expect(effects == 0)
            prepared = bytes
            return bytes
        }, effect: { effects += 1 }, finalEncoding: {
            failedEncoderCalls += 1
            throw Fixture.FixtureError.injectedEncodingFailure
        })
        #expect(effects == 1)
        #expect(preparationCalls == 1)
        #expect(failedEncoderCalls == 1)
        #expect(selected == prepared)
        let result = try Fixture.result(selected, id: id)
        let presentation = Fixture.field("presentation", in: try Fixture.structured(result))
        let recovery = try #require(Fixture.field("recovery", in: presentation))
        let leaves = Fixture.leaves(recovery)
        #expect(leaves.contains("original-\"\\\n-key"))
        #expect(leaves.contains("update_task"))
        #expect(leaves.contains("reconcile_original_write"))
        #expect(!leaves.contains("new_request_new_key"))
    }

    @Test func typedPreparationCancellationPreventsAllSyntheticEffects() throws {
        let counter = MCPEncoderCheckpointCounter(failAt: 1)
        let source = try failureSource()
        var effects = 0
        var finalCalls = 0
        #expect(throws: Fixture.FixtureError.cancelled) {
            _ = try selectAfterSyntheticEffect(prepare: {
                try MCPResultEncoder.prepareMutationFallback(id: .integer(7), source: source,
                    context: Fixture.context(protectedContext()), metadata: nil,
                    checkpoint: { try counter.check() })
            }, effect: { effects += 1 }, finalEncoding: {
                finalCalls += 1
                return Data()
            })
        }
        #expect(effects == 0)
        #expect(finalCalls == 0)
        #expect(counter.value() == 1)
    }

    @Test func maintenanceFallbackRequiresReconciliationWithoutInventedKeyOrAcceptance() throws {
        let source = try Fixture.source("{\"error\":{\"code\":\"OUTCOME_UNCERTAIN\"}}", isError: true,
                                       evidence: .unestablished)
        let context = Fixture.context(.unprotectedMaintenance(tool: "reassign_duplicate_display_ids"))
        let bytes = try MCPResultEncoder.prepareMutationFallback(id: .integer(19), source: source,
                                                                 context: context, metadata: nil)
        let result = try Fixture.result(bytes, id: .integer(19))
        #expect(try Fixture.originalText(result) == source.originalText)
        let structured = try Fixture.structured(result)
        let payload = Fixture.field("payload", in: Fixture.field("source", in: structured))
        #expect(payload == source.document?.value)
        #expect(Fixture.field("accepted", in: payload) == nil)
        let presentation = try #require(Fixture.field("presentation", in: structured))
        let leaves = Fixture.leaves(presentation)
        #expect(leaves.contains("reconcile_maintenance"))
        #expect(leaves.contains("reassign_duplicate_display_ids"))
        #expect(!leaves.contains("idempotencyKey"))
        #expect(!leaves.contains("new_request_new_key"))
    }

    @Test func batchFallbackOmitsUnboundedCorrelationOnlyFromFallbackPresentation() throws {
        let giantID = String(repeating: "giant-correlation-🛰️", count: 4_096)
        let normalFixture = MCPJSONFixtureValue.object([
            MCPJSONFixtureMember(name: "items", value: .array([.object([
                MCPJSONFixtureMember(name: "itemId", value: .string(giantID)),
                MCPJSONFixtureMember(name: "originalResult", value: .object([
                    MCPJSONFixtureMember(name: "unknown", value: .number("9007199254740993"))
                ]))
            ])]))
        ])
        let normalSource = try Fixture.source(normalFixture.json())
        let normalPresentation = try MCPResultAdapter.present(normalSource, context: Fixture.context())
        let normalResult = try Fixture.result(MCPResultEncoder.encode(source: normalSource,
            presentation: normalPresentation, id: .string("normal"), metadata: nil), id: .string("normal"))
        let payload = try #require(Fixture.field("payload", in: Fixture.field("source",
                                                                         in: try Fixture.structured(normalResult))))
        #expect(normalFixture.matches(payload))
        #expect(try Fixture.originalText(normalResult) == normalSource.originalText)

        let taskId = try #require(UUID(uuidString: "E46FCBBA-31BA-4C53-AD13-C3A4E3209819"))
        let item = MCPBatchRecoveryItem(index: 3, itemId: giantID, operation: "update_task",
            originalKey: MCPProtectedRecoveryKey(tool: "update_task", idempotencyKey: "batch-original-key"),
            targetTaskId: taskId)
        // This synthetic provider owns its compact logical failure shape.
        let compactSource = try Fixture.source(
            "{\"summary\":\"serialization_failed\",\"retryAction\":\"reconcile\"}",
            isError: true, evidence: .unestablished)
        let context = Fixture.context(.applicationBatch(items: [item]))
        let bytes = try MCPResultEncoder.prepareMutationFallback(id: .string("batch"), source: compactSource,
                                                                 context: context, metadata: nil)
        let result = try Fixture.result(bytes, id: .string("batch"))
        #expect(try Fixture.originalText(result) == compactSource.originalText)
        let structured = try Fixture.structured(result)
        #expect(Fixture.field("payload", in: Fixture.field("source", in: structured)) == compactSource.document?.value)
        let presentation = try #require(Fixture.field("presentation", in: structured))
        #expect(Fixture.field("evidence", in: presentation) == .string("unestablished"))
        let leaves = Fixture.leaves(presentation)
        #expect(leaves.contains("3"))
        #expect(leaves.contains("update_task"))
        #expect(leaves.contains("batch-original-key"))
        #expect(leaves.contains(taskId.uuidString))
        #expect(!leaves.contains(giantID))
        #expect(!leaves.contains("itemId"))
        #expect(bytes.count < 4_096)
    }

    @Test func postEffectDepthFailureSelectsAlreadyEncodedShallowFallback() throws {
        let source = try Fixture.source("{\"summary\":\"serialization_failed\"}", isError: true,
                                       evidence: .unestablished)
        let mutation = MCPMutationRecoveryContext.applicationBatch(items: [MCPBatchRecoveryItem(
            index: 0, itemId: nil, operation: "update_task",
            originalKey: MCPProtectedRecoveryKey(tool: "update_task", idempotencyKey: "depth-original-key"),
            targetTaskId: nil)])
        let id = JSONRPCId.integer(31)
        var effects = 0
        var preparations = 0
        var finalCalls = 0
        var finalFailure: MCPResultBoundaryError?
        let selected = try selectAfterSyntheticEffect(prepare: {
            preparations += 1
            let bytes = try MCPResultEncoder.prepareMutationFallback(id: id, source: source,
                                                                     context: Fixture.context(mutation), metadata: nil)
            _ = try Fixture.result(bytes, id: id)
            #expect(effects == 0)
            return bytes
        }, effect: { effects += 1 }, finalEncoding: {
            finalCalls += 1
            let deep = String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33)
            let aggregate: MCPResultSource
            do { aggregate = try Fixture.source(deep) } catch let failure as MCPResultBoundaryError {
                finalFailure = failure
                throw failure
            }
            let presentation = try MCPResultAdapter.present(aggregate, context: Fixture.context())
            return try MCPResultEncoder.encode(source: aggregate, presentation: presentation, id: id, metadata: nil)
        })
        #expect(effects == 1)
        #expect(preparations == 1)
        #expect(finalCalls == 1)
        #expect(finalFailure == .resourceLimit)
        let result = try Fixture.result(selected, id: id)
        let structured = try Fixture.structured(result)
        let retained = Fixture.field("payload", in: Fixture.field("source", in: structured))
        #expect(Fixture.field("summary", in: retained) == .string("serialization_failed"))
        #expect(Fixture.field("accepted", in: retained) != .boolean(false))
        #expect(Fixture.field("outcome", in: retained) != .string("rejected"))
        let presentation = try #require(Fixture.field("presentation", in: structured))
        #expect(Fixture.field("evidence", in: presentation) == .string("unestablished"))
        #expect(Fixture.leaves(presentation).contains("depth-original-key"))
    }
}
#endif
