#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Regression tests for T-1106: JSON-RPC requests must carry `"jsonrpc": "2.0"`.
/// `MCPToolHandler.handle(_:)` previously dispatched any decoded request regardless
/// of the version field, so requests like `{"jsonrpc":"1.0",...}` or with the field
/// missing entirely were processed normally. Per JSON-RPC 2.0 §4, such requests
/// must produce an error response with code -32600 (Invalid Request).
@MainActor @Suite(.serialized)
struct MCPProtocolVersionTests {

    // MARK: - Helpers

    private struct ErrorFields {
        let code: Int
        let idKeyPresent: Bool
        let idIsNull: Bool
    }

    /// Decode a JSON-RPC error response and return the code plus id presence/null state.
    private static func errorFields(_ response: JSONRPCResponse) throws -> ErrorFields {
        let data = try JSONEncoder().encode(response)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let error = try #require(object["error"] as? [String: Any])
        let code = try #require(error["code"] as? Int)
        return ErrorFields(
            code: code,
            idKeyPresent: object.keys.contains("id"),
            idIsNull: object["id"] is NSNull
        )
    }

    // MARK: - Invalid jsonrpc value

    @Test func handlerRejectsJsonRpcVersion1() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let json = Data(#"{"jsonrpc":"1.0","id":1,"method":"ping"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = try #require(
            await env.handler.handle(request),
            "Request with jsonrpc=1.0 must produce a JSON-RPC error response"
        )

        let fields = try Self.errorFields(response)
        #expect(
            fields.code == JSONRPCErrorCode.invalidRequest,
            "Invalid jsonrpc version must return -32600 (Invalid Request)"
        )
    }

    @Test func handlerRejectsArbitraryJsonRpcVersion() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let json = Data(#"{"jsonrpc":"3.0","id":"abc","method":"tools/list"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = try #require(await env.handler.handle(request))
        let fields = try Self.errorFields(response)
        #expect(fields.code == JSONRPCErrorCode.invalidRequest)
    }

    @Test func handlerRejectsEmptyJsonRpcVersion() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let json = Data(#"{"jsonrpc":"","id":1,"method":"ping"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = try #require(await env.handler.handle(request))
        let fields = try Self.errorFields(response)
        #expect(fields.code == JSONRPCErrorCode.invalidRequest)
    }

    // MARK: - Missing jsonrpc value

    @Test func handlerRejectsMissingJsonRpcField() async throws {
        let env = try MCPTestHelpers.makeEnv()

        // No jsonrpc member at all — must still be parseable and rejected by the
        // handler with -32600 rather than silently dispatched.
        let json = Data(#"{"id":1,"method":"ping"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = try #require(
            await env.handler.handle(request),
            "Request missing jsonrpc must produce an error response"
        )
        let fields = try Self.errorFields(response)
        #expect(fields.code == JSONRPCErrorCode.invalidRequest)
    }

    // MARK: - Echoing the id on protocol-version errors

    @Test func errorResponseEchoesRequestId() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let json = Data(#"{"jsonrpc":"1.0","id":42,"method":"ping"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = try #require(await env.handler.handle(request))
        let data = try JSONEncoder().encode(response)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["id"] as? Int == 42, "Error response must echo the original request id")
    }

    @Test func errorResponseForMissingIdUsesNull() async throws {
        let env = try MCPTestHelpers.makeEnv()

        // No id member and bad jsonrpc — JSON-RPC §5 requires id: null in errors.
        let json = Data(#"{"jsonrpc":"1.0","method":"ping"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = try #require(
            await env.handler.handle(request),
            "Invalid-request errors must respond even when the original was a notification shape"
        )
        let fields = try Self.errorFields(response)
        #expect(fields.idKeyPresent, "Error response must include id field")
        #expect(fields.idIsNull, "Error response id must be null when the original id was absent")
    }

    // MARK: - Valid jsonrpc value still dispatches normally

    @Test func handlerAcceptsValidJsonRpcVersion() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let json = Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        let response = try #require(await env.handler.handle(request))
        let data = try JSONEncoder().encode(response)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["result"] != nil, "Valid ping must produce a result, not an error")
        #expect(object["error"] == nil)
    }
}

#endif
