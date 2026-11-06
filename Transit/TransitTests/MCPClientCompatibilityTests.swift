#if os(macOS)
import Foundation
import HTTPTypes
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPClientCompatibilityTests {
    private func request(
        _ env: MCPTestEnv, body: String, version: String? = nil,
        origin: String? = nil, headers: [HTTPField] = []
    ) async throws -> MCPHTTPTestResponse {
        try await MCPTestHelpers.respond(handler: env.handler, origin: origin,
            contentType: "application/json", accept: "application/json, text/event-stream",
            protocolVersion: version, orderedHeaders: headers, body: body,
            loggerLabel: "mcp-client-compatibility")
    }

    @Test func metadataFreeDiscoveryListAndReadUseProductionRouter() async throws {
        let env = try MCPModernResultFixture.makeEnvWithReads()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        for version in [nil, "2026-07-28"] as [String?] {
            for method in ["server/discover", "tools/list"] {
                let response = try await request(env,
                    body: "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"\(method)\"}", version: version)
                #expect(response.status == .ok)
                let object = try #require(response.json as? [String: Any])
                #expect(object["result"] != nil)
                #expect(object["error"] == nil)
            }
            let read = try await request(env, body:
                #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_projects","arguments":{}}}"#,
                version: version)
            #expect(read.status == .ok)
            let object = try #require(read.json as? [String: Any])
            let result = try #require(object["result"] as? [String: Any])
            #expect(result["isError"] as? Bool != true)
            #expect(result["structuredContent"] != nil)
        }
    }

    @Test func legacyHandshakeAcknowledgementAndRead() async throws {
        let env = try MCPModernResultFixture.makeEnvWithReads()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let initialized = try await request(env, body:
            #"""
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25",
            "capabilities":{},"clientInfo":{"name":"fixture","version":"1"}}}
            """#)
        #expect(initialized.status == .ok)
        let object = try #require(initialized.json as? [String: Any])
        let result = try #require(object["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-03-26")
        let ack = try await request(env, body: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
                                    version: "2025-03-26")
        #expect(ack.status == .accepted)
        #expect(ack.body.isEmpty)
        let read = try await request(env, body:
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_projects","arguments":{}}}"#,
            version: "2025-03-26")
        #expect(read.status == .ok)
        #expect((read.json as? [String: Any])?["result"] != nil)
    }

    @Test func compatibilityNeverBypassesOriginMetadataHeadersOrWriteGuards() async throws {
        let env = try MCPTestHelpers.makeEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let list = #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#
        let blocked = try await request(env, body: list, origin: "https://untrusted.invalid")
        #expect(blocked.status == .forbidden)
        for headers in [
            [HTTPField(name: HTTPField.Name("Mcp-Method")!, value: "tools/call")],
            [HTTPField(name: HTTPField.Name("MCP-Protocol-Version")!, value: "2026-07-28"),
             HTTPField(name: HTTPField.Name("MCP-Protocol-Version")!, value: "2026-07-28")]
        ] {
            let response = try await request(env, body: list, headers: headers)
            #expect(response.status == .badRequest)
        }
        for metadata in ["null", "[]", #"{"io.modelcontextprotocol/protocolVersion":null}"#,
                         #"{"io.modelcontextprotocol/clientCapabilities":null}"#] {
            let response = try await request(env, body:
                "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{\"_meta\":\(metadata)}}")
            #expect(response.status == .badRequest)
        }
        let mutation = ##"""
        {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_project",
        "arguments":{"name":"Blocked","colorHex":"#112233"}}}
        """##
        let missingKey = try await request(env, body: mutation)
        let result = try #require((missingKey.json as? [String: Any])?["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
        let notification = try await request(env, body: mutation.replacingOccurrences(of: #""id":2,"#, with: ""))
        #expect(notification.status == .badRequest)
        #expect(try env.context.fetchCount(FetchDescriptor<Project>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }

    @Test func malformedCompatibilityRequestsStillReject() async throws {
        let env = try MCPTestHelpers.makeEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        for body in [
            #"{"jsonrpc":"2.0","id":null,"method":"tools/list"}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":null}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{},"params":{}}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"subscriptions/listen","params":{"notifications":{}}}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"unavailable_tool"}}"#
        ] {
            let response = try await request(env, body: body)
            #expect(response.status == .badRequest)
        }
        let read = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_projects"}}"#
        let mismatch = try await request(env, body: read, headers: [
            HTTPField(name: HTTPField.Name("Mcp-Name")!, value: "create_project")
        ])
        #expect(mismatch.status == .badRequest)
        let version = try await request(env, body: read, version: "unsupported")
        #expect(version.status == .badRequest)
    }

    @Test func omittedMetadataGrantsNoClientCapabilities() throws {
        let input = MCPModernRequestInput(httpMethod: "POST", headers: [
            MCPModernHeader(name: "Host", value: "localhost:3141"),
            MCPModernHeader(name: "Content-Type", value: "application/json"),
            MCPModernHeader(name: "Accept", value: "application/json")
        ], body: Data(#"{"jsonrpc":"2.0","id":1,"method":"server/discover"}"#.utf8))
        let request = try MCPModernValidator.validate(input, availability: MCPModernAvailability(tools: []))
        #expect(request.metadata.clientCapabilities == .object([]))
        #expect(request.metadata.clientInfo == nil)
    }
}
#endif
