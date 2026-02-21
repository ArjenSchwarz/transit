#if os(macOS)
import Foundation

// All types in this file are `nonisolated` because they are pure data types
// used across actor boundaries (NIO event loop ↔ MainActor).

// MARK: - JSON-RPC 2.0

nonisolated struct JSONRPCRequest: Decodable, Sendable {
    let jsonrpc: String
    let id: JSONRPCId?
    let method: String
    let params: AnyCodable?
}

nonisolated struct JSONRPCResponse: Encodable, Sendable {
    let jsonrpc: String = "2.0"
    let id: JSONRPCId?
    let result: AnyCodable?
    let error: JSONRPCError?

    static func success(id: JSONRPCId?, result: some Encodable) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: AnyCodable(result), error: nil)
    }

    static func error(
        id: JSONRPCId?,
        code: Int,
        message: String,
        data: (some Encodable)? = nil as String?
    ) -> JSONRPCResponse {
        JSONRPCResponse(
            id: id,
            result: nil,
            error: JSONRPCError(code: code, message: message, data: data.map { AnyCodable($0) })
        )
    }
}

nonisolated struct JSONRPCError: Encodable, Sendable {
    let code: Int
    let message: String
    let data: AnyCodable?
}

// MARK: - JSON-RPC Error Codes

nonisolated enum JSONRPCErrorCode {
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603
}

// MARK: - JSON-RPC ID (can be string or integer)

nonisolated enum JSONRPCId: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .integer(intVal)
            return
        }
        if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
            return
        }
        throw DecodingError.typeMismatch(
            JSONRPCId.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Expected string or integer")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let val): try container.encode(val)
        case .integer(let val): try container.encode(val)
        }
    }
}

// MARK: - MCP Initialize

nonisolated struct MCPInitializeResult: Encodable, Sendable {
    let protocolVersion: String
    let capabilities: MCPServerCapabilities
    let serverInfo: MCPServerInfo
}

nonisolated struct MCPServerCapabilities: Encodable, Sendable {
    let tools: MCPToolsCapability?
}

nonisolated struct MCPToolsCapability: Encodable, Sendable {
    // Empty object signals tool support
}

nonisolated struct MCPServerInfo: Encodable, Sendable {
    let name: String
    let version: String
}

// MARK: - MCP Tools

nonisolated struct MCPToolDefinition: Encodable, Sendable {
    let name: String
    let description: String
    let inputSchema: JSONSchema
}

nonisolated struct MCPToolsListResult: Encodable, Sendable {
    let tools: [MCPToolDefinition]
}

nonisolated struct MCPToolResult: Encodable, Sendable {
    let content: [MCPContent]
    let isError: Bool?
}

nonisolated struct MCPContent: Encodable, Sendable {
    let type: String
    let text: String

    static func text(_ text: String) -> MCPContent {
        MCPContent(type: "text", text: text)
    }
}

// MARK: - JSON Schema (for tool input definitions)

nonisolated struct JSONSchema: Encodable, Sendable {
    let type: String
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?

    static func object(
        properties: [String: JSONSchemaProperty],
        required: [String]
    ) -> JSONSchema {
        JSONSchema(type: "object", properties: properties, required: required)
    }
}

nonisolated struct JSONSchemaItems: Encodable, Sendable {
    let type: String?
    let enumValues: [String]?

    nonisolated enum CodingKeys: String, CodingKey {
        case type
        case enumValues = "enum"
    }
}

nonisolated struct JSONSchemaProperty: Encodable, Sendable {
    let type: String?
    let description: String?
    let enumValues: [String]?
    let items: JSONSchemaItems?

    nonisolated enum CodingKeys: String, CodingKey {
        case type, description, items
        case enumValues = "enum"
    }

    static func string(_ description: String) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "string", description: description, enumValues: nil, items: nil)
    }

    static func integer(_ description: String) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "integer", description: description, enumValues: nil, items: nil)
    }

    static func object(_ description: String) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "object", description: description, enumValues: nil, items: nil)
    }

    static func stringEnum(_ description: String, values: [String]) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "string", description: description, enumValues: values, items: nil)
    }

    static func boolean(_ description: String) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "boolean", description: description, enumValues: nil, items: nil)
    }

    static func array(
        _ description: String, itemType: String = "string", enumValues: [String]? = nil
    ) -> JSONSchemaProperty {
        JSONSchemaProperty(
            type: "array",
            description: description,
            enumValues: nil,
            items: JSONSchemaItems(type: itemType, enumValues: enumValues)
        )
    }
}

// MARK: - AnyCodable (type-erased Codable wrapper)

nonisolated struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: some Encodable) {
        self.value = value
    }

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let encodable as Encodable:
            try encodable.encode(to: encoder)
        default:
            throw EncodingError.invalidValue(
                value,
                .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "Unsupported type: \(type(of: value))"
                )
            )
        }
    }
}

#endif
