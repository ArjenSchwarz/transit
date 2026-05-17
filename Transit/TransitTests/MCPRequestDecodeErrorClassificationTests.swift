#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Regression tests for T-1128: the MCP route handler must distinguish
/// JSON-RPC parse errors (-32700) from invalid-request shape errors (-32600).
///
/// Per JSON-RPC 2.0 §5.1:
/// - `-32700 Parse error` is for input that is not well-formed JSON.
/// - `-32600 Invalid Request` is for valid JSON that is not a well-formed
///   Request object (e.g. missing `method`, non-string `jsonrpc`, unsupported
///   `id` type such as boolean or object).
///
/// The previous implementation used a single `try?` decode and returned
/// `-32700 "Invalid JSON"` for both cases, conflating transport-level parse
/// failures with protocol-level shape failures.
@MainActor @Suite(.serialized)
struct MCPRequestDecodeErrorClassificationTests {

    // MARK: - Parse errors (-32700)

    @Test func malformedJSONReturnsParseError() throws {
        let data = Data("{not json".utf8)
        let response = try unwrapErrorResponse(for: data)
        #expect(response.code == JSONRPCErrorCode.parseError)
        #expect(response.message == "Parse error")
    }

    @Test func emptyBodyReturnsParseError() throws {
        let data = Data()
        let response = try unwrapErrorResponse(for: data)
        #expect(response.code == JSONRPCErrorCode.parseError)
        #expect(response.message == "Parse error")
    }

    @Test func unterminatedStringReturnsParseError() throws {
        // Lexically broken JSON: a quoted string that never closes.
        let data = Data(#"{"jsonrpc":"2.0,"method":"ping"}"#.utf8)
        let response = try unwrapErrorResponse(for: data)
        #expect(response.code == JSONRPCErrorCode.parseError)
    }

    // MARK: - Invalid request errors (-32600)

    @Test func missingMethodReturnsInvalidRequest() throws {
        // Valid JSON, but missing the required `method` member.
        let data = Data(#"{"jsonrpc":"2.0","id":1}"#.utf8)
        let response = try unwrapErrorResponse(for: data)
        #expect(response.code == JSONRPCErrorCode.invalidRequest)
        #expect(response.message == "Invalid Request")
    }

    @Test func nonStringJSONRPCMemberReturnsInvalidRequest() throws {
        // `jsonrpc` must be a string per the spec; a number is structurally wrong.
        let data = Data(#"{"jsonrpc":2.0,"id":1,"method":"ping"}"#.utf8)
        let response = try unwrapErrorResponse(for: data)
        #expect(response.code == JSONRPCErrorCode.invalidRequest)
    }

    @Test func booleanIdReturnsInvalidRequest() throws {
        // `id` must be string, number, or null. Boolean is not allowed.
        let data = Data(#"{"jsonrpc":"2.0","id":true,"method":"ping"}"#.utf8)
        let response = try unwrapErrorResponse(for: data)
        #expect(response.code == JSONRPCErrorCode.invalidRequest)
    }

    @Test func objectIdReturnsInvalidRequest() throws {
        // `id` must be string, number, or null. Object is not allowed.
        let data = Data(#"{"jsonrpc":"2.0","id":{"x":1},"method":"ping"}"#.utf8)
        let response = try unwrapErrorResponse(for: data)
        #expect(response.code == JSONRPCErrorCode.invalidRequest)
    }

    @Test func scalarRootReturnsInvalidRequest() throws {
        // Valid JSON, but the root is a scalar — not a Request object.
        let data = Data("42".utf8)
        let response = try unwrapErrorResponse(for: data)
        #expect(response.code == JSONRPCErrorCode.invalidRequest)
    }

    @Test func errorResponseIdIsNull() throws {
        // For both error categories, `id` in the response must be null when it
        // cannot be reliably extracted from the request.
        let data = Data(#"{"jsonrpc":"2.0","id":true,"method":"ping"}"#.utf8)
        let response = MCPServer.decodeIncomingRequest(data)
        switch response {
        case .success:
            Issue.record("Expected error response for invalid id type")
        case .failure(let errorResponse):
            let encoded = try JSONEncoder().encode(errorResponse)
            let parsed = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            let dict = try #require(parsed)
            #expect(dict.keys.contains("id"))
            #expect(dict["id"] is NSNull)
        }
    }

    // MARK: - Happy path (sanity)

    @Test func wellFormedRequestDecodes() throws {
        let data = Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)
        let result = MCPServer.decodeIncomingRequest(data)
        switch result {
        case .success(let req):
            #expect(req.method == "ping")
            #expect(req.jsonrpc == "2.0")
            #expect(!req.isNotification)
        case .failure:
            Issue.record("Well-formed request must decode successfully")
        }
    }

    // MARK: - Helpers

    private func unwrapErrorResponse(for data: Data) throws -> JSONRPCError {
        let result = MCPServer.decodeIncomingRequest(data)
        switch result {
        case .success:
            Issue.record("Expected decode failure but request decoded successfully")
            throw DecodeUnwrapError.unexpectedSuccess
        case .failure(let response):
            let error = try #require(response.error, "Error response must carry a JSONRPCError")
            return error
        }
    }

    private enum DecodeUnwrapError: Error { case unexpectedSuccess }
}

#endif
