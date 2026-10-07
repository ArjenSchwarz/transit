#if os(macOS)
import Foundation
import Testing
@testable import Transit
@MainActor struct MCPConsolidationContractTests {
    @Test func fullCapabilityAdvertisesFourToolsAndClosedInputs() throws {
        let tools = MCPToolDefinitions.tools(includingMaintenance: false, includingConsolidation: true)
        let names = Set(MCPConsolidationToolDefinitions.tools.map(\.name))
        #expect(names.count == 4)
        #expect(names.isSubset(of: Set(tools.map(\.name))))
        for definition in MCPConsolidationToolDefinitions.tools {
            #expect(definition.inputSchema.additionalProperties == false)
        }
        #expect(!MCPToolDefinitions.tools(includingMaintenance: false).contains { names.contains($0.name) })
        let raw = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            MCPConsolidationToolDefinitions.previewApply.inputSchema)) as? [String: Any])
        let properties = try #require(raw["properties"] as? [String: [String: Any]])
        let accounting = try #require(properties["preservation"])
        #expect(accounting["additionalProperties"] as? Bool == false)
        let patterns = try #require(accounting["patternProperties"] as? [String: [String: Any]])
        let entry = try #require(patterns.values.first)
        #expect(entry["additionalProperties"] as? Bool == false && entry["anyOf"] is [[String: Any]])
        let edits = try #require(properties["survivorEdits"]?["properties"] as? [String: [String: Any]])
        #expect((edits["metadata"]?["additionalProperties"] as? [String: Any])?["type"] as? String == "string")
    }
    @Test(arguments: ["true", "1", "null"])
    func acknowledgmentMustBeActualBooleanTrue(raw: String) throws {
        let value = try JSONSerialization.jsonObject(with: Data(raw.utf8), options: [.fragmentsAllowed])
        let arguments: [String: Any] = ["idempotencyKey": "contract", "reviewId": UUID().uuidString,
            "reviewRevision": "p1:" + String(repeating: "a", count: 64), "preservationAcknowledged": value]
        if raw == "true" {
            _ = try MCPWriteCommand.validate(tool: "consolidate_tasks", arguments: arguments)
        } else {
            #expect(throws: (any Error).self) {
                _ = try MCPWriteCommand.validate(tool: "consolidate_tasks", arguments: arguments)
            }
        }
    }
    @Test func previewReadsUseCoveredAdmission() throws {
        for name in MCPConsolidationToolDefinitions.previewTools {
            let request = JSONRPCRequest(jsonrpc: "2.0", id: .integer(1), method: "tools/call",
                params: AnyCodable(["name": name, "arguments": [:]] as [String: Any]))
            #expect(MCPBoundedReadDispatcher.classify(request)?.request.tool == name)
            #expect(MCPModernProviderBinding.availability(maintenanceEnabled: false, consolidationEnabled: true)
                .tools.contains { $0.name == name && $0.execution == .coveredRead })
        }
    }
}
#endif
