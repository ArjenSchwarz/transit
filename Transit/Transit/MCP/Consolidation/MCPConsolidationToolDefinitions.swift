#if os(macOS)
import Foundation
/// Complete public contracts, registered only with the app's full consolidation capability.
nonisolated enum MCPConsolidationToolDefinitions {
    static let previewTools: Set<String> = ["preview_task_consolidation", "preview_task_consolidation_undo"]
    static var tools: [MCPToolDefinition] {
        [previewApply, previewUndo] + ["consolidate_tasks", "undo_task_consolidation"].compactMap {
            MCPConsolidationWriteDefinition.definition($0)
        }
    }
    static var previewApply: MCPToolDefinition {
        var candidates = JSONSchemaProperty.array("Ordered distinct candidate UUIDs, excluding the survivor")
        candidates.minItems = 1
        candidates.maxItems = 5
        candidates.uniqueItems = true
        var edits = JSONSchemaProperty.object("Only explicit survivor description and metadata edits")
        edits.properties = ["description": nullableDescription, "metadata": metadata]
        edits.additionalProperties = false
        return definition("preview_task_consolidation", description:
            "Read saved same-project originals, preservation accounting and planned duplicate mappings. "
            + "Returns a five-minute local review; no write or identifier allocation occurs.", properties: [
                "survivorTaskId": .string("Unique saved survivor task UUID"), "candidateTaskIds": candidates,
                "reason": nonblank("Nonblank durable explanation"),
                "preservation": preservation,
                "survivorEdits": edits, "readPolicy": readPolicy
            ], required: ["survivorTaskId", "candidateTaskIds", "reason", "preservation"])
    }
    static var previewUndo: MCPToolDefinition {
        definition("preview_task_consolidation_undo", description:
            "Read the exact whole reversal of a saved operation, current originals and undo availability. "
            + "Only an available inverse returns a five-minute local review; no data changes.", properties: [
                "operationId": .string("Original saved consolidation operation UUID"), "readPolicy": readPolicy
            ], required: ["operationId"])
    }
    private static func nonblank(_ description: String) -> JSONSchemaProperty {
        var value = JSONSchemaProperty.string(description)
        value.pattern = "\\S"
        return value
    }
    private static var metadata: JSONSchemaProperty {
        var value = JSONSchemaProperty.object("Replace metadata with an exact string-to-string dictionary")
        value.additionalProperties = .schema(JSONSchema(type: "string", properties: nil, required: nil))
        return value
    }
    private static var preservation: JSONSchemaProperty {
        var reference = JSONSchema.object(properties: ["sourceDetail": nonblank("Original detail accounted for"),
            "survivorField": .stringEnum("Explicit edited destination", values: ["description", "metadata"])],
            required: ["sourceDetail", "survivorField"])
        reference.additionalProperties = false
        var incorporated = JSONSchemaProperty.array("Explicit references to survivor edits", itemType: "object")
        incorporated.items = JSONSchemaItems(type: nil, enumValues: nil, oneOf: [reference])
        incorporated.minItems = 1
        var entry = JSONSchemaProperty.object("Incorporated, retained explanation, or both")
        entry.properties = ["incorporated": incorporated,
            "retainedExplanation": nonblank("Nonblank retention explanation")]
        entry.additionalProperties = false
        entry.anyOf = [JSONSchema(type: "object", properties: nil, required: ["incorporated"]),
                       JSONSchema(type: "object", properties: nil, required: ["retainedExplanation"])]
        var value = JSONSchemaProperty.object("Exactly one entry per selected candidate UUID")
        let uuidPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        value.patternProperties = [uuidPattern: entry]
        value.additionalProperties = false
        value.minProperties = 1
        value.maxProperties = 5
        return value
    }
    private static var nullableDescription: JSONSchemaProperty {
        var value = JSONSchemaProperty(type: nil, description: "Omit to preserve; null to clear; string to replace",
            enumValues: nil, items: nil)
        value.oneOf = [JSONSchema(type: "string", properties: nil, required: nil),
                       JSONSchema(type: "null", properties: nil, required: nil)]
        return value
    }
    private static var readPolicy: JSONSchemaProperty {
        .stringEnum("Saved-boundary capture policy", values: ["cached", "refresh_if_needed"])
    }
    private static func definition(_ name: String, description: String,
                                   properties: [String: JSONSchemaProperty], required: [String]) -> MCPToolDefinition {
        var schema = JSONSchema.object(properties: properties, required: required)
        schema.additionalProperties = false
        return MCPToolDefinition(name: name, description: description, inputSchema: schema)
    }
}
#endif
