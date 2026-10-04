#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Modern requests require a string/integer ID. Preserve omitted/null presence
/// for rejection, and omit unreadable IDs from encoded request errors.
@MainActor @Suite(.serialized)
struct MCPNullIdTests {

    // MARK: - Decoding and presence

    @Test func decodingPreservesOmittedIdAndExplicitNullPresence() throws {
        let omittedJSON = Data(#"{"jsonrpc":"2.0","method":"tools/list"}"#.utf8)
        let nullJSON = Data(#"{"jsonrpc":"2.0","id":null,"method":"tools/list"}"#.utf8)
        let stringJSON = Data(#"{"jsonrpc":"2.0","id":"request-1","method":"tools/list"}"#.utf8)
        let integerJSON = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8)

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
        let json = Data(#"{"jsonrpc":"2.0","id":null,"method":"tools/list"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = try #require(await env.handler.handle(request))
        let error = try #require(response.error)
        #expect(error.code == JSONRPCErrorCode.invalidRequest)
        #expect(response.result == nil)
        #expect(response.id == nil, "Invalid requests have no readable response identifier")
    }

    @Test func handlerRejectsMissingIdWithoutEffects() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let json = Data(#"{"jsonrpc":"2.0","method":"tools/list"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = await env.handler.handle(request)
        #expect(response?.error?.code == JSONRPCErrorCode.invalidRequest)
        #expect(response?.id == nil && response?.result == nil)
        #expect(try env.context.fetchCount(FetchDescriptor<TransitTask>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }

    @Test(arguments: [
        "initialize", "ping", "tools/list", "tools/call",
        "notifications/initialized", "unknown/method"
    ])
    func handlerRejectsExplicitNullBeforeDispatchingAnyMethod(method: String) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let json = Data(#"{"jsonrpc":"2.0","id":null,"method":"\#(method)"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = try #require(await env.handler.handle(request))
        let error = try #require(response.error)
        #expect(error.code == JSONRPCErrorCode.invalidRequest)
        #expect(response.result == nil)
        #expect(response.id == nil)
    }

    @Test(arguments: [
        "initialize", "ping", "tools/list", "tools/call",
        "notifications/initialized", "unknown/method"
    ])
    func handlerRejectsMissingIdBeforeEveryMethodPath(method: String) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let json = Data(#"{"jsonrpc":"2.0","method":"\#(method)"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = await env.handler.handle(request)
        #expect(response?.error?.code == JSONRPCErrorCode.invalidRequest)
        #expect(response?.id == nil && response?.result == nil)
        #expect(try env.context.fetchCount(FetchDescriptor<TransitTask>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }

    @Test func handlerReturnsResponsesForStringAndIntegerIds() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let stringRequest = try JSONDecoder().decode(
            JSONRPCRequest.self,
            from: Data(#"{"jsonrpc":"2.0","id":"request-1","method":"tools/list"}"#.utf8)
        )
        let integerRequest = try JSONDecoder().decode(
            JSONRPCRequest.self,
            from: Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8)
        )

        let stringResponse = try #require(await env.handler.handle(stringRequest))
        let integerResponse = try #require(await env.handler.handle(integerRequest))
        #expect(stringResponse.id == .string("request-1"))
        #expect(integerResponse.id == .integer(1))
        #expect(stringResponse.result != nil)
        #expect(integerResponse.result != nil)
    }

    // MARK: - Error envelope encoding

    @Test func invalidNullIdResponseOmitsUnavailableId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let request = try JSONDecoder().decode(
            JSONRPCRequest.self,
            from: Data(#"{"jsonrpc":"2.0","id":null,"method":"tools/list"}"#.utf8)
        )

        let response = try #require(await env.handler.handle(request))
        let data = try JSONEncoder().encode(response)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let error = try #require(object["error"] as? [String: Any])

        #expect(!object.keys.contains("id"))
        #expect(error["code"] as? Int == JSONRPCErrorCode.invalidRequest)
        #expect(object["result"] == nil)
    }
}

#endif
