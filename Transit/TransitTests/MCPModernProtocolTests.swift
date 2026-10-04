#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Pure protocol fixtures never construct services, capture storage or execute tools.
@MainActor
struct MCPModernProtocolTests {
    private let version = "2026-07-28"
    private let availability = MCPModernAvailability(tools: [
        MCPModernAvailableTool(name: "query_tasks", execution: .coveredRead),
        MCPModernAvailableTool(name: "update_task", execution: .protectedWrite),
        MCPModernAvailableTool(name: "café", execution: .ordinaryRead)
    ])

    private func envelope(
        method: String = "tools/call", id: Any = "request-1", name: Any = "query_tasks",
        version: Any = "2026-07-28", capabilities: Any = [String: Any](),
        arguments: Any = [String: Any]()
    ) -> [String: Any] {
        var params: [String: Any] = ["_meta": [
            "io.modelcontextprotocol/protocolVersion": version,
            "io.modelcontextprotocol/clientCapabilities": capabilities
        ]]
        if method == "tools/call" { params["name"] = name; params["arguments"] = arguments }
        return ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
    }

    private func input(
        _ body: Any, method: String = "tools/call", name: String? = "query_tasks",
        version: String = "2026-07-28", httpMethod: String = "POST",
        overrides: [String: String] = [:], extra: [MCPModernHeader] = []
    ) throws -> MCPModernRequestInput {
        var headers = ["Content-Type": "application/json",
                       "Accept": "application/json, text/event-stream",
                       "MCP-Protocol-Version": version, "Mcp-Method": method]
        if let name { headers["Mcp-Name"] = name }
        for (key, value) in overrides { headers[key] = value }
        return MCPModernRequestInput(httpMethod: httpMethod,
            headers: headers.map { MCPModernHeader(name: $0.key, value: $0.value) } + extra,
            body: try JSONSerialization.data(withJSONObject: body,
                                             options: [.fragmentsAllowed, .withoutEscapingSlashes]))
    }

    private func rejection(_ input: MCPModernRequestInput) throws -> MCPModernRejection {
        do {
            _ = try MCPModernValidator.validate(input, availability: availability)
            Issue.record("Invalid protocol input was accepted")
            throw FixtureFailure.expectedRejection
        } catch let error as MCPModernRejection { return error }
    }

    private enum FixtureFailure: Error { case expectedRejection }

    @Test func validRequestUsesImmutableAvailabilityAndLeavesDomainArgumentsForAdmission() throws {
        let request = try MCPModernValidator.validate(
            input(envelope(arguments: ["limit": -1, "displayId": "invalid"])),
            availability: availability)
        #expect(request.id == .string("request-1"))
        #expect(request.metadata.protocolVersion == version)
        #expect(request.metadata.clientInfo == nil)
        if case .callTool(let name, .coveredRead) = request.method {
            #expect(name == "query_tasks")
        } else { Issue.record("Expected covered-read classification") }
        #expect(request.params != nil)
    }

    @Test(arguments: ["server/discover", "tools/list", "subscriptions/listen"])
    func requestOnlyMethodsAreStateless(method: String) throws {
        var body = envelope(method: method, id: 17)
        if method == "subscriptions/listen" {
            var params = try #require(body["params"] as? [String: Any])
            params["notifications"] = ["toolsListChanged": true]
            body["params"] = params
        }
        let request = try MCPModernValidator.validate(input(body, method: method, name: nil),
                                                      availability: availability)
        #expect(request.id == .integer(17))
        switch request.method {
        case .discover: #expect(method == "server/discover")
        case .listTools: #expect(method == "tools/list")
        case .listenSubscriptions: #expect(method == "subscriptions/listen")
        case .callTool: Issue.record("Unexpected tool call")
        }
    }

    @Test(arguments: ["protocolVersion", "clientCapabilities"])
    func missingMetadataHasStandardError(field: String) throws {
        var body = envelope()
        var params = try #require(body["params"] as? [String: Any])
        var meta = try #require(params["_meta"] as? [String: Any])
        meta.removeValue(forKey: "io.modelcontextprotocol/" + field)
        params["_meta"] = meta; body["params"] = params
        let error = try rejection(input(body))
        #expect(error.httpStatus == 400)
        #expect(error.rpcCode == -32602)
        #expect(error.id == .string("request-1"))
    }

    @Test func metadataShapePrecedesHeaderComparison() throws {
        let error = try rejection(input(envelope(capabilities: []),
                                        overrides: ["Mcp-Method": "tools/list"]))
        #expect(error.rpcCode == -32602)
    }

    @Test(arguments: ["roots", "sampling", "elicitation", "extensions", "experimental"])
    func knownCapabilitiesRequireObjects(field: String) throws {
        let error = try rejection(input(envelope(capabilities: [field: true])))
        #expect(error.rpcCode == -32602)
    }

    @Test func unknownExtensionMetadataAndEmptyCapabilitiesDoNotRequireOptionalFeatures() throws {
        var body = envelope()
        var params = try #require(body["params"] as? [String: Any])
        var meta = try #require(params["_meta"] as? [String: Any])
        meta["com.example/context"] = ["unknown": NSNull()]
        params["_meta"] = meta; body["params"] = params
        _ = try MCPModernValidator.validate(input(body), availability: availability)
        let second = try MCPModernValidator.validate(input(envelope(id: "fresh")),
                                                    availability: availability)
        #expect(second.metadata.clientCapabilities == .object([]))
    }

    @Test(arguments: ["MCP-Protocol-Version", "Mcp-Method", "Mcp-Name"])
    func requiredHeaderMissingConflictingOrDuplicatedIsRejected(header: String) throws {
        let original = try input(envelope())
        let missing = MCPModernRequestInput(httpMethod: "POST",
            headers: original.headers.filter { $0.name != header }, body: original.body)
        #expect(try rejection(missing).rpcCode == -32020)
        #expect(try rejection(input(envelope(), overrides: [header: "mismatch"])).rpcCode == -32020)
        let duplicate = try input(envelope(), extra: [MCPModernHeader(name: header.lowercased(), value: "other")])
        #expect(try rejection(duplicate).rpcCode == -32020)
    }

    @Test func headerNamesAreCaseInsensitiveButValuesAreExact() throws {
        let original = try input(envelope())
        let lowered = MCPModernRequestInput(httpMethod: "POST", headers: original.headers.map {
            MCPModernHeader(name: $0.name.lowercased(), value: $0.value)
        }, body: original.body)
        _ = try MCPModernValidator.validate(lowered, availability: availability)
        #expect(try rejection(input(envelope(), overrides: ["Mcp-Method": "TOOLS/CALL"])).rpcCode == -32020)
    }

    @Test func matchingUnsupportedVersionReportsSupportedAndMismatchWins() throws {
        let error = try rejection(input(envelope(version: "2025-11-25"), version: "2025-11-25"))
        #expect(error.httpStatus == 400)
        #expect(error.rpcCode == -32022)
        guard case .object(let fields) = error.data else {
            Issue.record("Unsupported version must supply structured negotiation evidence")
            return
        }
        #expect(fields.first { $0.name == "requested" }?.value == .string("2025-11-25"))
        #expect(fields.first { $0.name == "supported" }?.value == .array([.string(version)]))
        let mismatch = try rejection(input(envelope(version: "2025-11-25")))
        #expect(mismatch.rpcCode == -32020)
    }

    @Test func base64NameDecodesUTF8AndRejectsMalformedTokens() throws {
        let name = "café"
        let encoded = "=?base64?" + Data(name.utf8).base64EncodedString() + "?="
        _ = try MCPModernValidator.validate(input(envelope(name: name), name: encoded), availability: availability)
        for invalid in ["=?base64?%%%?=", "=?base64?/w==?=", "=?base64?Y2Fmw6k=", name] {
            #expect(try rejection(input(envelope(name: name), name: invalid)).rpcCode == -32020)
        }
    }

    @Test(arguments: ["initialize", "ping", "resources/list", "unknown/method"])
    func unsupportedMethodsHaveNoLegacyDispatch(method: String) throws {
        let error = try rejection(input(envelope(method: method), method: method, name: nil))
        #expect(error.httpStatus == 404)
        #expect(error.rpcCode == -32601)
    }

    @Test func unavailableToolAndMalformedNameAreProtocolErrors() throws {
        #expect(try rejection(input(envelope(name: "disabled_tool"), name: "disabled_tool")).rpcCode == -32602)
        #expect(try rejection(input(envelope(name: 42))).rpcCode == -32602)
    }

    @Test func arraysNullAndInvalidIDsNeverBecomeDispatchableRequests() throws {
        let arrayError = try rejection(input([envelope(), envelope(id: "second")]))
        #expect(arrayError.rpcCode == -32600)
        #expect(arrayError.id == nil)
        for invalid: Any in [NSNull(), true, 1.5, ["nested": "id"]] {
            let error = try rejection(input(envelope(id: invalid)))
            #expect(error.httpStatus == 400)
            #expect(error.rpcCode == -32600)
            #expect(error.id == nil)
        }
        var wrongEnvelope = envelope(id: 9)
        wrongEnvelope["jsonrpc"] = "1.0"
        #expect(try rejection(input(wrongEnvelope)).id == .integer(9))
    }

    @Test func notificationsRejectWithoutFabricatedRPCResponse() throws {
        for method in ["tools/call", "notifications/initialized", "notifications/cancelled"] {
            var body = envelope(method: method)
            body.removeValue(forKey: "id")
            let error = try rejection(input(body, method: method, name: method == "tools/call" ? "query_tasks" : nil))
            #expect(error.httpStatus == 400)
            #expect(error.rpcCode == nil)
            #expect(error.id == nil)
        }
    }

    @Test func duplicateMetadataKeysAreNotSilentlyCollapsed() throws {
        let original = try input(envelope())
        let text = try #require(String(data: original.body, encoding: .utf8))
        let field = "\"io.modelcontextprotocol/protocolVersion\""
        let malformed = text.replacingOccurrences(of: field + ":\"2026-07-28\"",
            with: field + ":\"2026-07-28\"," + field + ":\"2025-11-25\"")
        #expect(malformed != text)
        let error = try rejection(MCPModernRequestInput(httpMethod: "POST", headers: original.headers,
                                                       body: Data(malformed.utf8)))
        #expect(error.httpStatus == 400)
        #expect(error.rpcCode == -32700)
    }

    @Test func knownNestedCapabilityAndClientInfoShapesAreValidated() throws {
        for capabilities: Any in [["sampling": ["tools": true]], ["elicitation": ["form": []]],
                                  ["extensions": ["com.example/feature": false]]] {
            #expect(try rejection(input(envelope(capabilities: capabilities))).rpcCode == -32602)
        }
        var body = envelope()
        var params = try #require(body["params"] as? [String: Any])
        var meta = try #require(params["_meta"] as? [String: Any])
        meta["io.modelcontextprotocol/clientInfo"] = ["name": "fixture"]
        params["_meta"] = meta; body["params"] = params
        #expect(try rejection(input(body)).rpcCode == -32602)
    }

    @Test func deterministicHostileHeaderCorpusNeverProducesValidClassification() throws {
        // Enumerate rather than randomize so every hostile byte is reproducible.
        for byte in [UInt8(0), 10, 13, 31, 127, 128, 255] {
            let value = "query_tasks" + String(UnicodeScalar(byte))
            let error = try rejection(input(envelope(), name: value))
            #expect(error.httpStatus == 400)
            #expect(error.rpcCode == -32020)
        }
    }

    @Test func malformedJSONHasNoInventedID() throws {
        let original = try input(envelope())
        let error = try rejection(MCPModernRequestInput(httpMethod: "POST", headers: original.headers,
                                                       body: Data("{invalid".utf8)))
        #expect(error.httpStatus == 400)
        #expect(error.rpcCode == -32700)
        #expect(error.id == nil)
    }

    @Test(arguments: ["GET", "DELETE", "PATCH"])
    func unsupportedHTTPMethodsCannotOpenLegacyStreams(method: String) throws {
        #expect(try rejection(input(envelope(), httpMethod: method)).httpStatus == 405)
    }

    @Test func contentAndAcceptNegotiationFailBeforeClassification() throws {
        #expect(try rejection(input(envelope(), overrides: ["Content-Type": "text/plain"])).httpStatus == 415)
        #expect(try rejection(input(envelope(), overrides: ["Accept": "text/html"])).httpStatus == 406)
        var body = envelope(method: "subscriptions/listen")
        var params = try #require(body["params"] as? [String: Any])
        params["notifications"] = ["toolsListChanged": true]; body["params"] = params
        #expect(try rejection(input(body, method: "subscriptions/listen", name: nil,
                                    overrides: ["Accept": "application/json"])).httpStatus == 406)
    }
}

extension MCPModernProtocolTests {
    // Supplemental boundary coverage added after the original declaration-stage RED.
    private func rawInput(id: String = "1", padding: String = "0") throws -> MCPModernRequestInput {
        let template = try input(envelope())
        let body = """
        {"jsonrpc":"2.0","id":\(id),"method":"tools/call","params":{
          "name":"query_tasks","arguments":{},"padding":\(padding),"_meta":{
            "io.modelcontextprotocol/protocolVersion":"2026-07-28",
            "io.modelcontextprotocol/clientCapabilities":{}}}}
        """
        return MCPModernRequestInput(httpMethod: "POST", headers: template.headers, body: Data(body.utf8))
    }

    @Test func numericIDsUseExactIntegralSemanticsWithinSignedIntResourceBound() throws {
        let cases: [(String, Int)] = [
            (String(Int.min), Int.min), (String(Int.max), Int.max),
            ("1.0", 1), ("1e0", 1), ("1000e-3", 1), ("0.01e2", 1),
            ("-1000.00e-2", -10), ("0e999999", 0), ("-0.000e-999999", 0)
        ]
        for (token, value) in cases {
            let request = try MCPModernValidator.validate(rawInput(id: token), availability: availability)
            #expect(request.id == .integer(value))
        }
    }

    @Test func outOfRangeAndNonIntegralNumericIDsNeverBecomeDispatchable() throws {
        for token in ["9223372036854775808", "-9223372036854775809", "1e999999", "1.5", "1e-1"] {
            let error = try rejection(rawInput(id: token))
            #expect(error.httpStatus == 400)
            #expect(error.rpcCode == -32600)
            #expect(error.id == nil)
            #expect(error.message.contains("use a string ID"))
        }
        #expect(try rejection(rawInput(id: "true")).rpcCode == -32600)
    }

    @Test func validJSONDepthLimitIsDistinctFromParseFailure() throws {
        // Root and params consume two containers; thirty arrays reaches exactly 32.
        let atLimit = String(repeating: "[", count: 30) + "0" + String(repeating: "]", count: 30)
        _ = try MCPModernValidator.validate(rawInput(padding: atLimit), availability: availability)
        let beyondLimit = "[" + atLimit + "]"
        let error = try rejection(rawInput(padding: beyondLimit))
        #expect(error.httpStatus == 400)
        #expect(error.rpcCode == -32600)
        #expect(error.message.contains("32-container nesting resource limit"))
        #expect(error.id == nil)
    }

    @Test func bodyAndWidthBoundsAreIndependentOfNestingLimit() throws {
        let wide = "{" + (0..<128).map { "\"field\($0)\":0" }.joined(separator: ",") + "}"
        _ = try MCPModernValidator.validate(rawInput(padding: wide), availability: availability)
        let original = try rawInput()
        var oversized = Data(repeating: 0x20, count: 1_048_576)
        oversized.append(original.body)
        let error = try rejection(MCPModernRequestInput(httpMethod: "POST", headers: original.headers,
                                                       body: oversized))
        #expect(error.httpStatus == 413)
    }

}

// Critic supplemental RED: the production validator remains at 3cfd28a.
extension MCPModernProtocolTests {
    private func subscriptionInput(_ filters: [String: Any]) throws -> MCPModernRequestInput {
        var body = envelope(method: "subscriptions/listen")
        var params = try #require(body["params"] as? [String: Any])
        params["notifications"] = filters
        body["params"] = params
        return try input(body, method: "subscriptions/listen", name: nil)
    }

    @Test func validUnsupportedResourceSubscriptionsDoNotRejectMixedFilters() throws {
        let request = try MCPModernValidator.validate(subscriptionInput([
            "toolsListChanged": true, "resourcesListChanged": true,
            "resourceSubscriptions": ["file:///synthetic/one", "file:///synthetic/two"]
        ]), availability: availability)
        guard case .listenSubscriptions = request.method else {
            Issue.record("Expected subscription classification")
            return
        }
        // A future stream acknowledges only toolsListChanged; unsupported valid
        // filters must survive protocol validation without acquiring resources.
        #expect(request.params != nil)
    }

    @Test func malformedResourceSubscriptionsStillRejectBeforeDispatch() throws {
        for invalid: Any in ["file:///synthetic/one", [true], ["valid", NSNull()]] {
            let error = try rejection(subscriptionInput(["toolsListChanged": true,
                                                         "resourceSubscriptions": invalid]))
            #expect(error.httpStatus == 400)
            #expect(error.rpcCode == -32602)
        }
    }

    private func classifySyntheticName(_ name: String, header: String) throws -> MCPModernRequest {
        let available = MCPModernAvailability(tools: [
            MCPModernAvailableTool(name: name, execution: .ordinaryRead)
        ])
        return try MCPModernValidator.validate(input(envelope(name: name), name: header), availability: available)
    }

    private func encodedName(_ name: String) -> String {
        "=?base64?" + Data(name.utf8).base64EncodedString() + "?="
    }

    @Test func paddedPlainNamesRequireEncodingEvenWhenTheyMatchBody() throws {
        for name in [" padded", "padded ", " padded "] {
            #expect(throws: MCPModernRejection.self) {
                _ = try classifySyntheticName(name, header: name)
            }
            let request = try classifySyntheticName(name, header: encodedName(name))
            guard case .callTool(let actual, .ordinaryRead) = request.method else {
                Issue.record("Expected synthetic name classification")
                continue
            }
            #expect(actual.utf8.elementsEqual(name.utf8))
        }
    }

    @Test func sentinelRequiresBothExactMarkersAndLiteralSentinelIsOuterEncoded() throws {
        for name in ["=?base64?prefix-only", "suffix-only?=", "=?BASE64?literal?="] {
            _ = try classifySyntheticName(name, header: name)
        }
        let literal = "=?base64?YQ==?="
        _ = try classifySyntheticName(literal, header: encodedName(literal))
        #expect(throws: MCPModernRejection.self) {
            _ = try classifySyntheticName(literal, header: literal)
        }
    }
}

#endif
