#if os(macOS)
import Foundation

/// Pure transport values. Logical result sources never pass through this request bridge.
nonisolated enum MCPModernWire {
    static func request(_ modern: MCPModernRequest, tool: String) -> JSONRPCRequest {
        var params: [String: Any] = ["name": tool]
        if case .object(let members) = modern.params,
           let arguments = members.first(where: { $0.name.utf8.elementsEqual("arguments".utf8) }) {
            params["arguments"] = (try? requestValue(arguments.value)) ?? UnsupportedArguments.value
        }
        return JSONRPCRequest(jsonrpc: "2.0", id: modern.id, method: "tools/call", params: AnyCodable(params))
    }

    /// Domain conversion never rejects before read admission. Unsupported numeric representations
    /// and Unicode-key collisions make the entire envelope unsupported; existing domain validation
    /// rejects that envelope inside its worker, without dropping fields or inventing defaults.
    private enum UnsupportedArguments: Error { case value }

    private static func requestValue(_ value: MCPJSONValue) throws -> Any {
        switch value {
        case .null: return NSNull()
        case .boolean(let value): return value
        case .string(let value): return value
        case .number(let value):
            guard let decoded = try? JSONDecoder().decode(AnyCodable.self, from: Data(value.lexeme.utf8)) else {
                throw UnsupportedArguments.value
            }
            return decoded.value
        case .array(let values): return try values.map(requestValue)
        case .object(let members):
            var object: [String: Any] = [:]
            for member in members {
                guard object[member.name] == nil else { throw UnsupportedArguments.value }
                object[member.name] = try requestValue(member.value)
            }
            return object
        }
    }

    static func error(_ rejection: MCPModernRejection) throws -> Data {
        var writer = MCPResultByteWriter(checkpoint: {})
        try writer.literal("{\"jsonrpc\":\"2.0\"")
        if let id = rejection.id {
            try writer.literal(",\"id\":")
            try writer.raw(JSONEncoder().encode(id))
        }
        try writer.literal(",\"error\":{\"code\":")
        try writer.literal(String(rejection.rpcCode ?? JSONRPCErrorCode.internalError))
        try writer.field("message", rejection.message)
        if let data = rejection.data {
            try writer.literal(",\"data\":")
            try write(data, to: &writer)
        }
        try writer.literal("}}")
        return writer.data
    }

    private static func write(_ value: MCPJSONValue, to writer: inout MCPResultByteWriter) throws {
        switch value {
        case .null: try writer.literal("null")
        case .boolean(let value): try writer.literal(value ? "true" : "false")
        case .string(let value): try writer.string(value)
        case .number(let value): try writer.literal(value.lexeme)
        case .array(let values):
            try writer.literal("[")
            for (index, value) in values.enumerated() {
                if index > 0 { try writer.literal(",") }
                try write(value, to: &writer)
            }
            try writer.literal("]")
        case .object(let members):
            try writer.literal("{")
            for (index, member) in members.enumerated() {
                if index > 0 { try writer.literal(",") }
                try writer.string(member.name)
                try writer.literal(":")
                try write(member.value, to: &writer)
            }
            try writer.literal("}")
        }
    }
}
#endif
