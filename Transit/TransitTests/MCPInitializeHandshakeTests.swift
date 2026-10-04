#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Legacy handshake regressions now apply to each modern request's metadata.
/// Initialize is unavailable; an absent optional clientInfo is valid.
@MainActor @Suite(.serialized)
struct MCPInitializeHandshakeTests {
    @Test func initializeIsUnavailableInsteadOfNegotiatingSession() throws {
        let rejection = try reject(method: "initialize", params: ["_meta": validMetadata()])
        #expect(rejection.httpStatus == 404)
        #expect(rejection.rpcCode == -32601)
    }

    @Test func discoverWithoutParamsReturnsInvalidParams() throws {
        let rejection = try reject(params: nil)
        #expect(rejection.rpcCode == -32602)
    }

    @Test func discoverWithNonObjectParamsReturnsInvalidParams() throws {
        let rejection = try reject(params: ["2026-07-28"])
        #expect(rejection.rpcCode == -32602)
    }

    @Test func scalarParamsRemainInvalid() throws {
        for value in [42, true, NSNull(), "invalid"] as [Any] {
            #expect(try reject(params: value).rpcCode == -32602)
        }
    }

    @Test func everyRequiredMetadataFieldRemainsRequired() throws {
        for field in ["protocolVersion", "clientCapabilities"] {
            var meta = validMetadata()
            meta.removeValue(forKey: field)
            #expect(try reject(params: ["_meta": meta]).rpcCode == -32602)
        }
        #expect(try reject(params: [:] as [String: Any]).rpcCode == -32602)
    }

    @Test func wrongRequiredFieldTypesRemainRejected() throws {
        for (field, value) in [("protocolVersion", 20260728), ("clientCapabilities", [])] as [(String, Any)] {
            var meta = validMetadata()
            meta[field] = value
            #expect(try reject(params: ["_meta": meta]).rpcCode == -32602)
        }
    }

    @Test func malformedClientInfoRemainsRejectedWhenProvided() throws {
        for clientInfo in [
            ["version": "1.0"], ["name": "Transit Tests"], ["name": 42, "version": "1.0"],
            ["name": "Transit Tests", "version": 1], ["name": "Transit Tests", "version": "1.0", "title": false]
        ] as [[String: Any]] {
            var meta = validMetadata()
            meta["clientInfo"] = clientInfo
            #expect(try reject(params: ["_meta": meta]).rpcCode == -32602)
        }
    }

    @Test func optionalClientInfoAndUnknownMetadataDoNotRequireSession() throws {
        var meta = validMetadata()
        meta["example.test/extension"] = ["unknown": NSNull()]
        _ = try MCPModernValidator.validate(input(method: "server/discover", params: ["_meta": meta]),
                                            availability: MCPModernAvailability(tools: []))
    }

    @Test func unsupportedVersionRejectsWithoutLegacyFallback() throws {
        var meta = validMetadata()
        meta["protocolVersion"] = "2099-01-01"
        let rejection = try reject(params: ["_meta": meta], version: "2099-01-01")
        #expect(rejection.rpcCode == -32022)
    }

    private func validMetadata() -> [String: Any] {
        ["protocolVersion": "2026-07-28", "clientCapabilities": [:] as [String: Any]]
    }

    private func input(method: String, params: Any?, version: String = "2026-07-28") throws -> MCPModernRequestInput {
        var object: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method]
        if let params { object["params"] = params }
        return MCPModernRequestInput(httpMethod: "POST", headers: [
            .init(name: "Content-Type", value: "application/json"), .init(name: "Accept", value: "application/json"),
            .init(name: "MCP-Protocol-Version", value: version), .init(name: "Mcp-Method", value: method)
        ], body: try JSONSerialization.data(withJSONObject: object))
    }

    private func reject(method: String = "server/discover", params: Any?,
                        version: String = "2026-07-28") throws -> MCPModernRejection {
        do {
            _ = try MCPModernValidator.validate(input(method: method, params: params, version: version),
                                                availability: MCPModernAvailability(tools: []))
            Issue.record("Expected modern metadata rejection")
            throw FixtureFailure.expectedRejection
        } catch let rejection as MCPModernRejection { return rejection }
    }

    private enum FixtureFailure: Error { case expectedRejection }
}
#endif
