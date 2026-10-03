#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct MCPResultSchemaRecoveryTests {
    @Test func receiptLikeBatchPreservesOriginalItemKeyReconciliation() throws {
        let mutation = MCPMutationRecoveryContext.applicationBatch(items: [MCPBatchRecoveryItem(
            index: 0, itemId: "saved item", operation: "update_task",
            originalKey: MCPProtectedRecoveryKey(tool: "update_task", idempotencyKey: "original-item-key"),
            targetTaskId: UUID(uuidString: "AA000000-0000-0000-0000-000000000001"))])
        try Self.exportAndCheck("batch", mutation: mutation, expected: .reconcileOriginalWrite)
    }

    @Test func receiptLikeMaintenanceReconcilesWithoutInventingKey() throws {
        try Self.exportAndCheck("maintenance", mutation: .unprotectedMaintenance(tool: "maintenance_fixture"),
                                expected: .reconcileMaintenance)
    }

    @Test func protectedReceiptKeepsAuthoritativeFollowSourceDirection() throws {
        let key = MCPProtectedRecoveryKey(tool: "update_task", idempotencyKey: "original-protected-key")
        try Self.exportAndCheck("protected", mutation: .protectedWrite(key), expected: .followSource)
    }

    private static func exportAndCheck(_ name: String, mutation: MCPMutationRecoveryContext,
                                       expected: MCPResultRecoveryDirection) throws {
        let text = #"""
            {"contractVersion":1,"outcome":"rejected","accepted":false,
            "retryAction":"new_request_new_key","error":{"code":"INVALID_INPUT"},
            "unknown":{"flag":false,"value":null,"exponent":1E-9999}}
            """#
        let source = try MCPResultAdapter.source(text: text, isError: true,
            origin: .retainedJSON, evidence: .established)
        let context = MCPResultContext(tool: "recovery_fixture", semanticFailure: nil,
            mutationRecovery: mutation, entityPositions: [])
        let presentation = try MCPResultAdapter.present(source, context: context)
        let bytes = try MCPResultEncoder.encode(source: source, presentation: presentation,
            id: .string(name), metadata: nil)
        let descriptor = try MCPResultSchemas.descriptor(tool: "recovery_fixture",
                                                         description: "Recovery source fixture")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("transit-mcp-schema-recovery-" + name + "-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try bytes.write(to: directory.appendingPathComponent("result.json"))
        try descriptor.outputSchema.originalUTF8.write(to: directory.appendingPathComponent("schema.json"))
        print("TRANSIT_MCP_SCHEMA_RECOVERY_EXPORT=" + name + " " + directory.path)
        #expect(presentation.evidence == .established)
        #expect(presentation.errorCategory == .invalidInput)
        let result = try MCPResultEncoderFixtures.result(bytes, id: .string(name))
        #expect(try MCPResultEncoderFixtures.originalText(result) == text)
        #expect(MCPResultEncoderFixtures.field("isError", in: result) == .boolean(true))
        #expect(try MCPResultEncoderFixtures.rawFragment(bytes,
            path: ["result", "structuredContent", "source", "payload"]) == Data(text.utf8))
        let structured = try MCPResultEncoderFixtures.structured(result)
        let recovery = MCPResultEncoderFixtures.field("recovery",
            in: MCPResultEncoderFixtures.field("presentation", in: structured))
        #expect(MCPResultEncoderFixtures.field("direction", in: recovery) == .string(expected.rawValue))
        try checkOriginalIdentity(mutation, recovery: recovery)
        #expect(presentation.recovery?.direction == expected)
    }

    private static func checkOriginalIdentity(_ mutation: MCPMutationRecoveryContext,
                                              recovery: MCPJSONValue?) throws {
        switch mutation {
        case .protectedWrite(let key):
            #expect(MCPResultEncoderFixtures.field("tool", in: recovery) == .string(key.tool))
            #expect(MCPResultEncoderFixtures.field("idempotencyKey", in: recovery) == .string(key.idempotencyKey))
        case .unprotectedMaintenance(let tool):
            #expect(MCPResultEncoderFixtures.field("tool", in: recovery) == .string(tool))
            #expect(MCPResultEncoderFixtures.field("idempotencyKey", in: recovery) == nil)
        case .applicationBatch(let items):
            guard case .array(let saved) = MCPResultEncoderFixtures.field("items", in: recovery) else {
                throw MCPResultEncoderFixtures.FixtureError.invalidFixture
            }
            #expect(saved.count == items.count)
            for (index, item) in items.enumerated() {
                let actual = try #require(saved.indices.contains(index) ? saved[index] : nil)
                #expect(try MCPResultEncoderFixtures.field("index", in: actual)
                    == MCPJSONDocument.parse(String(item.index)).value)
                #expect(MCPResultEncoderFixtures.field("tool", in: actual) == .string(item.originalKey.tool))
                #expect(MCPResultEncoderFixtures.field("operation", in: actual) == .string(item.operation))
                #expect(MCPResultEncoderFixtures.field("idempotencyKey", in: actual)
                    == .string(item.originalKey.idempotencyKey))
                #expect(MCPResultEncoderFixtures.field("itemId", in: actual) == item.itemId.map { .string($0) })
                #expect(MCPResultEncoderFixtures.field("targetTaskId", in: actual)
                    == item.targetTaskId.map { .string($0.uuidString) })
            }
        }
    }
}
#endif
