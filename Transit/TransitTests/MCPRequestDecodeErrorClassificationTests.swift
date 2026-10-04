#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Regression tests for T-1128: the MCP route handler must distinguish
/// JSON-RPC parse errors (-32700) from invalid-request shape errors (-32600).
///
/// Modern request validation retains the original parse-versus-shape regression.
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
        #expect(response.rpcCode == JSONRPCErrorCode.parseError)
        #expect(response.httpStatus == 400)
    }

    @Test func emptyBodyReturnsParseError() throws {
        let data = Data()
        let response = try unwrapErrorResponse(for: data)
        #expect(response.rpcCode == JSONRPCErrorCode.parseError)
        #expect(response.httpStatus == 400)
    }

    @Test func unterminatedStringReturnsParseError() throws {
        // Lexically broken JSON: a quoted string that never closes.
        let data = Data(#"{"jsonrpc":"2.0,"method":"ping"}"#.utf8)
        let response = try unwrapErrorResponse(for: data)
        #expect(response.rpcCode == JSONRPCErrorCode.parseError)
    }

    // MARK: - Invalid request errors (-32600)

    @Test func missingMethodReturnsInvalidRequest() throws {
        // Valid JSON, but missing the required `method` member.
        let data = Data(#"{"jsonrpc":"2.0","id":1}"#.utf8)
        let response = try unwrapErrorResponse(for: data)
        #expect(response.rpcCode == JSONRPCErrorCode.invalidRequest)
        #expect(response.httpStatus == 400)
    }

    @Test func nonStringJSONRPCMemberReturnsInvalidRequest() throws {
        // `jsonrpc` must be a string per the spec; a number is structurally wrong.
        let data = Data(#"{"jsonrpc":2.0,"id":1,"method":"ping"}"#.utf8)
        let response = try unwrapErrorResponse(for: data)
        #expect(response.rpcCode == JSONRPCErrorCode.invalidRequest)
    }

    @Test func booleanIdReturnsInvalidRequest() throws {
        // `id` must be string, number, or null. Boolean is not allowed.
        let data = Data(#"{"jsonrpc":"2.0","id":true,"method":"ping"}"#.utf8)
        let response = try unwrapErrorResponse(for: data)
        #expect(response.rpcCode == JSONRPCErrorCode.invalidRequest)
    }

    @Test func objectIdReturnsInvalidRequest() throws {
        // `id` must be string, number, or null. Object is not allowed.
        let data = Data(#"{"jsonrpc":"2.0","id":{"x":1},"method":"ping"}"#.utf8)
        let response = try unwrapErrorResponse(for: data)
        #expect(response.rpcCode == JSONRPCErrorCode.invalidRequest)
    }

    @Test func scalarRootReturnsInvalidRequest() throws {
        // Valid JSON, but the root is a scalar — not a Request object.
        let data = Data("42".utf8)
        let response = try unwrapErrorResponse(for: data)
        #expect(response.rpcCode == JSONRPCErrorCode.invalidRequest)
    }

    @Test func invalidIDRemainsUnavailableForModernErrorCorrelation() throws {
        for token in ["true", "null", "{}", "[]", "1.5"] {
            let data = Data("{\"jsonrpc\":\"2.0\",\"id\":\(token),\"method\":\"server/discover\"}".utf8)
            let rejection = try unwrapErrorResponse(for: data)
            #expect(rejection.rpcCode == JSONRPCErrorCode.invalidRequest)
            #expect(rejection.id == nil)
        }
    }

    // MARK: - Happy path (sanity)

    @Test func wellFormedRequestDecodes() throws {
        let body = Data("""
            {"jsonrpc":"2.0","id":1,"method":"server/discover",
            "params":{"_meta":{"protocolVersion":"2026-07-28","clientCapabilities":{}}}}
            """.utf8)
        let result = try MCPModernValidator.validate(input(body), availability: MCPModernAvailability(tools: []))
        if case .discover = result.method {} else { Issue.record("Expected discover classification") }
        if case .integer(1) = result.id {} else { Issue.record("Expected original ID") }
    }

    private func input(_ body: Data) -> MCPModernRequestInput {
        MCPModernRequestInput(httpMethod: "POST", headers: [
            .init(name: "Content-Type", value: "application/json"),
            .init(name: "Accept", value: "application/json, text/event-stream"),
            .init(name: "MCP-Protocol-Version", value: "2026-07-28"),
            .init(name: "Mcp-Method", value: "server/discover")
        ], body: body)
    }

    private func unwrapErrorResponse(for data: Data) throws -> MCPModernRejection {
        do {
            _ = try MCPModernValidator.validate(input(data), availability: MCPModernAvailability(tools: []))
            Issue.record("Expected modern rejection")
            throw DecodeUnwrapError.unexpectedSuccess
        } catch let rejection as MCPModernRejection {
            return rejection
        }
    }

    private enum DecodeUnwrapError: Error { case unexpectedSuccess }
}
#endif
