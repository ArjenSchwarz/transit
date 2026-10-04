#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import NIOConcurrencyHelpers
import ServiceLifecycle
import SwiftData
import Testing
@testable import Transit

nonisolated enum MCPReadinessFixtureError: Error { case unsafeEndpoint, invalidTrace }
@MainActor enum MCPModernReadinessFixture {
    static func validateEndpoint(_ endpoint: URL) throws {
        guard endpoint.scheme == "http", endpoint.host == "127.0.0.1", let port = endpoint.port,
              port > 1024, port != MCPSettings.defaultPort, endpoint.path == "/mcp",
              endpoint.user == nil, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil else {
            throw MCPReadinessFixtureError.unsafeEndpoint
        }
    }

    static func capture() async throws -> [String: Any] {
        let env = try MCPModernResultFixture.makeEnvWithReads()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(name: "Synthetic readiness record", description: nil,
                                               type: .feature, project: project)
        let boundPort = NIOLockedValueBox<Int?>(nil)
        let underlying = MCPServer.makeRouter(handler: env.handler).buildResponder()
        let allowedNames = ["query_tasks", "get_projects"].flatMap {
            [$0, "=?base64?" + Data($0.utf8).base64EncodedString() + "?="]
        }
        let responder = CallbackResponder<MCPRequestContext> { request, context in
            // Mirrored header and body must match in the actual validator. A forged read header
            // cannot authorize a write; its body is rejected by that validator before effects.
            if request.head.headerFields[HTTPField.Name("Mcp-Method")!] == "tools/call",
               !allowedNames.contains(request.head.headerFields[HTTPField.Name("Mcp-Name")!] ?? "") {
                return Response(status: .forbidden)
            }
            return try await underlying.respond(to: request, context: context)
        }
        let app = Application(responder: responder,
            configuration: .init(address: .hostname("127.0.0.1", port: 0)),
            onServerRunning: { channel in boundPort.withLockedValue { $0 = channel.localAddress?.port } })
        let configuration = MCPServerLifecycleConfiguration.make(services: [app], logger: app.logger)
        let group = ServiceGroup(configuration: configuration)
        let listener = Task.detached { try await group.run() }
        do {
            let cutoff = ContinuousClock.now.advanced(by: .seconds(5))
            while boundPort.withLockedValue({ $0 }) == nil && ContinuousClock.now < cutoff {
                try await Task.sleep(for: .milliseconds(10))
            }
            let port = try #require(boundPort.withLockedValue { $0 })
            let endpoint = try #require(URL(string: "http://127.0.0.1:\(port)/mcp"))
            try validateEndpoint(endpoint)
            let descriptor = try exportDescriptor(endpoint)
            let trace = try await collect(endpoint: endpoint, env: env, group: group, descriptor: descriptor)
            await group.triggerGracefulShutdown()
            try await listener.value
            return trace
        } catch {
            env.handler.finishToolListChangeSessions()
            await group.triggerGracefulShutdown()
            _ = try? await listener.value
            throw error
        }
    }

    private static func exportDescriptor(_ endpoint: URL) throws -> URL {
        let requestedHold = ProcessInfo.processInfo.environment["TRANSIT_READINESS_HOLD_SECONDS"] ?? "0"
        let hold = min(120, max(0, Int(requestedHold) ?? 0))
        let descriptor: [String: Any] = ["formatVersion": 1, "endpoint": endpoint.absoluteString,
            "synthetic": true, "persistentStore": false, "allowedTools": ["query_tasks", "get_projects"],
            "catalog": "Actual full catalog; all other tool calls denied before dispatch",
            "bundleID": "me.nore.ig.Transit.development", "holdSeconds": hold,
            "shutdown": "Graceful shutdown after ACK and bounded hold; fixture listener only"]
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-endpoint.json")
        try JSONSerialization.data(withJSONObject: descriptor, options: [.sortedKeys]).write(to: path)
        print("T2383_MODERN_READINESS_ENDPOINT=\(path.path)")
        return path
    }

    private static func collect(endpoint: URL, env: MCPTestEnv, group: ServiceGroup,
                                descriptor: URL) async throws -> [String: Any] {
        let config = URLSessionConfiguration.ephemeral
        let requestedHold = ProcessInfo.processInfo.environment["TRANSIT_READINESS_HOLD_SECONDS"] ?? "0"
        let hold = min(120, max(0, Int(requestedHold) ?? 0))
        config.timeoutIntervalForRequest = Double(hold + 10)
        config.timeoutIntervalForResource = Double(hold + 15)
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var exchanges = [[String: Any]]()
        exchanges.append(try await exchange(session, endpoint, kind: "discovery",
                                            method: "server/discover", id: "discover"))
        exchanges.append(try await exchange(session, endpoint, kind: "list", method: "tools/list", id: 2))
        exchanges.append(try await exchange(session, endpoint, kind: "read", method: "tools/call", id: "read",
            params: ["name": "query_tasks", "arguments": ["detailLevel": "full", "includeComments": false,
                                                         "limit": 1, "readPolicy": "cached"]]))
        exchanges.append(try await exchange(session, endpoint, kind: "wrong-version", method: "server/discover",
            id: 4, version: "2025-03-26"))
        exchanges.append(try await exchange(session, endpoint, kind: "legacy-method", method: "initialize", id: 5))
        exchanges.append(try await exchange(session, endpoint, kind: "notification", method: "tools/list", id: nil))
        let deniedWrite = try await exchange(session, endpoint, kind: "denied-write", method: "tools/call", id: 6,
            params: ["name": "create_project", "arguments": ["name": "Forbidden fixture mutation",
                      "colorHex": "#123456", "idempotencyKey": "readiness-denied-write"]])
        try #require(deniedWrite["status"] as? Int == 403)
        let read = try #require(exchanges[2]["response"] as? [String: Any])
        let result = try #require(read["result"] as? [String: Any])
        let structured = try #require(result["structuredContent"] as? [String: Any])
        let subscription = try await subscription(session, endpoint: endpoint, group: group, env: env)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
        return ["formatVersion": 1, "synthetic": true, "persistentStore": false,
            "endpoint": endpoint.absoluteString, "descriptorPath": descriptor.path, "endpointClosed": true,
            "exchanges": exchanges, "writeDenied": deniedWrite, "structuredConsumption": structured,
            "subscriptionRequest": ["id": "readiness-subscription", "notifications": ["toolsListChanged": true]],
            "subscriptionFrames": subscription.frames, "sessionHeader": subscription.sessionHeader ?? NSNull(),
            "eventIDs": subscription.eventIDs,
            "provenance": ["producer": "actual-app-test", "bundleID": "me.nore.ig.Transit.development",
                           "path": "Actual app router/validator/encoder over separate loopback URLSession"]]
    }

    private static func request(_ endpoint: URL, method: String, id: Any?, params: [String: Any] = [:],
                                version: String = "2026-07-28",
                                accept: String = "application/json") throws -> URLRequest {
        var metadata = MCPModernResultFixture.meta
        metadata["io.modelcontextprotocol/protocolVersion"] = version
        var parameters = params; parameters["_meta"] = metadata
        var object: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": parameters]
        if let id { object["id"] = id }
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version")
        request.setValue(method, forHTTPHeaderField: "Mcp-Method")
        if let tool = params["name"] as? String { request.setValue(tool, forHTTPHeaderField: "Mcp-Name") }
        request.httpBody = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return request
    }

    private static func exchange(_ session: URLSession, _ endpoint: URL, kind: String, method: String,
                                 id: Any?, params: [String: Any] = [:], version: String = "2026-07-28") async throws
        -> [String: Any] {
        let outgoing = try request(endpoint, method: method, id: id, params: params, version: version)
        let (data, response) = try await session.data(for: outgoing)
        let http = try #require(response as? HTTPURLResponse)
        let body: Any = data.isEmpty ? NSNull() : try JSONSerialization.jsonObject(with: data)
        return ["kind": kind, "request": try JSONSerialization.jsonObject(with: try #require(outgoing.httpBody)),
                "headers": outgoing.allHTTPHeaderFields ?? [:], "status": http.statusCode, "response": body]
    }

    private struct SubscriptionEvidence {
        let frames: [[String: Any]]
        let sessionHeader: String?
        let eventIDs: [String]
    }

    private static func subscription(_ session: URLSession, endpoint: URL, group: ServiceGroup,
                                     env: MCPTestEnv) async throws -> SubscriptionEvidence {
        var outgoing = try request(endpoint, method: "subscriptions/listen", id: "readiness-subscription",
            params: ["notifications": ["toolsListChanged": true]], accept: "text/event-stream")
        let requestedHold = ProcessInfo.processInfo.environment["TRANSIT_READINESS_HOLD_SECONDS"] ?? "0"
        outgoing.timeoutInterval = Double(min(120, max(0, Int(requestedHold) ?? 0)) + 10)
        let (bytes, response) = try await session.bytes(for: outgoing)
        let http = try #require(response as? HTTPURLResponse); try #require(http.statusCode == 200)
        var frames = [[String: Any]](); var eventIDs = [String]()
        for try await line in bytes.lines {
            if line.hasPrefix("id:") { eventIDs.append(line) }
            if line.hasPrefix("data:") {
                let data = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
                frames.append(try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any]))
                if frames.count == 1 {
                    let requestedHold = ProcessInfo.processInfo.environment["TRANSIT_READINESS_HOLD_SECONDS"] ?? "0"
                    let hold = min(120, max(0, Int(requestedHold) ?? 0))
                    if hold > 0 { try await Task.sleep(for: .seconds(hold)) }
                    env.handler.finishToolListChangeSessions()
                    await group.triggerGracefulShutdown()
                }
            }
        }
        return SubscriptionEvidence(frames: frames,
            sessionHeader: http.value(forHTTPHeaderField: "Mcp-Session-Id"), eventIDs: eventIDs)
    }
}
#endif
