#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor
struct MCPPartialMetadataCompatibilityTests {
    private func input(
        _ meta: String, method: String = "server/discover", headers: [MCPModernHeader] = []
    ) -> MCPModernRequestInput {
        MCPModernRequestInput(httpMethod: "POST", headers: [
            .init(name: "Host", value: "localhost:3141"),
            .init(name: "Content-Type", value: "application/json"),
            .init(name: "Accept", value: "application/json, text/event-stream")
        ] + headers, body: Data("""
        {"jsonrpc":"2.0","id":1,"method":"\(method)","params":{"_meta":\(meta)}}
        """.utf8))
    }

    @Test(arguments: [
        "{}", #"{"progressToken":"fixture"}"#,
        #"{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}"#,
        #"{"io.modelcontextprotocol/clientCapabilities":{}}"#
    ])
    func partialObjectsAllowDiscoveryWithNoMirroredHeaders(meta: String) throws {
        let request = try MCPModernValidator.validate(input(meta), availability: .init(tools: []))
        #expect(request.metadata.protocolVersion == "2026-07-28")
        #expect(request.metadata.clientCapabilities == .object([]))
        #expect(request.metadata.clientInfo == nil)
        guard case .discover = request.method else { Issue.record("Expected discovery"); return }
    }

    @Test func defaultsUseSuppliedHeaderAndNeverCarryCapabilitiesBetweenRequests() throws {
        let declared = try MCPModernValidator.validate(
            input(#"{"io.modelcontextprotocol/clientCapabilities":{"sampling":{}}}"#),
            availability: .init(tools: []))
        #expect(declared.metadata.clientCapabilities == .object([.init(name: "sampling", value: .object([]))]))
        let empty = try MCPModernValidator.validate(input(#"{"progressToken":1}"#,
            headers: [.init(name: "MCP-Protocol-Version", value: "2025-03-26")]), availability: .init(tools: []))
        #expect(empty.metadata.protocolVersion == "2025-03-26")
        #expect(empty.metadata.clientCapabilities == .object([]))
    }

    @Test(arguments: [
        "null", "[]", "true", #""invalid""#,
        #"{"io.modelcontextprotocol/protocolVersion":null}"#,
        #"{"io.modelcontextprotocol/protocolVersion":20260728}"#,
        #"{"io.modelcontextprotocol/clientCapabilities":null}"#,
        #"{"io.modelcontextprotocol/clientCapabilities":[]}"#,
        #"{"io.modelcontextprotocol/clientCapabilities":{"sampling":{"tools":true}}}"#,
        #"{"io.modelcontextprotocol/clientInfo":{"name":"missing-version"}}"#,
        #"{"bad/key/extra":{}}"#
    ])
    func everySuppliedFieldStillMustBeValid(meta: String) throws {
        do {
            _ = try MCPModernValidator.validate(input(meta), availability: .init(tools: []))
            Issue.record("Malformed metadata was accepted")
        } catch let rejection as MCPModernRejection {
            #expect(rejection.httpStatus == 400)
            #expect(rejection.rpcCode == -32602)
        }
    }

    @Test func partialMetadataDoesNotBypassHeaderChecksOrSubscriptionRequirements() throws {
        let meta = #"{"progressToken":1}"#
        let invalidHeaders: [[MCPModernHeader]] = [
            [.init(name: "Mcp-Method", value: "tools/list")],
            [.init(name: "MCP-Protocol-Version", value: "2026-07-28"),
             .init(name: "MCP-Protocol-Version", value: "2026-07-28")],
            [.init(name: "MCP-Protocol-Version", value: "unsupported")]
        ]
        for headers in invalidHeaders {
            #expect(throws: MCPModernRejection.self) {
                try MCPModernValidator.validate(input(meta, headers: headers), availability: .init(tools: []))
            }
        }
        for partial in [meta, #"{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}"#,
                        #"{"io.modelcontextprotocol/clientCapabilities":{}}"#] {
            #expect(throws: MCPModernRejection.self) {
                try MCPModernValidator.validate(input(partial, method: "subscriptions/listen"),
                                                availability: .init(tools: []))
            }
        }
        let versionMismatch = input(#"{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}"#,
            headers: [.init(name: "MCP-Protocol-Version", value: "2025-03-26")])
        #expect(throws: MCPModernRejection.self) {
            try MCPModernValidator.validate(versionMismatch, availability: .init(tools: []))
        }
    }
}
#endif
