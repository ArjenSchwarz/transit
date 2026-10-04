#if os(macOS)
import Foundation

/// Owns the shallow batch failure payload; the common encoder owns all wire
/// bytes. Unbounded item IDs, records, text and navigation data never enter it.
nonisolated enum MCPBatchTaskFallback {
    static func source(items: [MCPBatchRecoveryItem]) throws -> MCPResultSource {
        guard (1...50).contains(items.count), items.enumerated().allSatisfy({ index, item in
            item.index == index && item.targetTaskId != nil &&
                ["update_task", "update_task_status", "add_comment"].contains(item.operation) &&
                item.operation.unicodeScalars.elementsEqual(item.originalKey.tool.unicodeScalars) &&
                validKey(item.originalKey.idempotencyKey)
        }) else { throw MCPResultBoundaryError.unsupportedEvidence }
        var writer = MCPResultByteWriter(checkpoint: {})
        try writer.literal("{\"contractVersion\":1,\"mode\":\"execute\",\"atomicity\":\"per_item\",")
        try writer.literal("\"summary\":\"serialization_failed\",\"effectEvidence\":\"unestablished\",")
        try writer.literal("\"recovery\":{\"direction\":\"reconcile_original_write\",\"items\":[")
        for (index, item) in items.enumerated() {
            if index > 0 { try writer.literal(",") }
            try writer.literal("{\"index\":\(item.index)")
            try writer.field("operation", item.operation)
            try writer.field("tool", item.originalKey.tool)
            try writer.field("idempotencyKey", item.originalKey.idempotencyKey)
            if let taskID = item.targetTaskId { try writer.field("targetTaskId", taskID.uuidString) }
            try writer.literal("}")
        }
        try writer.literal("]}}")
        guard let text = String(data: writer.data, encoding: .utf8) else {
            throw MCPResultBoundaryError.invalidJSON
        }
        return try MCPResultAdapter.source(text: text, isError: true,
                                           origin: .generatedJSON, evidence: .unestablished)
    }

    private static func validKey(_ key: String) -> Bool {
        guard (1...128).contains(key.utf8.count) else { return false }
        return key.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) ||
                [46, 95, 58, 45].contains($0)
        }
    }
}
#endif
