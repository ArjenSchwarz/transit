#if os(macOS)

import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPInitializeHandshakeTests {

    @Test func initializeWithoutParamsReturnsInvalidParams() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = await env.handler.handle(MCPTestHelpers.request(method: "initialize"))

        let error = try MCPTestHelpers.jsonRPCError(response)
        #expect(error["code"] as? Int == JSONRPCErrorCode.invalidParams)
    }

    @Test func initializeWithNonObjectParamsReturnsInvalidParams() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            id: .integer(1),
            method: "initialize",
            params: AnyCodable(["2025-03-26"])
        )

        let error = try MCPTestHelpers.jsonRPCError(await env.handler.handle(request))
        #expect(error["code"] as? Int == JSONRPCErrorCode.invalidParams)
    }

    @Test func initializeWithScalarParamsReturnsInvalidRequest() throws {
        for params in ["42", "true", "null", "\"invalid\""] {
            let data = Data("""
                {"jsonrpc":"2.0","id":1,"method":"initialize","params":\(params)}
                """.utf8)

            let response: JSONRPCResponse
            switch MCPServer.decodeIncomingRequest(data) {
            case .failure(let errorResponse):
                response = errorResponse
            case .success, .batch:
                Issue.record("Scalar initialize params must be an invalid request")
                continue
            }
            let error = try MCPTestHelpers.jsonRPCError(response)
            #expect(error["code"] as? Int == JSONRPCErrorCode.invalidRequest)
        }
    }

    @Test func initializeRequiresEveryHandshakeField() async throws {
        let env = try MCPTestHelpers.makeEnv()

        for field in ["protocolVersion", "capabilities", "clientInfo"] {
            var params = validInitializeParams()
            params.removeValue(forKey: field)

            let request = MCPTestHelpers.request(method: "initialize", params: params)
            let error = try MCPTestHelpers.jsonRPCError(await env.handler.handle(request))
            #expect(error["code"] as? Int == JSONRPCErrorCode.invalidParams)
        }
    }

    @Test func initializeRejectsWrongRequiredFieldTypes() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let malformedFields: [(String, Any)] = [
            ("protocolVersion", 20250326),
            ("capabilities", []),
            ("clientInfo", "Transit Tests")
        ]

        for (field, value) in malformedFields {
            var params = validInitializeParams()
            params[field] = value

            let request = MCPTestHelpers.request(method: "initialize", params: params)
            let error = try MCPTestHelpers.jsonRPCError(await env.handler.handle(request))
            #expect(error["code"] as? Int == JSONRPCErrorCode.invalidParams)
        }
    }

    @Test func initializeRejectsMalformedClientInfo() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let malformedClientInfo: [[String: Any]] = [
            ["version": "1.0"],
            ["name": "Transit Tests"],
            ["name": 42, "version": "1.0"],
            ["name": "Transit Tests", "version": 1],
            ["name": "Transit Tests", "version": "1.0", "title": false]
        ]

        for clientInfo in malformedClientInfo {
            var params = validInitializeParams()
            params["clientInfo"] = clientInfo

            let request = MCPTestHelpers.request(method: "initialize", params: params)
            let error = try MCPTestHelpers.jsonRPCError(await env.handler.handle(request))
            #expect(error["code"] as? Int == JSONRPCErrorCode.invalidParams)
        }
    }

    @Test func initializeFallsBackToSupportedProtocolVersion() async throws {
        let env = try MCPTestHelpers.makeEnv()
        var params = validInitializeParams()
        params["protocolVersion"] = "2099-01-01"

        let request = MCPTestHelpers.request(method: "initialize", params: params)
        let response = try #require(await env.handler.handle(request))
        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require(json["result"] as? [String: Any])

        #expect(result["protocolVersion"] as? String == "2025-03-26")
    }

    private func validInitializeParams() -> [String: Any] {
        [
            "protocolVersion": "2025-03-26",
            "capabilities": [:] as [String: Any],
            "clientInfo": ["name": "Transit Tests", "version": "1.0"]
        ]
    }
}

#endif
