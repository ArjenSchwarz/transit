#if os(macOS)
import Foundation

extension MCPToolDefinitions {
    nonisolated private static let writeSafetyContract = """
        Requires a case-sensitive idempotencyKey matching [A-Za-z0-9._:-]{1,128}. \
        Retried identical arguments replay the original saved outcome for seven days across local-store restarts; \
        JSON object order is ignored and different payloads return IDEMPOTENCY_KEY_REUSED. \
        Results are JSON committed/rejected/in_progress/uncertain envelopes with saved records and r1 revisions. \
        Replay expiry is fixed; after it a retry may execute again. Uncertain outcomes require reconciliation; \
        never retry them with a fresh key. Revisions compare exact locally observed content, remain stable for no-ops \
        and restored content, and cannot detect edits not yet imported from CloudKit or prevent later sync conflicts. \
        Read a task or milestone first, write with its expectedRevision and a fresh key, then retry identical \
        arguments \
        with that key after a timeout. REVISION_CONFLICT returns the currentRecord and no effect; use a new key after \
        reviewing it. Keys are scoped to this local store and tool, independently of connection/session/request ID. \
        Cross-device deduplication and atomic batches are not provided.
        """

    nonisolated static func protected(_ definition: MCPToolDefinition) -> MCPToolDefinition {
        var properties = definition.inputSchema.properties ?? [:]
        var key = JSONSchemaProperty.string("Required retry key; UUID strings are suitable")
        key.pattern = "^[A-Za-z0-9._:-]{1,128}$"
        properties["idempotencyKey"] = key
        let hasLinks = ["create_task", "update_task"].contains(definition.name)
        if hasLinks {
            properties["linkChanges"] = TaskLinkWireSchema.changes(creating: definition.name == "create_task")
            properties["endpointPreconditions"] = TaskLinkWireSchema.endpoints
        }
        var required = definition.inputSchema.required ?? []
        required.append("idempotencyKey")
        if ["update_task", "update_task_status", "update_milestone", "delete_milestone"].contains(definition.name) {
            var revision = JSONSchemaProperty.string("Required target revision from the full read response")
            revision.pattern = "^r1:[0-9a-f]{64}$"
            properties["expectedRevision"] = revision
            required.append("expectedRevision")
        }
        var schema = JSONSchema.object(properties: properties, required: required)
        schema.additionalProperties = false
        return MCPToolDefinition(
            name: definition.name,
            description: definition.description + " " + writeSafetyContract +
                (hasLinks ? " " + TaskLinkWireSchema.description : ""),
            inputSchema: schema)
    }

}

#endif
