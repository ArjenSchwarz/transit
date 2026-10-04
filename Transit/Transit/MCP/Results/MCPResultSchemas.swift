#if os(macOS)
import Foundation

/// Descriptor data is independent of shared tool-definition registration.
nonisolated struct MCPResultSchemaDescriptor: Sendable {
    let tool: String
    let description: String
    let outputSchema: MCPJSONDocument
}

nonisolated enum MCPResultSchemas {
    static func descriptor(tool: String, description: String) throws -> MCPResultSchemaDescriptor {
        MCPResultSchemaDescriptor(tool: tool, description: description,
                                  outputSchema: try MCPJSONDocument.parse(schemaJSON))
    }

    /// Only the presentation contract is closed. Historic logical JSON remains
    /// unrestricted, including arbitrary names, nulls and exact numeric tokens.
    /// Provider descriptions document current payload shapes without making
    /// those shapes a restriction on saved outcomes or future batch providers.
    private static let schemaJSON = #"""
    {
      "$schema":"https://json-schema.org/draft/2020-12/schema",
      "title":"Transit structured result contract version 1",
      "description":"Immutable original source and separate presentation; text and isError remain in the tool result.",
      "type":"object",
      "required":["contractVersion","source","presentation"],
      "additionalProperties":false,
      "properties":{
        "contractVersion":{"type":"integer","const":1},
        "source":{"oneOf":[
          {"$ref":"#/$defs/jsonSource"},
          {"$ref":"#/$defs/textSource"},
          {"$ref":"#/$defs/unreadableSource"}
        ]},
        "presentation":{"$ref":"#/$defs/presentation"}
      },
      "if":{"properties":{"source":{"properties":{"kind":{"const":"unreadable"}}}}},
      "then":{"properties":{"presentation":{"properties":{"evidence":{"const":"unestablished"}}}}},
      "$defs":{
        "jsonSource":{
          "type":"object","required":["kind","payload"],"additionalProperties":false,
          "properties":{
            "kind":{"const":"json"},
            "payload":{"description":"Complete original JSON; historical fields and types are unrestricted."}
          }
        },
        "textSource":{
          "type":"object","required":["kind","payload"],"additionalProperties":false,
          "properties":{"kind":{"const":"text"},"payload":{"type":"string"}}
        },
        "unreadableSource":{
          "type":"object","required":["kind"],"additionalProperties":false,
          "properties":{"kind":{"const":"unreadable"}}
        },
        "uuid":{
          "type":"string","format":"uuid",
          "minLength":36,"maxLength":36,
          "pattern":"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
        },
        "jsonPointer":{
          "type":"string",
          "description":"RFC 6901 pointer to frozen source evidence; empty root or slash-separated escaped tokens.",
          "pattern":"^(?:/(?:[^~/]|~[01])*)*(?![\\s\\S])"
        },
        "link":{
          "type":"object",
          "required":["entityType","entityId","sourcePath","availability","reason"],
          "additionalProperties":false,
          "properties":{
            "entityType":{"type":"string","enum":["task","project"]},
            "entityId":{"$ref":"#/$defs/uuid"},
            "sourcePath":{"$ref":"#/$defs/jsonPointer"},
            "availability":{"const":"unavailable"},
            "reason":{"const":"navigation_not_supported"}
          }
        },
        "presentation":{
          "type":"object","required":["evidence","links"],"additionalProperties":false,
          "properties":{
            "evidence":{"type":"string","enum":["established","unestablished"]},
            "links":{"type":"array","items":{"$ref":"#/$defs/link"}},
            "errorCategory":{"type":"string","enum":[
              "invalid_input","not_found","ambiguous_identity","revision_conflict","key_conflict",
              "storage_failure","incoherent_capture","admission_busy","deadline_exceeded","retention_capacity",
              "invalid_cursor","expired_cursor","serialization_failure","outcome_uncertain",
              "unclassified_historical","internal_failure"
            ]},
            "recovery":{"oneOf":[
              {"$ref":"#/$defs/readRecovery"},
              {"$ref":"#/$defs/protectedRecovery"},
              {"$ref":"#/$defs/batchRecovery"},
              {"$ref":"#/$defs/maintenanceRecovery"}
            ]}
          }
        },
        "readRecovery":{
          "type":"object","required":["direction"],"additionalProperties":false,
          "properties":{"direction":{"type":"string","enum":["retry_identical_read","restart_read"]}}
        },
        "protectedRecovery":{
          "type":"object","required":["direction","tool","idempotencyKey"],"additionalProperties":false,
          "description":"Original protected identity from trusted provider evidence; no newly invented key.",
          "properties":{
            "direction":{"type":"string","enum":["follow_source","reconcile_original_write"]},
            "tool":{"type":"string"},"idempotencyKey":{"type":"string"}
          }
        },
        "batchRecovery":{
          "type":"object","required":["direction","items"],"additionalProperties":false,
          "description":"Ordered original item identities; no aggregate durable key namespace.",
          "properties":{
            "direction":{"const":"reconcile_original_write"},
            "items":{"type":"array","items":{"$ref":"#/$defs/batchRecoveryItem"}}
          }
        },
        "batchRecoveryItem":{
          "type":"object","required":["index","operation","tool","idempotencyKey"],"additionalProperties":false,
          "properties":{
            "index":{"type":"integer","minimum":0},
            "operation":{"type":"string"},"tool":{"type":"string"},"idempotencyKey":{"type":"string"},
            "itemId":{"type":"string"},"targetTaskId":{"$ref":"#/$defs/uuid"}
          }
        },
        "maintenanceRecovery":{
          "type":"object","required":["direction","tool"],"additionalProperties":false,
          "properties":{"direction":{"const":"reconcile_maintenance"},"tool":{"type":"string"}}
        }
      }
    }
    """#
}
#endif
