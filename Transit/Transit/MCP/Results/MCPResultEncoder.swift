#if os(macOS)
import Foundation

/// Frozen tool-level fragments never retain the originating JSON-RPC ID.
nonisolated struct MCPResultToolFragment: Sendable {
    let encodedResult: Data

    fileprivate init(encodedResult: Data) {
        self.encodedResult = encodedResult
    }
}

/// Encoder boundaries return complete immutable response bytes, not closures.
nonisolated enum MCPResultEncoder {
    static func encode(
        source: MCPResultSource,
        presentation: MCPResultPresentation,
        id: JSONRPCId,
        metadata: MCPResultMetadata?,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> Data {
        let fragment = try freeze(source: source, presentation: presentation, metadata: metadata,
                                  checkpoint: checkpoint)
        return try encode(fragment: fragment, id: id, checkpoint: checkpoint)
    }

    /// Providers own the compact logical failure. No effects or delivery selection occur here.
    static func prepareMutationFallback(
        id: JSONRPCId,
        source: MCPResultSource,
        context: MCPResultContext,
        metadata: MCPResultMetadata?,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> Data {
        try checkpoint()
        guard let mutation = context.mutationRecovery else { throw MCPResultBoundaryError.unsupportedEvidence }
        let direction: MCPResultRecoveryDirection
        if case .unprotectedMaintenance = mutation {
            direction = .reconcileMaintenance
        } else {
            direction = .reconcileOriginalWrite
        }
        let presentation = MCPResultPresentation(evidence: .unestablished, links: [], errorCategory: .outcomeUncertain,
            recovery: MCPResultRecovery(direction: direction, mutation: mutation))
        var writer = MCPResultByteWriter(checkpoint: checkpoint)
        try writeTool(source: source, presentation: presentation, metadata: metadata,
                      omitBatchItemId: true, to: &writer)
        let fragment = MCPResultToolFragment(encodedResult: writer.data)
        return try encode(fragment: fragment, id: id, checkpoint: checkpoint)
    }

    static func freeze(
        source: MCPResultSource,
        presentation: MCPResultPresentation,
        metadata: MCPResultMetadata?,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> MCPResultToolFragment {
        try checkpoint()
        var writer = MCPResultByteWriter(checkpoint: checkpoint)
        try writeTool(source: source, presentation: presentation, metadata: metadata,
                      omitBatchItemId: false, to: &writer)
        try checkpoint()
        return MCPResultToolFragment(encodedResult: writer.data)
    }

    static func encode(
        fragment: MCPResultToolFragment,
        id: JSONRPCId,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> Data {
        try checkpoint()
        var writer = MCPResultByteWriter(checkpoint: checkpoint)
        try writer.literal("{\"jsonrpc\":\"2.0\",\"id\":")
        switch id {
        case .string(let value): try writer.string(value)
        case .integer(let value): try writer.literal(String(value))
        }
        try writer.literal(",\"result\":")
        try writer.raw(fragment.encodedResult)
        try writer.literal("}")
        try checkpoint()
        return writer.data
    }

    private static func writeTool(source: MCPResultSource, presentation: MCPResultPresentation,
                                  metadata: MCPResultMetadata?, omitBatchItemId: Bool,
                                  to writer: inout MCPResultByteWriter) throws {
        try writer.literal("{\"resultType\":\"complete\",\"content\":[{\"type\":\"text\",\"text\":")
        try writer.string(source.originalText)
        try writer.literal("}],\"structuredContent\":{\"contractVersion\":1,\"source\":{\"kind\":")
        try writer.string(source.kind.rawValue)
        switch source.kind {
        case .json:
            guard let document = source.document else { throw MCPResultBoundaryError.unsupportedEvidence }
            try writer.literal(",\"payload\":")
            try writer.raw(document.originalUTF8)
        case .text:
            try writer.literal(",\"payload\":")
            try writer.string(source.originalText)
        case .unreadable: break
        }
        try writer.literal("},\"presentation\":")
        try writePresentation(presentation, omitBatchItemId: omitBatchItemId, to: &writer)
        try writer.literal("}")
        if let isError = source.originalIsError {
            try writer.literal(isError ? ",\"isError\":true" : ",\"isError\":false")
        }
        if let metadata {
            try writer.literal(",\"_meta\":")
            try writer.raw(metadata.document.originalUTF8)
        }
        try writer.literal("}")
    }

    private static func writePresentation(_ value: MCPResultPresentation, omitBatchItemId: Bool,
                                          to writer: inout MCPResultByteWriter) throws {
        try writer.literal("{")
        try writer.field("evidence", value.evidence.rawValue, first: true)
        try writer.literal(",\"links\":[")
        for (index, link) in value.links.enumerated() {
            if index > 0 { try writer.literal(",") }
            try writer.literal("{")
            try writer.field("entityType", link.entityType.rawValue, first: true)
            try writer.field("entityId", link.entityId.uuidString)
            try writer.field("sourcePath", link.sourcePath)
            try writer.field("availability", link.availability)
            try writer.field("reason", link.reason)
            try writer.literal("}")
        }
        try writer.literal("]")
        if let category = value.errorCategory { try writer.field("errorCategory", category.rawValue) }
        if let recovery = value.recovery {
            try writer.literal(",\"recovery\":")
            try writeRecovery(recovery, omitBatchItemId: omitBatchItemId, to: &writer)
        }
        try writer.literal("}")
    }

    private static func writeRecovery(_ recovery: MCPResultRecovery, omitBatchItemId: Bool,
                                      to writer: inout MCPResultByteWriter) throws {
        try writer.literal("{")
        try writer.field("direction", recovery.direction.rawValue, first: true)
        switch recovery.mutation {
        case .protectedWrite(let key):
            try writer.field("tool", key.tool)
            try writer.field("idempotencyKey", key.idempotencyKey)
        case .unprotectedMaintenance(let tool): try writer.field("tool", tool)
        case .applicationBatch(let items):
            try writer.literal(",\"items\":[")
            for (index, item) in items.enumerated() {
                if index > 0 { try writer.literal(",") }
                try writer.literal("{\"index\":")
                try writer.literal(String(item.index))
                try writer.field("operation", item.operation)
                try writer.field("tool", item.originalKey.tool)
                try writer.field("idempotencyKey", item.originalKey.idempotencyKey)
                if let taskId = item.targetTaskId { try writer.field("targetTaskId", taskId.uuidString) }
                if !omitBatchItemId, let itemId = item.itemId { try writer.field("itemId", itemId) }
                try writer.literal("}")
            }
            try writer.literal("]")
        case nil: break
        }
        try writer.literal("}")
    }
}
#endif
