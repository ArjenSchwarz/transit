#if os(macOS)
import Foundation

nonisolated enum MCPBatchTaskOutputSchema {
    /// Generated schema data only. Historical JSON never passes through
    /// Foundation's value bridge; nested original payload accepts every JSON value.
    static func descriptor(description: String) throws -> MCPResultSchemaDescriptor {
        let common = try MCPResultSchemas.descriptor(tool: "mutate_tasks", description: description)
        guard var schema = try JSONSerialization.jsonObject(with: common.outputSchema.originalUTF8) as? [String: Any],
              var definitions = schema["$defs"] as? [String: Any],
              var jsonSource = definitions["jsonSource"] as? [String: Any],
              var properties = jsonSource["properties"] as? [String: Any] else {
            throw MCPResultBoundaryError.unsupportedEvidence
        }
        definitions["batchPayload"] = try JSONSerialization.jsonObject(with: logical().originalUTF8)
        properties["payload"] = ["$ref": "#/$defs/batchPayload"]
        jsonSource["properties"] = properties
        definitions["jsonSource"] = jsonSource
        schema["$defs"] = definitions
        return MCPResultSchemaDescriptor(tool: "mutate_tasks", description: description,
            outputSchema: try MCPJSONDocument.parse(
                JSONSerialization.data(withJSONObject: schema, options: .sortedKeys)))
    }

    static func logical() throws -> MCPJSONDocument {
        try MCPJSONDocument.parse(#"""
        {"type":"object","required":["contractVersion","summary"],"properties":{
          "contractVersion":{"const":1},"mode":{"enum":["dry_run","execute"]},"atomicity":{"const":"per_item"},
          "summary":{"enum":["preview_valid","preview_invalid","all_committed","stopped","interrupted",
                              "evidence_unavailable","rejected_input","serialization_failed"]},
          "confirmedCommittedCount":{"type":"integer","minimum":0,"maximum":50},
          "observedCancellation":{"type":"boolean"},"advisory":{"const":true},
          "observation":{"const":"saved_local_store"},"keyState":{"const":"unchecked"},
          "stop":{"type":"object","required":["reason","nextUnstartedIndex"],"properties":{
            "reason":{"enum":["item_result","evidence_unavailable","pending_edits","cancelled"]},
            "nextUnstartedIndex":{"type":"integer","minimum":0,"maximum":50},
            "blocker":{"type":"object","required":["index","itemId"],"properties":{
              "index":{"type":"integer"},"itemId":{"type":"string"}}}}},
          "items":{"type":"array","minItems":1,"maxItems":50,"items":{"type":"object",
            "required":["index","itemId","operation","idempotencyKey","taskId","state"],"properties":{
              "index":{"type":"integer"},"itemId":{"type":"string"},"operation":{"type":"string"},
              "idempotencyKey":{"type":"string"},"taskId":{"type":"string","format":"uuid"},
              "state":{"enum":["attempted","not_attempted","valid","invalid","unavailable"]},
              "originalResult":{"type":"object","required":["text"],"additionalProperties":false,
                "properties":{"text":{"type":"string"},"payload":{},"isError":{"type":"boolean"}}},
              "current":{},"proposedEffects":{},"diagnostic":{"type":"object"}}}},
          "diagnostics":{"type":"array"},"effectEvidence":{"const":"unestablished"},"recovery":{"type":"object"}
        }}
        """#)
    }
}
#endif
