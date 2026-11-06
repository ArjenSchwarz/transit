#if os(macOS)
import Foundation
import Hummingbird
import NIOConcurrencyHelpers
import ServiceLifecycle
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPClientCompatibilityLoopbackTests {
    @Test func directMetadataFreeClientUsesIsolatedHTTPServer() async throws {
        let env = try MCPModernResultFixture.makeEnvWithReads()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let port = NIOLockedValueBox<Int?>(nil)
        let app = Application(responder: MCPServer.makeRouter(handler: env.handler).buildResponder(),
            configuration: .init(address: .hostname("127.0.0.1", port: 0)),
            onServerRunning: { channel in port.withLockedValue { $0 = channel.localAddress?.port } })
        let group = ServiceGroup(configuration:
            MCPServerLifecycleConfiguration.make(services: [app], logger: app.logger))
        let listener = Task.detached { try await group.run() }
        do {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while port.withLockedValue({ $0 }) == nil && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let boundPort = try #require(port.withLockedValue { $0 })
            let endpoint = try #require(URL(string: "http://127.0.0.1:\(boundPort)/mcp"))
            try MCPModernReadinessFixture.validateEndpoint(endpoint)
            try await exchange(endpoint)
            await group.triggerGracefulShutdown()
            try await listener.value
        } catch {
            await group.triggerGracefulShutdown()
            _ = try? await listener.value
            throw error
        }
    }

    private func exchange(_ endpoint: URL) async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let bodies = [
            #"{"jsonrpc":"2.0","id":1,"method":"server/discover"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            #"""
            {"jsonrpc":"2.0","id":3,"method":"tools/call",
            "params":{"name":"get_projects","arguments":{}}}
            """#,
            #"""
            {"jsonrpc":"2.0","id":4,"method":"initialize","params":{"protocolVersion":"2025-03-26",
            "capabilities":{},"clientInfo":{"name":"compatibility-fixture","version":"1"}}}
            """#,
            #"""
            {"jsonrpc":"2.0","id":5,"method":"server/discover","params":{"_meta":{"progressToken":1}}}
            """#,
            #"""
            {"jsonrpc":"2.0","id":6,"method":"tools/list",
            "params":{"_meta":{"io.modelcontextprotocol/clientCapabilities":{}}}}
            """#,
            #"""
            {"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"get_projects","arguments":{},
            "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}
            """#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        ]
        for (index, body) in bodies.enumerated() {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            request.httpBody = Data(body.utf8)
            let (bytes, response) = try await session.data(for: request)
            let http = try #require(response as? HTTPURLResponse)
            #expect(http.statusCode == (index == bodies.count - 1 ? 202 : 200))
            if index == bodies.count - 1 {
                #expect(bytes.isEmpty)
            } else {
                let object = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                let result = try #require(object["result"] as? [String: Any])
                #expect(result["isError"] as? Bool != true)
                #expect(object["id"] as? Int == index + 1)
            }
        }
    }
}
#endif
