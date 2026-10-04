#if os(macOS)
import Foundation

@MainActor enum MCPBatchTaskInputArguments {
    enum Validation {
        case valid([String: Any])
        case invalid(String)
    }

    static func validate(_ value: MCPJSONValue, operation: String) throws -> Validation {
        guard case .object(let members) = value else { return .invalid("arguments") }
        let shape = try MCPBatchTaskSchema.arguments(operation)
        if let field = MCPBatchTaskInputValue.closedField(members, allowed: Array(shape.properties.keys)) {
            return .invalid(field)
        }
        for field in shape.required where MCPBatchTaskInputValue.member(field, in: members) == nil {
            return .invalid(field)
        }
        var arguments: [String: Any] = [:]
        for member in members {
            guard let property = shape.properties[member.name] else { return .invalid(member.name) }
            switch try bridge(member.value, type: property.type, field: member.name) {
            case .invalid: return .invalid(member.name)
            case .valid(let value): arguments[member.name] = value
            }
        }
        return .valid(arguments)
    }

    private enum Bridged {
        case valid(Any)
        case invalid
    }

    private static func bridge(_ value: MCPJSONValue, type: String?, field: String) throws -> Bridged {
        switch type {
        case "string":
            guard case .string(let text) = value, validString(text, field: field) else { return .invalid }
            return .valid(text)
        case "integer":
            guard let integer = MCPBatchTaskInputValue.integer(value) else { return .invalid }
            return .valid(integer)
        case "boolean":
            guard case .boolean(let flag) = value else { return .invalid }
            return .valid(flag)
        case "object": return metadata(value)
        default: return .invalid
        }
    }

    private static func validString(_ text: String, field: String) -> Bool {
        switch field {
        case "idempotencyKey": return MCPBatchTaskInputValue.key(text)
        case "expectedRevision": return MCPBatchTaskEvidenceValidation.revision(.string(text))
        case "taskId": return UUID(uuidString: text) != nil
        default: return true // Domain strings, including empty values, are checked per item.
        }
    }

    private static func metadata(_ value: MCPJSONValue) -> Bridged {
        guard case .object(let members) = value else { return .invalid }
        var metadata: [String: String] = [:]
        for member in members {
            // The latest modern bridge also rejects canonical-equivalent names
            // that cannot survive [String: Any]. Never silently collapse a key.
            guard case .string(let text) = member.value, metadata[member.name] == nil else { return .invalid }
            metadata[member.name] = text
        }
        return .valid(metadata)
    }
}
#endif
