#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskResponseTests {
    private typealias Fixture = MCPBatchTaskResultFixtures
    private typealias Sequence = MCPBatchTaskCoordinatorSequenceFixtures

    @Test(arguments: [false, true])
    func actualResponseAdapterUsesOneEncoderAndPreservesCommittedReceipt(failEncoding: Bool) async throws {
        let fixture = try MCPBatchTaskCoordinatorFixture()
        let request = try fixture.request([fixture.item(0, operation: "add_comment")])
        let prepared = try Sequence.prepared(request)
        let counts = MCPBatchTaskEncodingCounts()
        let selected = try await MCPBatchTaskResponse.execute(request, prepared: prepared,
            writeCoordinator: try #require(fixture.coordinator), encodeOutcome: { outcome, id, metadata in
                counts.record("encode")
                if failEncoding { throw MCPResultBoundaryError.resourceLimit }
                return try MCPResultProviderSelection.encode(outcome: outcome, id: id, metadata: metadata)
            })
        #expect(counts.snapshot().encode == 1)
        let bytes: Data
        switch selected {
        case .normal(let value): #expect(!failEncoding); bytes = value
        case .reconciliation(let value): #expect(failEncoding); bytes = value
        case .suppressed: Issue.record("Unexpected delivery suppression"); return
        }
        let result = try Fixture.result(bytes)
        let payload = Fixture.field("payload", in: Fixture.field("source",
            in: Fixture.field("structuredContent", in: result)))
        #expect(Fixture.field("summary", in: payload) ==
            .string(failEncoding ? "serialization_failed" : "all_committed"))
        #expect(try fixture.durableComments().count == 1)
        let replay = try await fixture.source(request.items[0])
        #expect(replay.originalIsError == nil)
        #expect(try fixture.durableComments().count == 1)
    }

    @Test func failedPreparationPreventsResponseAdapterAndEffects() throws {
        let fixture = try MCPBatchTaskCoordinatorFixture()
        let request = try fixture.request([fixture.item(0)])
        do {
            _ = try MCPBatchTaskPreparedResponse.prepare(id: .integer(42), items: request.items.map {
                .init(index: $0.index, itemId: $0.itemId, operation: $0.operation,
                    originalKey: .init(tool: $0.command.tool, idempotencyKey: $0.command.key),
                    targetTaskId: $0.targetTaskId)
            }, metadata: nil, checkpoint: { throw MCPResultBoundaryError.resourceLimit })
            Issue.record("Preparation fault must produce no execution capability")
        } catch let error as MCPResultBoundaryError { #expect(error == .resourceLimit) }
        #expect(fixture.saveStages.isEmpty)
        #expect(try fixture.durableTasks().first { $0.id == fixture.tasks[0].id }?.taskDescription == nil)
    }

    @Test func outputSchemaPreservesCommonWrapperAndUnrestrictedOriginalJSON() throws {
        let descriptor = try MCPBatchTaskOutputSchema.descriptor(description: "Batch mutations")
        let root = descriptor.outputSchema.value
        let definitions = Fixture.field("$defs", in: root)
        let payload = Fixture.field("batchPayload", in: definitions)
        #expect(Fixture.field("type", in: root) == .string("object"))
        #expect(Fixture.field("additionalProperties", in: root) == .boolean(false))
        let items = Fixture.field("items", in: Fixture.field("items", in: Fixture.field("properties", in: payload)))
        let original = Fixture.field("originalResult", in: Fixture.field("properties", in: items))
        #expect(Fixture.field("payload", in: Fixture.field("properties", in: original)) == .object([]))
        #expect(Fixture.field("type", in: Fixture.field("text", in: Fixture.field("properties", in: original))) ==
            .string("string"))
    }
}
#endif
