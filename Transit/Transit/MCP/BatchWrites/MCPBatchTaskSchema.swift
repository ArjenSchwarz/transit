#if os(macOS)
import Foundation

/// Logical rich input descriptor only. Shared registration stays with its owner.
nonisolated enum MCPBatchTaskSchema {
    nonisolated struct ArgumentShape: Sendable {
        let properties: [String: JSONSchemaProperty]
        let required: [String]
    }

    static let operations = ["update_task", "update_task_status", "add_comment"]

    /// Public fields/types stay sourced from the actual protected definitions.
    /// Only batch targeting and metadata/domain-stage restrictions differ.
    static func arguments(_ operation: String) throws -> ArgumentShape {
        guard operations.contains(operation),
              let definition = MCPToolDefinitions.coreTools.first(where: { $0.name == operation }),
              var properties = definition.inputSchema.properties else {
            throw MCPResultBoundaryError.unsupportedEvidence
        }
        properties.removeValue(forKey: "displayId")
        properties.removeValue(forKey: "linkChanges")
        properties.removeValue(forKey: "endpointPreconditions")
        var required = definition.inputSchema.required ?? []
        if !required.contains("taskId") { required.append("taskId") }
        return ArgumentShape(properties: properties, required: required)
    }

    static func inputSchema() throws -> MCPJSONDocument {
        let branches = try operations.map(branch)
        let schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object",
            "additionalProperties": false, "required": ["mode", "items"],
            "properties": [
                "mode": ["type": "string", "enum": ["dry_run", "execute"]],
                "items": ["type": "array", "minItems": 1, "maxItems": 50,
                          "items": ["oneOf": branches]]
            ]
        ]
        return try MCPJSONDocument.parse(JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys]))
    }

    private static func branch(_ operation: String) throws -> [String: Any] {
        let shape = try arguments(operation)
        var fields: [String: Any] = [:]
        for (name, property) in shape.properties { fields[name] = field(name, property: property) }
        return [
            "type": "object", "additionalProperties": false, "required": ["itemId", "operation", "arguments"],
            "properties": [
                "itemId": ["type": "string", "minLength": 1, "pattern": "\\S",
                           "description": "Opaque nonblank caller mapping; preserved without trimming."],
                "operation": ["type": "string", "const": operation],
                "arguments": ["type": "object", "additionalProperties": false,
                              "properties": fields, "required": shape.required]
            ]
        ]
    }

    private static func field(_ name: String, property: JSONSchemaProperty) -> [String: Any] {
        var description = property.description ?? ""
        if let values = property.enumValues {
            description += " Supported values: " + values.joined(separator: ", ") +
                ". Invalid strings are item domain failures."
        }
        var result: [String: Any] = ["type": property.type ?? "string", "description": description]
        if let pattern = property.pattern { result["pattern"] = pattern }
        if name == "taskId" { result["format"] = "uuid" }
        if name == "metadata" { result["additionalProperties"] = ["type": "string"] }
        // No enum/const or conditional author requirement for domain values.
        return result
    }
}
#endif
