#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Regression tests for T-1863: MCP 2025-03-26 rejects an explicit JSON `null`
/// request id as Invalid Request. Requests with the id member omitted remain
/// notifications, while string and integer ids remain valid.
@MainActor @Suite(.serialized)
struct MCPNullIdTests {

    // MARK: - Decoding and presence

    @Test func decodingPreservesOmittedIdAndExplicitNullPresence() throws {
        let omittedJSON = Data(#"{"jsonrpc":"2.0","method":"ping"}"#.utf8)
        let nullJSON = Data(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#.utf8)
        let stringJSON = Data(#"{"jsonrpc":"2.0","id":"request-1","method":"ping"}"#.utf8)
        let integerJSON = Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)

        let omitted = try JSONDecoder().decode(JSONRPCRequest.self, from: omittedJSON)
        let explicitNull = try JSONDecoder().decode(JSONRPCRequest.self, from: nullJSON)
        let stringID = try JSONDecoder().decode(JSONRPCRequest.self, from: stringJSON)
        let integerID = try JSONDecoder().decode(JSONRPCRequest.self, from: integerJSON)

        #expect(omitted.isNotification, "An omitted id member must be a notification")
        #expect(!explicitNull.isNotification, "An explicit null id is not an omitted id")
        #expect(explicitNull.id == nil, "Explicit null must remain distinguishable by presence")
        #expect(stringID.id == .string("request-1"))
        #expect(integerID.id == .integer(1))
    }

    // MARK: - Handler behaviour

    @Test func handlerRejectsExplicitNullIdAsInvalidRequest() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let json = Data(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = try #require(await env.handler.handle(request))
        let error = try #require(response.error)
        #expect(error.code == JSONRPCErrorCode.invalidRequest)
        #expect(response.result == nil)
        #expect(response.id == nil, "Invalid requests use a JSON null response id")
    }

    @Test func handlerOmitsResponseForMissingId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let json = Data(#"{"jsonrpc":"2.0","method":"ping"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = await env.handler.handle(request)
        #expect(response == nil, "Notifications (omitted id) must not produce a response")
    }

    @Test func handlerReturnsResponsesForStringAndIntegerIds() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let stringRequest = try JSONDecoder().decode(
            JSONRPCRequest.self,
            from: Data(#"{"jsonrpc":"2.0","id":"request-1","method":"ping"}"#.utf8)
        )
        let integerRequest = try JSONDecoder().decode(
            JSONRPCRequest.self,
            from: Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)
        )

        let stringResponse = try #require(await env.handler.handle(stringRequest))
        let integerResponse = try #require(await env.handler.handle(integerRequest))
        #expect(stringResponse.id == .string("request-1"))
        #expect(integerResponse.id == .integer(1))
        #expect(stringResponse.result != nil)
        #expect(integerResponse.result != nil)
    }

    // MARK: - Error envelope encoding

    @Test func invalidNullIdResponseEncodesErrorWithNullId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let request = try JSONDecoder().decode(
            JSONRPCRequest.self,
            from: Data(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#.utf8)
        )

        let response = try #require(await env.handler.handle(request))
        let data = try JSONEncoder().encode(response)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let error = try #require(object["error"] as? [String: Any])

        #expect(object.keys.contains("id"))
        #expect(object["id"] is NSNull)
        #expect(error["code"] as? Int == JSONRPCErrorCode.invalidRequest)
        #expect(object["result"] == nil)
    }
}

#endif
