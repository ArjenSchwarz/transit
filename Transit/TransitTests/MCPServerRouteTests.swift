#if os(macOS)
import Foundation
import HTTPTypes
import Testing
@testable import Transit

/// Latest-only POST negotiation; no GET SSE/session compatibility.
@MainActor @Suite(.serialized)
struct MCPServerRouteTests {
    @Test(arguments: ["GET", "DELETE", "HEAD", "OPTIONS"])
    func allLegacyListeningMethodsRejectEvenWithSessionAndSSE(method: String) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let verb = try #require(HTTPRequest.Method(rawValue: method))
        let response = try await MCPModernResultFixture.transport(handler: env.handler,
            method: verb, accept: "text/event-stream",
            orderedHeaders: [HTTPField(name: .mcpSessionID, value: "obsolete")], loggerLabel: "subscription-method")
        #expect(response.status == .methodNotAllowed)
        #expect(response.allow == "POST")
        #expect(response.sessionID == nil)
        #expect(env.handler.activeToolListChangeStreamCount == 0)
    }

    @Test func unrelatedPathIsStillNotFoundAndOriginPrecedesMethodRejection() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let unrelated = try await MCPModernResultFixture.transport(handler: env.handler, method: .get,
            path: "/not-mcp", loggerLabel: "subscription-unrelated")
        #expect(unrelated.status == .notFound)
        let forbidden = try await MCPModernResultFixture.transport(handler: env.handler, method: .get,
            origin: "https://evil.example.com", loggerLabel: "subscription-origin")
        #expect(forbidden.status == .forbidden)
        #expect(forbidden.body.isEmpty)
    }

    @Test func modernPOSTSubscriptionRequiresSSEAccept() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = try await rejected(env, accept: "application/json")
        #expect(response.status == .notAcceptable)
        #expect(env.handler.activeToolListChangeStreamCount == 0)
    }

    @Test(arguments: ["application/x-text/event-stream", "text/event-stream;q=0", "text/event-streaming"])
    func unacceptableSSEMediaRangesNeverRegister(accept: String) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = try await rejected(env, accept: accept)
        #expect(response.status == .notAcceptable)
        #expect(env.handler.activeToolListChangeStreamCount == 0)
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5, 6]) func malformedModernSubscriptionDoesNotRegister(variant: Int) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let valid = try MCPModernResultFixture.body(method: "subscriptions/listen",
            parameters: ["notifications": ["toolsListChanged": true]])
        var body = valid
        var version: String? = "2026-07-28"
        var mirrored = "subscriptions/listen"
        switch variant {
        case 0:
            var json = try #require(try JSONSerialization.jsonObject(with: Data(valid.utf8)) as? [String: Any])
            json.removeValue(forKey: "id")
            body = try #require(String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8))
        case 1:
            body = try MCPModernResultFixture.body(method: "subscriptions/listen", id: NSNull(),
                parameters: ["notifications": [:]])
        case 2: version = nil
        case 3: mirrored = "tools/list"
        case 4:
            body = try MCPModernResultFixture.body(method: "subscriptions/listen", parameters: ["notifications": []])
        case 5:
            body = try MCPModernResultFixture.body(method: "subscriptions/listen",
                parameters: ["notifications": ["toolsListChanged": "true"]])
        default:
            body = #"{"jsonrpc":"2.0","id":1,"method":"subscriptions/listen","params":{"notifications":{}}}"#
        }
        let response = try await rejected(env, body: body, version: version, mirrored: mirrored)
        #expect(response.status == .badRequest)
        #expect(response.sessionID == nil)
        #expect(env.handler.activeToolListChangeStreamCount == 0)
    }

    @Test func invalidKnownResourceFilterRejectsWhileUnknownExtensionsRemainValid() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let invalid = try MCPModernResultFixture.body(method: "subscriptions/listen",
            parameters: ["notifications": ["resourceSubscriptions": [1]]])
        let response = try await rejected(env, body: invalid)
        #expect(response.status == .badRequest)
        #expect(env.handler.activeToolListChangeStreamCount == 0)
        let stream = try await MCPSubscriptionFixture.open(handler: env.handler,
            filters: ["unknown": ["nested": NSNull()]])
        do { try MCPToolListChangeNotificationTests.requireStream(stream) } catch {
            await stream.close(); throw error
        }
        await stream.close()
    }

    @Test func duplicateMirroredHeadersNeverCreateSubscription() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let body = try MCPModernResultFixture.body(method: "subscriptions/listen", parameters: ["notifications": [:]])
        let response = try await MCPModernResultFixture.transport(handler: env.handler,
            contentType: "application/json", accept: "text/event-stream", protocolVersion: "2026-07-28",
            orderedHeaders: [HTTPField(name: HTTPField.Name("Mcp-Method")!, value: "subscriptions/listen"),
                HTTPField(name: HTTPField.Name("Mcp-Method")!, value: "subscriptions/listen")],
            body: body, loggerLabel: "subscription-duplicate-header")
        #expect(response.status == .badRequest)
        #expect(env.handler.activeToolListChangeStreamCount == 0)
    }

    @Test func invalidContentTypeAndHostRejectBeforeRegistration() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let body = try MCPModernResultFixture.body(method: "subscriptions/listen", parameters: ["notifications": [:]])
        let unsupported = try await MCPModernResultFixture.transport(handler: env.handler,
            contentType: "text/plain", accept: "text/event-stream", body: body, loggerLabel: "subscription-content")
        #expect(unsupported.status == .unsupportedMediaType)
        let forbidden = try await MCPModernResultFixture.transport(handler: env.handler,
            authority: "rebind.example:3141", contentType: "application/json", accept: "text/event-stream",
            body: body, loggerLabel: "subscription-host")
        #expect(forbidden.status == .forbidden)
        #expect(env.handler.activeToolListChangeStreamCount == 0)
    }

    private func rejected(_ env: MCPTestEnv, body: String? = nil, accept: String = "text/event-stream",
                          version: String? = "2026-07-28", mirrored: String = "subscriptions/listen") async throws
        -> MCPHTTPTestResponse {
        let requestBody = try body ?? MCPModernResultFixture.body(method: "subscriptions/listen",
            parameters: ["notifications": ["toolsListChanged": true]])
        return try await MCPModernResultFixture.transport(handler: env.handler,
            contentType: "application/json", accept: accept, protocolVersion: version,
            orderedHeaders: [HTTPField(name: HTTPField.Name("Mcp-Method")!, value: mirrored)],
            body: requestBody, loggerLabel: "subscription-rejection")
    }
}
#endif
