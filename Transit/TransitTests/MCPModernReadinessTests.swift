#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Separate synthetic fixture, never the installed listener or a persistent store.
@MainActor @Suite(.serialized)
struct MCPModernReadinessTests {
    @Test func isolatedLoopbackNegotiatesDiscoveryListReadAndSubscription() async throws {
        let trace = try await MCPModernReadinessFixture.capture()
        try assertNegotiation(trace)
        try #require(trace["synthetic"] as? Bool == true)
        try #require(trace["persistentStore"] as? Bool == false)
        let exchanges = try #require(trace["exchanges"] as? [[String: Any]])
        try #require(exchanges.count == 6)
        #expect(exchanges.compactMap { $0["kind"] as? String } == [
            "discovery", "list", "read", "wrong-version", "legacy-method", "notification"
        ])
        let discovery = try #require(exchanges[0]["response"] as? [String: Any])
        let discoveryResult = try #require(discovery["result"] as? [String: Any])
        #expect(discoveryResult["supportedVersions"] as? [String] == ["2026-07-28"])
        let listed = try #require(exchanges[1]["response"] as? [String: Any])
        let listedResult = try #require(listed["result"] as? [String: Any])
        let tools = try #require(listedResult["tools"] as? [[String: Any]])
        #expect(tools.contains { $0["name"] as? String == "query_tasks" && $0["outputSchema"] != nil })
        let read = try #require(exchanges[2]["response"] as? [String: Any])
        let result = try #require(read["result"] as? [String: Any])
        let structured = try #require(result["structuredContent"] as? [String: Any])
        #expect(structured["contractVersion"] as? Int == 1)
        #expect(structured["source"] != nil && structured["presentation"] != nil)
        for negative in exchanges.suffix(3) {
            #expect((negative["status"] as? Int ?? 0) >= 400)
        }
        let frames = try #require(trace["subscriptionFrames"] as? [[String: Any]])
        try #require(frames.count == 2)
        #expect(frames[0]["method"] as? String == "notifications/subscriptions/acknowledged")
        #expect((frames[0]["params"] as? [String: Any])?["notifications"] as? [String: Bool]
            == ["toolsListChanged": true])
        #expect((frames[1]["result"] as? [String: Any])?["resultType"] as? String == "complete")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("modern-readiness-trace.json")
        try JSONSerialization.data(withJSONObject: trace, options: [.sortedKeys]).write(to: file)
        print("T2383_MODERN_READINESS_EXPORT=\(file.path)")
    }

    private func assertNegotiation(_ trace: [String: Any]) throws {
        let exchanges = try #require(trace["exchanges"] as? [[String: Any]])
        for exchange in exchanges.prefix(3) {
            let request = try #require(exchange["request"] as? [String: Any])
            let response = try #require(exchange["response"] as? [String: Any])
            let headers = try #require(exchange["headers"] as? [String: String])
            let params = try #require(request["params"] as? [String: Any])
            let meta = try #require(params["_meta"] as? [String: Any])
            #expect(meta["io.modelcontextprotocol/protocolVersion"] as? String == "2026-07-28")
            #expect(meta["io.modelcontextprotocol/clientCapabilities"] is [String: Any])
            #expect(headers["MCP-Protocol-Version"] == "2026-07-28")
            #expect(headers["Mcp-Method"] == request["method"] as? String)
            #expect(response["jsonrpc"] as? String == "2.0")
            #expect(exchange["status"] as? Int == 200)
            if request["method"] as? String == "tools/call" { #expect(headers["Mcp-Name"] == "query_tasks") }
            let requestValue = try #require(request["id"])
            let responseValue = try #require(response["id"])
            let requestedID = try JSONSerialization.data(withJSONObject: requestValue, options: [.fragmentsAllowed])
            let responseID = try JSONSerialization.data(withJSONObject: responseValue, options: [.fragmentsAllowed])
            #expect(requestedID == responseID)
        }
        let read = try #require(exchanges[2]["response"] as? [String: Any])
        let result = try #require(read["result"] as? [String: Any])
        let structured = try #require(result["structuredContent"] as? [String: Any])
        let consumed = try #require(trace["structuredConsumption"] as? [String: Any])
        let source = try #require(structured["source"] as? NSDictionary)
        let consumedSource = try #require(consumed["source"])
        #expect(source.isEqual(consumedSource))
        let frames = try #require(trace["subscriptionFrames"] as? [[String: Any]])
        try #require(frames.count == 2)
        let subscription = try #require(trace["subscriptionRequest"] as? [String: Any])
        let subscriptionID = try #require(subscription["id"] as? String)
        let ackParams = try #require(frames[0]["params"] as? [String: Any])
        let ackMeta = try #require(ackParams["_meta"] as? [String: Any])
        let completion = try #require(frames[1]["result"] as? [String: Any])
        let completionMeta = try #require(completion["_meta"] as? [String: Any])
        #expect(ackMeta["io.modelcontextprotocol/subscriptionId"] as? String == subscriptionID)
        #expect(completionMeta["io.modelcontextprotocol/subscriptionId"] as? String == subscriptionID)
        #expect(frames[1]["id"] as? String == subscriptionID)
        #expect(trace["eventIDs"] as? [String] == [])
        #expect(trace["sessionHeader"] is NSNull)
        let discovery = try #require(exchanges[0]["response"] as? [String: Any])
        let discoveryResult = try #require(discovery["result"] as? [String: Any])
        let meta = try #require(discoveryResult["_meta"] as? [String: Any])
        let identity = try #require(meta["io.modelcontextprotocol/serverInfo"] as? [String: Any])
        #expect(identity["name"] as? String == "transit")
        #expect(discoveryResult["capabilities"] != nil)
    }

    @Test func fixtureRefusesProductionAndNonLoopbackEndpoints() throws {
        for endpoint in ["http://127.0.0.1:3141/mcp", "http://example.com:9876/mcp",
                         "https://127.0.0.1:9876/mcp", "http://127.0.0.1:9876/other",
                         "http://user@127.0.0.1:9876/mcp", "http://127.0.0.1:9876/mcp?alias=1",
                         "http://127.0.0.1:9876/mcp#alias"] {
            #expect(throws: MCPReadinessFixtureError.unsafeEndpoint) {
                try MCPModernReadinessFixture.validateEndpoint(URL(string: endpoint)!)
            }
        }
    }
}

#endif
