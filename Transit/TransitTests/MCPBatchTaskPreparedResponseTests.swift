#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskPreparedResponseTests {
    private typealias Fixture = MCPBatchTaskResultFixtures

    @Test func failedPreparationCannotConstructADispatchCapability() async throws {
        let counts = MCPBatchTaskEncodingCounts()
        do {
            let prepared = try MCPBatchTaskPreparedResponse.prepare(id: .integer(1),
                items: Fixture.recoveryItems(), metadata: nil, checkpoint: {
                    counts.record("prepare"); throw MCPResultBoundaryError.resourceLimit
                })
            _ = try await prepared.select(dispatch: {
                counts.record("dispatch"); throw MCPResultBoundaryError.unsupportedEvidence
            })
            Issue.record("Preparation failure must block capability construction")
        } catch let error as MCPResultBoundaryError { #expect(error == .resourceLimit) }
        #expect(counts.snapshot().prepare == 1 && counts.snapshot().dispatch == 0)
    }

    @Test func readyCapabilitySelectsExactBytesAfterEncodingFailureWithoutPreparingAgain() async throws {
        let counts = MCPBatchTaskEncodingCounts()
        let giantID = "giant-caller-id-" + String(repeating: "x", count: 200_000)
        let items = Fixture.recoveryItems(itemID: giantID)
        let id = JSONRPCId.string("rpc-\"\\")
        let metadata = try Fixture.metadata()
        let expected = try MCPResultEncoder.prepareMutationFallback(id: id,
            source: MCPBatchTaskFallback.source(items: items),
            context: Fixture.context(items: items), metadata: metadata)
        let prepared = try MCPBatchTaskPreparedResponse.prepare(id: id, items: items, metadata: metadata,
                                                               checkpoint: { counts.record("prepare") })
        let checksBeforeDispatch = counts.snapshot().prepare
        #expect(checksBeforeDispatch > 0 && counts.snapshot().dispatch == 0)
        let normal = try MCPResultAdapter.source(text: Fixture.aggregate(original: Fixture.committed()),
                                                isError: nil, origin: .generatedJSON, evidence: .established)
        let context = prepared.context
        let selected = try await prepared.select(encodeOutcome: { _, _, _ in
            counts.record("encode"); throw MCPResultBoundaryError.resourceLimit
        }, dispatch: {
            #expect(counts.snapshot().prepare == checksBeforeDispatch)
            counts.record("dispatch")
            return .init(source: normal, context: context)
        })
        let bytes = try Fixture.reconciliation(selected)
        #expect(bytes == expected)
        #expect(counts.snapshot().prepare == checksBeforeDispatch)
        #expect(counts.snapshot().dispatch == 1 && counts.snapshot().encode == 1)
        let wire = try #require(String(data: bytes, encoding: .utf8))
        #expect(!wire.contains(giantID) && !wire.contains("itemId"))
        #expect(Fixture.field("id", in: try MCPJSONDocument.parse(bytes).value) == .string("rpc-\"\\"))
        #expect(Fixture.field("_meta", in: try Fixture.result(bytes)) == metadata.document.value)
    }

    @Test func providerFailureAfterSyntheticEffectUsesCapabilityWithoutNormalEncoding() async throws {
        let counts = MCPBatchTaskEncodingCounts()
        let items = Fixture.recoveryItems()
        let prepared = try MCPBatchTaskPreparedResponse.prepare(id: .integer(3), items: items, metadata: nil,
                                                               checkpoint: { counts.record("prepare") })
        let checksBeforeDispatch = counts.snapshot().prepare
        let expected = try MCPResultEncoder.prepareMutationFallback(id: .integer(3),
            source: MCPBatchTaskFallback.source(items: items), context: prepared.context, metadata: nil)
        let selected = try await prepared.select(encodeOutcome: { _, _, _ in
            counts.record("encode"); throw MCPResultBoundaryError.invalidJSON
        }, dispatch: {
            counts.record("dispatch"); throw MCPResultBoundaryError.resourceLimit
        })
        #expect(try Fixture.reconciliation(selected) == expected)
        #expect(counts.snapshot().prepare == checksBeforeDispatch)
        #expect(counts.snapshot().dispatch == 1 && counts.snapshot().encode == 0)
    }
}
#endif
