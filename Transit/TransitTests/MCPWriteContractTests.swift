#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor struct MCPWriteContractTests {
    @Test func allProtectedSchemasPublishRequiredSafety() {
        for definition in MCPToolDefinitions.coreTools
        where MCPWriteCommand.protectedTools.contains(definition.name) {
            #expect(definition.inputSchema.required?.contains("idempotencyKey") == true)
            #expect(definition.inputSchema.properties?["idempotencyKey"]?.pattern == "^[A-Za-z0-9._:-]{1,128}$")
            #expect(definition.inputSchema.additionalProperties == false)
            if MCPWriteCommand.revisionTools.contains(definition.name) {
                #expect(definition.inputSchema.required?.contains("expectedRevision") == true)
                #expect(definition.inputSchema.properties?["expectedRevision"]?.pattern == "^r1:[0-9a-f]{64}$")
            }
        }
    }

    @Test func exactIntegerBoundaryIsAccepted() throws {
        let args: [String: Any] = ["displayId": Int.max, "content": "C", "authorName": "A", "idempotencyKey": "max"]
        _ = try MCPWriteCommand.validate(tool: "add_comment", arguments: args)
        for value in [true, 1.5, Double(Int.max), NSNumber(value: UInt64.max)] as [Any] {
            var invalid = args
            invalid["displayId"] = value
            #expect(throws: (any Error).self) {
                try MCPWriteCommand.validate(tool: "add_comment", arguments: invalid)
            }
        }
    }

    @Test func malformedInputsRemainPreAcceptance() {
        let valid: [String: Any] = ["name": "P", "colorHex": "#112233", "idempotencyKey": "key"]
        for value in [true, 1, NSNull(), "", "key\n", String(repeating: "a", count: 129)] as [Any] {
            var args = valid
            args["idempotencyKey"] = value
            #expect(throws: (any Error).self) {
                try MCPWriteCommand.validate(tool: "create_project", arguments: args)
            }
        }
    }
}

extension MCPTestHelpers {
    static func freshWriteKey() -> String { UUID().uuidString }
    static func readRevision(_ task: TransitTask, in context: ModelContext) throws -> String {
        try MCPRecordSnapshot.task(task, in: context).revision
    }
    static func readRevision(_ milestone: Milestone) throws -> String {
        try MCPRecordSnapshot.milestone(milestone).revision
    }
}
#endif
