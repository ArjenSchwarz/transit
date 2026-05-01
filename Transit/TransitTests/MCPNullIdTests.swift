#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Regression tests for T-847: JSON-RPC requests with explicit `null` id must
/// receive a response with `id: null`, while requests with the id member omitted
/// (notifications) must receive no response.
@MainActor @Suite(.serialized)
struct MCPNullIdTests {

    // MARK: - Decoding

    @Test func decodingDistinguishesOmittedIdFromExplicitNull() throws {
        // Per JSON-RPC 2.0, a request without an `id` member is a notification.
        // A request with `"id": null` is NOT a notification — null is a valid id value.
        let omittedJSON = Data(#"{"jsonrpc":"2.0","method":"ping"}"#.utf8)
        let nullJSON = Data(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#.utf8)

        let omitted = try JSONDecoder().decode(JSONRPCRequest.self, from: omittedJSON)
        let explicitNull = try JSONDecoder().decode(JSONRPCRequest.self, from: nullJSON)

        #expect(omitted.isNotification, "Request with no id member must be treated as a notification")
        #expect(!explicitNull.isNotification, "Request with explicit null id is not a notification")
    }

    // MARK: - Handler behaviour

    @Test func handlerReturnsResponseForExplicitNullId() async throws {
        let env = try MCPTestHelpers.makeEnv()

        // Request with explicit null id should get a response.
        let json = Data(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = await env.handler.handle(request)
        try #require(response, "Explicit null id must produce a JSON-RPC response")
    }

    @Test func handlerOmitsResponseForMissingId() async throws {
        let env = try MCPTestHelpers.makeEnv()

        // Request with no id member is a notification — no response.
        let json = Data(#"{"jsonrpc":"2.0","method":"ping"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = await env.handler.handle(request)
        #expect(response == nil, "Notifications (omitted id) must not produce a response")
    }

    // MARK: - Encoding

    @Test func responseToExplicitNullIdEncodesIdAsNull() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let json = Data(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = try #require(await env.handler.handle(request))
        let data = try JSONEncoder().encode(response)
        let parsed = try JSONSerialization.jsonObject(
            with: data, options: [.fragmentsAllowed]
        ) as? [String: Any]
        let object = try #require(parsed)

        // The id key must be present and explicitly NSNull (not absent).
        #expect(object.keys.contains("id"), "Response must include the id field for null-id requests")
        #expect(object["id"] is NSNull, "id must be encoded as JSON null")
    }
}

#endif
