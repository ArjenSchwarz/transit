#if os(macOS)
import Foundation
/// Private owned-execution contracts; advertised registration is a later gate.
nonisolated enum MCPConsolidationWriteDefinition {
    static let tools: Set<String> = ["consolidate_tasks", "undo_task_consolidation"]
    static func definition(_ tool: String) -> MCPToolDefinition? {
        guard tools.contains(tool) else { return nil }
        var properties: [String: JSONSchemaProperty] = [
            "idempotencyKey": .string("Required local protected-write key"),
            "reviewId": .string("Exact retained review identity"),
            "reviewRevision": .string("Exact retained p1 content revision")
        ]
        var required = ["idempotencyKey", "reviewId", "reviewRevision"]
        if tool == "consolidate_tasks" {
            var acknowledgment = JSONSchemaProperty.boolean("Explicit review acknowledgment")
            acknowledgment.const = true
            properties["preservationAcknowledged"] = acknowledgment
            required.append("preservationAcknowledged")
        } else {
            properties["operationId"] = .string("Original saved operation identity")
            required.append("operationId")
        }
        var schema = JSONSchema.object(properties: properties, required: required)
        schema.additionalProperties = false
        return MCPToolDefinition(name: tool, description: tool == "consolidate_tasks"
            ? "Commit an exactly acknowledged retained review in one local protected save; "
                + "preserves originals and comments"
            : "Reverse one saved consolidation wholly against its exact current review, "
                + "or reconcile an already saved reversal", inputSchema: schema)
    }
    @MainActor static func validate(tool: String, arguments: [String: Any]) throws {
        guard let raw = arguments["reviewId"] as? String, UUID(uuidString: raw) != nil,
              let revision = arguments["reviewRevision"] as? String,
              revision.range(of: "^p1:[0-9a-f]{64}$", options: .regularExpression)
                == revision.startIndex..<revision.endIndex else {
            throw MCPWriteFailure("INVALID_INPUT", "A valid exact reviewId and p1 reviewRevision are required")
        }
        if tool == "consolidate_tasks" {
            guard let acknowledged = arguments["preservationAcknowledged"],
                  try MCPCanonicalJSON.encode(acknowledged) == "true" else {
                throw MCPWriteFailure("INVALID_INPUT", "preservationAcknowledged must be true")
            }
        } else {
            guard let raw = arguments["operationId"] as? String, UUID(uuidString: raw) != nil else {
                throw MCPWriteFailure("INVALID_INPUT", "operationId must be a UUID")
            }
        }
    }
}
#endif
