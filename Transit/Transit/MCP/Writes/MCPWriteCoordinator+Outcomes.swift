#if os(macOS)
import Foundation

// Shared outcome construction stays byte-compatible for standalone and batch calls.
@MainActor extension MCPWriteCoordinator {
    func replay(_ receipt: MCPWriteReceipt) -> MCPToolResult? {
        guard let json = receipt.resultJSON, let isError = receipt.resultIsError else { return nil }
        return MCPToolResult(content: [.text(json)], isError: isError ? true : nil)
    }

    func reused(_ command: MCPWriteCommand) -> MCPToolResult {
        transient(
            command, .init("IDEMPOTENCY_KEY_REUSED", "The key is already bound to different arguments"),
            accepted: false)
    }

    func uncertain(_ command: MCPWriteCommand) -> MCPToolResult {
        transient(
            command, .init("OUTCOME_UNCERTAIN", "Reconcile the original operation before issuing another write"),
            accepted: true, outcome: "uncertain", retry: "reconcile")
    }

    func transient(
        _ command: MCPWriteCommand, _ failure: MCPWriteFailure, accepted: Bool?,
        outcome: String = "rejected", retry: String? = nil
    ) -> MCPToolResult {
        MCPWriteOutcome.result(
            MCPWriteOutcome.failure(
                tool: command.tool, key: command.key,
                failure: failure, accepted: accepted,
                outcome: outcome, retryAction: retry), isError: true)
    }
    /// Existing durable validation only: no guard repair, expiry write, recovery
    /// hook, domain lookup or shared-context mutation is permitted in this path.
    func inspectRetainedWhileDirty(
        _ command: MCPWriteCommand, payload: String,
        reservations: MCPLocalReservationStore, receipts: MCPWriteReceiptStore, now: Date,
        batchPolicy: MCPBatchWritePolicy? = nil
    ) -> MCPToolResult {
        switch MCPBatchWritePolicy.inspectRetained(
            command, payload: payload, reservations: reservations, receipts: receipts, now: now) {
        case .terminal(let receipt):
            return replay(receipt) ?? dirtyUnavailable(command, accepted: true, batchPolicy: batchPolicy)
        case .reused: return reused(command)
        case .unavailable(let accepted): return dirtyUnavailable(command, accepted: accepted, batchPolicy: batchPolicy)
        }
    }

    func dirtyUnavailable(
        _ command: MCPWriteCommand, accepted: Bool?, batchPolicy: MCPBatchWritePolicy? = nil
    ) -> MCPToolResult {
        batchPolicy?.onPendingEditsStop()
        return transient(
            command, .init("OUTCOME_UNCERTAIN", "Pending UI edits prevent recovery; reconcile the original key"),
            accepted: accepted, outcome: "uncertain", retry: "reconcile")
    }

}
#endif
