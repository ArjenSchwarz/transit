#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor
struct MCPModernDiscoveryTests {
    private func result(_ bytes: Data, id: Any) throws -> [String: Any] {
        let envelope = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(envelope["jsonrpc"] as? String == "2.0")
        let responseID = try #require(envelope["id"])
        #expect(String(describing: responseID) == String(describing: id))
        let result = try #require(envelope["result"] as? [String: Any])
        #expect(result["resultType"] as? String == "complete")
        #expect(result["ttlMs"] as? Int == 0)
        #expect(result["cacheScope"] as? String == "public")
        return result
    }

    @Test func discoveryAdvertisesOnlyImplementedCapabilitiesAndModernVersion() throws {
        let result = try result(MCPModernDiscovery.encodeDiscovery(id: .string("discover"),
            identity: MCPModernServerIdentity(name: "Transit", version: "fixture")), id: "discover")
        #expect(result["supportedVersions"] as? [String] == ["2026-07-28"])
        let capabilities = try #require(result["capabilities"] as? [String: Any])
        #expect(capabilities["tools"] is [String: Any])
        #expect(capabilities["resources"] == nil)
        #expect(capabilities["sampling"] == nil)
        let meta = try #require(result["_meta"] as? [String: Any])
        let identity = try #require(meta["io.modelcontextprotocol/serverInfo"] as? [String: Any])
        #expect(identity["name"] as? String == "Transit")
        #expect(identity["version"] as? String == "fixture")
    }

    @Test func toolsAreSortedAndEveryDefinitionRetainsOutputSchema() throws {
        let schema = try MCPJSONDocument.parse("{\"type\":\"object\"}")
        let tools = ["zeta", "alpha", "middle"].map {
            MCPModernToolDescriptor(name: $0, description: "fixture " + $0, inputSchema: schema,
                resultSchema: MCPResultSchemaDescriptor(tool: $0, description: "fixture", outputSchema: schema))
        }
        let result = try result(MCPModernDiscovery.encodeTools(id: .integer(7), tools: tools), id: 7)
        let definitions = try #require(result["tools"] as? [[String: Any]])
        #expect(definitions.compactMap { $0["name"] as? String } == ["alpha", "middle", "zeta"])
        for definition in definitions {
            #expect((definition["outputSchema"] as? [String: Any])?["type"] as? String == "object")
            #expect((definition["inputSchema"] as? [String: Any])?["type"] as? String == "object")
        }
        let empty = try self.result(MCPModernDiscovery.encodeTools(id: .integer(8), tools: []), id: 8)
        #expect((empty["tools"] as? [Any])?.isEmpty == true)
    }
}
#endif
