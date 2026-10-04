#if os(macOS)
import Foundation

/// Performs only protocol validation and immutable availability classification.
nonisolated enum MCPModernValidator {
    static let protocolVersion = "2026-07-28"

    /// Run Origin/Host and content negotiation before the transport reads a request body.
    static func validateTransport(_ input: MCPModernRequestInput) throws {
        try validateHTTP(input)
    }

    static func validate(
        _ input: MCPModernRequestInput,
        availability: MCPModernAvailability
    ) throws -> MCPModernRequest {
        try validateHTTP(input)
        let envelope = try envelope(input)
        let document = envelope.document
        let id = envelope.id
        let method = envelope.method
        let params = envelope.params
        guard let meta = params.field("_meta"), meta.isObject else {
            throw reject(400, -32602, "Required per-request metadata is missing", id: id)
        }
        let metadata = try clientMetadata(meta, id: id)
        try validateHeaders(input, method: method, params: params, metadata: metadata, id: id)
        guard metadata.protocolVersion == protocolVersion else {
            throw reject(400, -32022, "Unsupported protocol version", id: id, data: .object([
                MCPJSONMember(name: "requested", value: .string(metadata.protocolVersion)),
                MCPJSONMember(name: "supported", value: .array([.string(protocolVersion)]))
            ]))
        }
        let classification = try classify(method, params: params, availability: availability, id: id)
        if case .listenSubscriptions = classification {
            guard accepts("text/event-stream", input: input) else {
                throw reject(406, nil, "Subscriptions require text/event-stream", id: id)
            }
        } else {
            guard accepts("application/json", input: input) else {
                throw reject(406, nil, "Complete responses require application/json", id: id)
            }
        }
        return MCPModernRequest(id: id, method: classification, params: params,
                                metadata: metadata, document: document)
    }

    private static func validateHTTP(_ input: MCPModernRequestInput) throws {
        try validateOrigin(input)
        guard input.httpMethod == "POST" else { throw reject(405, nil, "Only POST is supported") }
        try validateContentType(input)
        guard accepts("application/json", input: input) || accepts("text/event-stream", input: input) else {
            throw reject(406, nil, "No acceptable response format")
        }
    }

    private struct Envelope {
        let document: MCPJSONDocument
        let id: JSONRPCId
        let method: String
        let params: MCPJSONValue
    }

    private static func envelope(
        _ input: MCPModernRequestInput
    ) throws -> Envelope {
        guard input.body.count <= 1_048_576 else { throw reject(413, nil, "Request body exceeds limit") }
        let document: MCPJSONDocument
        do {
            document = try MCPJSONDocument.parse(input.body)
        } catch MCPResultBoundaryError.resourceLimit {
            throw reject(400, -32600, "Request JSON exceeds the 32-container nesting resource limit")
        } catch {
            throw reject(400, -32700, "Invalid JSON")
        }
        guard case .object = document.value else { throw reject(400, -32600, "Expected one request object") }
        let root = document.value
        let id = requestID(root.field("id"))
        guard root.field("jsonrpc")?.text == "2.0", let method = root.field("method")?.text else {
            throw reject(400, -32600, "Invalid JSON-RPC envelope", id: id)
        }
        guard root.field("id") != nil else {
            throw reject(400, nil, "Client notifications are unsupported over HTTP")
        }
        guard let id else {
            if case .number = root.field("id") {
                throw reject(400, -32600,
                    "Numeric request ID must be integral and between \(Int.min) and \(Int.max); "
                        + "use a string ID outside this range")
            }
            throw reject(400, -32600, "Request ID must be a string or integer")
        }
        guard let params = root.field("params"), params.isObject else {
            throw reject(400, -32602, "Required request parameters are missing", id: id)
        }
        return Envelope(document: document, id: id, method: method, params: params)
    }

    private static func classify(
        _ method: String, params: MCPJSONValue, availability: MCPModernAvailability, id: JSONRPCId
    ) throws -> MCPModernMethod {
        switch method {
        case "server/discover": return .discover
        case "tools/list": return .listTools
        case "tools/call":
            guard let name = params.field("name")?.text,
                  let tool = availability.tools.first(where: { $0.name.utf8.elementsEqual(name.utf8) }) else {
                throw reject(400, -32602, "Tool name is missing or unavailable", id: id)
            }
            // Domain arguments, including their shape, are the admitted worker's responsibility.
            return .callTool(name: name, execution: tool.execution)
        case "subscriptions/listen":
            guard let notifications = params.field("notifications"), case .object(let fields) = notifications else {
                throw reject(400, -32602, "Subscription notifications must be an object", id: id)
            }
            try validateSubscriptionFilters(fields, id: id)
            return .listenSubscriptions
        default: throw reject(404, -32601, "Method is unavailable", id: id)
        }
    }

    private static func validateSubscriptionFilters(_ fields: [MCPJSONMember], id: JSONRPCId) throws {
        for field in fields {
            switch field.name {
            case "toolsListChanged", "promptsListChanged", "resourcesListChanged":
                guard case .boolean = field.value else {
                    throw reject(400, -32602, "List-change notification filters must be Boolean", id: id)
                }
            case "resourceSubscriptions":
                guard case .array(let uris) = field.value, uris.allSatisfy({ $0.text != nil }) else {
                    throw reject(400, -32602, "Resource subscriptions must be an array of strings", id: id)
                }
            default:
                // The normative SubscriptionFilter JSON Schema leaves additional
                // properties unconstrained. Preserve valid unknown JSON; the stream
                // acknowledges only supported requested filters, never these extras.
                continue
            }
        }
    }

    private static func clientMetadata(_ meta: MCPJSONValue, id: JSONRPCId) throws -> MCPModernClientMetadata {
        guard let version = meta.field("io.modelcontextprotocol/protocolVersion")?.text,
              let capabilities = meta.field("io.modelcontextprotocol/clientCapabilities"), capabilities.isObject else {
            throw reject(400, -32602, "Invalid required per-request metadata", id: id)
        }
        if case .object(let fields) = meta, fields.contains(where: { !validMetaKey($0.name) }) {
            throw reject(400, -32602, "Invalid metadata key", id: id)
        }
        try validateCapabilities(capabilities, id: id)
        let info = meta.field("io.modelcontextprotocol/clientInfo")
        if let info {
            guard info.isObject, info.field("name")?.text != nil, info.field("version")?.text != nil else {
                throw reject(400, -32602, "Invalid client identity", id: id)
            }
        }
        return MCPModernClientMetadata(protocolVersion: version, clientCapabilities: capabilities, clientInfo: info)
    }

    private static func validateCapabilities(_ capabilities: MCPJSONValue, id: JSONRPCId) throws {
        for name in ["roots", "sampling", "elicitation", "experimental", "extensions"] {
            guard let value = capabilities.field(name) else { continue }
            guard value.isObject else { throw reject(400, -32602, "Invalid client capability", id: id) }
            if name == "experimental" || name == "extensions" {
                if case .object(let fields) = value, fields.contains(where: {
                    !$0.value.isObject || (name == "extensions" && !validMetaKey($0.name, requiresPrefix: true))
                }) {
                    throw reject(400, -32602, "Capability settings must be objects", id: id)
                }
            }
            let children = name == "sampling" ? ["tools", "context"] : name == "elicitation" ? ["form", "url"] : []
            for child in children {
                if let settings = value.field(child), !settings.isObject {
                    throw reject(400, -32602, "Capability settings must be objects", id: id)
                }
            }
        }
    }

    private static func validMetaKey(_ key: String, requiresPrefix: Bool = false) -> Bool {
        guard key.utf8.allSatisfy({ (0x20...0x7E).contains($0) }) else { return false }
        let segments = key.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count <= 2, !requiresPrefix || segments.count == 2 else { return false }
        func matches(_ text: Substring, _ pattern: String) -> Bool {
            text.range(of: pattern, options: .regularExpression) != nil
        }
        if segments.count == 2 {
            let labels = segments[0].split(separator: ".", omittingEmptySubsequences: false)
            guard labels.allSatisfy({ matches($0, "^[A-Za-z](?:[A-Za-z0-9-]*[A-Za-z0-9])?$") }) else {
                return false
            }
        }
        guard let name = segments.last else { return false }
        return name.isEmpty || matches(name, "^[A-Za-z0-9](?:[A-Za-z0-9_.-]*[A-Za-z0-9])?$")
    }

    private static func validateHeaders(
        _ input: MCPModernRequestInput, method: String, params: MCPJSONValue,
        metadata: MCPModernClientMetadata, id: JSONRPCId
    ) throws {
        let version = try requiredHeader("MCP-Protocol-Version", input: input, id: id)
        let mirroredMethod = try requiredHeader("Mcp-Method", input: input, id: id)
        guard version.utf8.elementsEqual(metadata.protocolVersion.utf8),
              mirroredMethod.utf8.elementsEqual(method.utf8) else {
            throw reject(400, -32020, "Header does not match request metadata or method", id: id)
        }
        if method == "tools/call" {
            guard let name = params.field("name")?.text else {
                throw reject(400, -32602, "Tool name must be a string", id: id)
            }
            let mirroredName = try requiredHeader("Mcp-Name", input: input, id: id)
            let decoded = try decodeName(mirroredName, id: id)
            guard decoded.utf8.elementsEqual(name.utf8) else {
                throw reject(400, -32020, "Mcp-Name does not match tool name", id: id)
            }
        }
    }

    private static func decodeName(_ name: String, id: JSONRPCId) throws -> String {
        guard name.utf8.allSatisfy({ (0x20...0x7E).contains($0) }) else {
            throw reject(400, -32020, "Mcp-Name must be printable ASCII or encoded UTF-8", id: id)
        }
        guard name.first != " ", name.last != " " else {
            throw reject(400, -32020, "Padded Mcp-Name values require Base64 encoding", id: id)
        }
        if name.hasPrefix("=?base64?"), name.hasSuffix("?=") {
            let token = String(name.dropFirst(9).dropLast(2))
            guard let data = Data(base64Encoded: token), data.base64EncodedString() == token,
                  let decoded = String(data: data, encoding: .utf8) else {
                throw reject(400, -32020, "Invalid encoded Mcp-Name", id: id)
            }
            return decoded
        }
        return name
    }

    private static func requiredHeader(
        _ name: String, input: MCPModernRequestInput, id: JSONRPCId
    ) throws -> String {
        let values = headers(name, input: input)
        guard values.count == 1, let value = values.first, !value.isEmpty,
              value.utf8.allSatisfy({ (0x20...0x7E).contains($0) }) else {
            throw reject(400, -32020, "Missing or conflicting " + name, id: id)
        }
        return value
    }

}

nonisolated private extension MCPModernValidator {
    static func validateOrigin(_ input: MCPModernRequestInput) throws {
        let origins = headers("Origin", input: input)
        let hosts = headers("Host", input: input)
        guard origins.count <= 1, hosts.count <= 1,
              MCPOriginValidator.rejectionReason(origin: origins.first, authority: hosts.first) == nil else {
            throw reject(403, nil, "Origin or Host is not allowed")
        }
    }

    private static func validateContentType(_ input: MCPModernRequestInput) throws {
        let values = headers("Content-Type", input: input)
        guard values.count == 1,
              values.first?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
                == "application/json" else { throw reject(415, nil, "Content-Type must be application/json") }
    }

    private static func accepts(_ media: String, input: MCPModernRequestInput) -> Bool {
        let ranges = headers("Accept", input: input).joined(separator: ",").split(separator: ",")
        var quality = -1.0
        var specificity = -1
        for range in ranges {
            let parts = range.split(separator: ";", omittingEmptySubsequences: false)
            let type = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let score = type == media ? 2 : type == media.split(separator: "/")[0] + "/*" ? 1 : type == "*/*" ? 0 : -1
            guard score >= 0 else { continue }
            var candidate = 1.0
            for parameter in parts.dropFirst() {
                let pair = parameter.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces).lowercased()
                }
                if pair.first == "q" {
                    guard pair.count == 2, let parsed = Double(pair[1]), (0...1).contains(parsed) else { return false }
                    candidate = parsed
                }
            }
            if score > specificity { specificity = score; quality = candidate } else if score == specificity {
                quality = max(quality, candidate)
            }
        }
        return quality > 0
    }

    private static func headers(_ name: String, input: MCPModernRequestInput) -> [String] {
        input.headers.filter { $0.name.lowercased() == name.lowercased() }.map(\.value)
    }

    private static func requestID(_ value: MCPJSONValue?) -> JSONRPCId? {
        switch value {
        case .string(let text): return .string(text)
        case .number(let number): return exactInteger(number.lexeme).map(JSONRPCId.integer)
        default: return nil
        }
    }

    /// JSON integer semantics include decimal/exponent spellings. Convert exact
    /// decimal digits, never Double/NSNumber, into the existing signed Int domain.
    private static func exactInteger(_ token: String) -> Int? {
        let negative = token.hasPrefix("-")
        let unsigned = negative ? String(token.dropFirst()) : token
        let exponentParts = unsigned.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        let decimal = exponentParts[0].split(separator: ".", omittingEmptySubsequences: false)
        var digits = String(decimal[0]) + (decimal.count == 2 ? String(decimal[1]) : "")
        if digits.allSatisfy({ $0 == "0" }) { return 0 }
        let exponent = exponentParts.count == 2 ? Int(exponentParts[1]) : 0
        guard let exponent, (-1_048_576...1_048_576).contains(exponent) else { return nil }
        let fractionCount = decimal.count == 2 ? decimal[1].count : 0
        let shift = exponent - fractionCount
        if shift < 0 {
            let removed = -shift
            guard removed < digits.count, digits.suffix(removed).allSatisfy({ $0 == "0" }) else { return nil }
            digits.removeLast(removed)
        }
        digits = String(digits.drop(while: { $0 == "0" }))
        if shift > 0 {
            guard digits.count + shift <= 19 else { return nil }
            digits += String(repeating: "0", count: shift)
        }
        guard digits.count <= 19 else { return nil }
        return Int((negative ? "-" : "") + digits)
    }

    private static func reject(
        _ status: Int, _ code: Int?, _ message: String, id: JSONRPCId? = nil, data: MCPJSONValue? = nil
    ) -> MCPModernRejection {
        MCPModernRejection(httpStatus: status, rpcCode: code, message: message, id: id, data: data)
    }
}

nonisolated private extension MCPJSONValue {
    func field(_ name: String) -> MCPJSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.name.utf8.elementsEqual(name.utf8) }?.value
    }

    var text: String? { if case .string(let text) = self { text } else { nil } }
    var isObject: Bool { if case .object = self { true } else { false } }
}
#endif
