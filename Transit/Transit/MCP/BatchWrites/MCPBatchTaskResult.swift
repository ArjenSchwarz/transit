#if os(macOS)
import Foundation

/// Logical batch source only. Raw JSON comes exclusively from validated
/// documents; the common encoder owns modern envelopes and byte selection.
@MainActor enum MCPBatchTaskResult {
    static func execution(_ request: MCPBatchTaskRequest, report: MCPBatchTaskCoordinator.Report) throws
        -> MCPResultSource {
        guard request.mode == .execute, report.entries.count == request.items.count else {
            throw MCPResultBoundaryError.unsupportedEvidence
        }
        var writer = MCPResultByteWriter(checkpoint: {})
        try start(&writer, mode: "execute", summary: report.summary)
        try writer.literal(",\"confirmedCommittedCount\":\(report.confirmedCommittedCount)")
        if report.observedCancellation { try writer.literal(",\"observedCancellation\":true") }
        if let stop = report.stop { try writer.literal(",\"stop\":"); try writeStop(stop, into: &writer) }
        try writer.literal(",\"items\":[")
        for (index, pair) in zip(request.items, report.entries).enumerated() {
            let (item, entry) = pair
            guard item.index == index, entry.index == index, entry.taskID == item.targetTaskId,
                  entry.itemId.utf8.elementsEqual(item.itemId.utf8),
                  entry.operation.utf8.elementsEqual(item.operation.utf8),
                  entry.originalKey.utf8.elementsEqual(item.command.key.utf8) else {
                throw MCPResultBoundaryError.unsupportedEvidence
            }
            if index > 0 { try writer.literal(",") }
            try mapping(item, into: &writer)
            try writer.field("state", entry.state.rawValue)
            if let original = entry.originalResult {
                try writer.literal(",\"originalResult\":{")
                try writer.field("text", original.originalText, first: true)
                if let payload = original.document {
                    try writer.literal(",\"payload\":"); try writer.raw(payload.originalUTF8)
                }
                if let flag = original.originalIsError { try writer.literal(",\"isError\":\(flag ? "true" : "false")") }
                try writer.literal("}")
            }
            if entry.state == .notAttempted, let stop = report.stop {
                try writer.literal(",\"diagnostic\":"); try writeStop(stop, into: &writer)
            }
            try writer.literal("}")
        }
        try writer.literal("]}")
        return try source(writer, isError: report.isError)
    }

    static func preview(_ request: MCPBatchTaskRequest, report: MCPBatchTaskPreview.Report) throws
        -> MCPResultSource {
        guard request.mode == .dryRun, report.entries.count == request.items.count else {
            throw MCPResultBoundaryError.unsupportedEvidence
        }
        var writer = MCPResultByteWriter(checkpoint: {})
        try start(&writer, mode: "dry_run", summary: report.isError == true ? "preview_invalid" : "preview_valid")
        try writer.field("observation", report.observation)
        try writer.field("keyState", report.keyState)
        try writer.literal(",\"advisory\":true,\"items\":[")
        for (index, pair) in zip(request.items, report.entries).enumerated() {
            let (item, entry) = pair
            guard item.index == index, entry.index == index,
                  entry.itemId.utf8.elementsEqual(item.itemId.utf8) else {
                throw MCPResultBoundaryError.unsupportedEvidence
            }
            if index > 0 { try writer.literal(",") }
            try mapping(item, into: &writer)
            try writer.field("state", entry.state.rawValue)
            if let code = entry.code {
                try writer.literal(",\"diagnostic\":{"); try writer.field("code", code, first: true)
                try writer.literal("}")
            }
            if let current = entry.current { try writer.literal(",\"current\":"); try writer.raw(current.originalUTF8) }
            if let effects = entry.proposedEffects {
                try writer.literal(",\"proposedEffects\":"); try writer.raw(effects.originalUTF8)
            }
            try writer.literal("}")
        }
        try writer.literal("]}")
        return try source(writer, isError: report.isError)
    }

    static func invalidInput(_ diagnostics: [MCPBatchTaskRequest.Diagnostic]) throws -> MCPResultSource {
        var writer = MCPResultByteWriter(checkpoint: {})
        try writer.literal("{\"contractVersion\":1,\"summary\":\"rejected_input\",\"diagnostics\":[")
        for (index, diagnostic) in diagnostics.enumerated() {
            if index > 0 { try writer.literal(",") }
            try writer.literal("{")
            try writer.field("code", diagnostic.code, first: true)
            try writer.field("field", diagnostic.field)
            if let item = diagnostic.index { try writer.literal(",\"index\":\(item)") }
            if let itemId = diagnostic.itemId { try writer.field("itemId", itemId) }
            try writer.literal("}")
        }
        try writer.literal("]}")
        return try source(writer, isError: true)
    }

    private static func start(_ writer: inout MCPResultByteWriter, mode: String, summary: String) throws {
        try writer.literal("{\"contractVersion\":1,\"atomicity\":\"per_item\"")
        try writer.field("mode", mode)
        try writer.field("summary", summary)
    }

    private static func mapping(_ item: MCPBatchTaskRequest.Item, into writer: inout MCPResultByteWriter) throws {
        try writer.literal("{\"index\":\(item.index)")
        try writer.field("itemId", item.itemId)
        try writer.field("operation", item.operation)
        try writer.field("idempotencyKey", item.command.key)
        // Preserve the original accepted spelling; compact recovery uses normalized UUIDs.
        guard let taskId = item.command.arguments["taskId"] as? String else {
            throw MCPResultBoundaryError.unsupportedEvidence
        }
        try writer.field("taskId", taskId)
    }

    private static func writeStop(_ stop: MCPBatchTaskCoordinator.Stop, into writer: inout MCPResultByteWriter) throws {
        try writer.literal("{")
        try writer.field("reason", stop.reason.rawValue, first: true)
        try writer.literal(",\"nextUnstartedIndex\":\(stop.nextUnstartedIndex)")
        if let blocker = stop.blocker {
            try writer.literal(",\"blocker\":{\"index\":\(blocker.index)")
            try writer.field("itemId", blocker.itemId)
            try writer.literal("}")
        }
        try writer.literal("}")
    }

    private static func source(_ writer: MCPResultByteWriter, isError: Bool?) throws -> MCPResultSource {
        guard let text = String(data: writer.data, encoding: .utf8) else { throw MCPResultBoundaryError.invalidJSON }
        return try MCPResultAdapter.source(text: text, isError: isError,
                                           origin: .generatedJSON, evidence: .established)
    }
}
#endif
