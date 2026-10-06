#if os(macOS)
import Foundation

/// Validate the complete response representation before the owned context's single save.
/// Retained receipt JSON and modern source/presentation/fragment backing are separate owners.
nonisolated enum MCPConsolidationTerminalBudget {
    @MainActor static func validate(_ json: String, receipt: MCPWriteReceipt) throws {
        guard MCPConsolidationWriteDefinition.tools.contains(receipt.tool) else { return }
        do {
            let page = try MCPResultPreparation.page(request: MCPResultPagePreparationRequest(
                text: json, isError: nil, origin: .retainedJSON, evidence: .established,
                context: MCPResultContext(tool: receipt.tool, semanticFailure: nil,
                    mutationRecovery: .protectedWrite(MCPProtectedRecoveryKey(
                        tool: receipt.tool, idempotencyKey: receipt.key)), entityPositions: []), metadataOwner: nil))
            _ = try MCPResultPreparation.prepare(pages: [page], budget: MCPResultRetentionBudget(
                store: .ordinary, originalCaptureIndexBytes: json.utf8.count, visibleBytes: 0, pendingBytes: 0))
        } catch MCPResultPreparationError.retentionCapacity {
            throw MCPWriteFailure("CONSOLIDATION_OVER_LIMIT", "The complete committed response exceeds 16 MiB")
        }
    }
}
#endif
