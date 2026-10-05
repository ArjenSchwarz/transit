#if os(macOS)
import Foundation
import SwiftData

/// Opt-in safeguards for batch calls through the existing receipt coordinator.
/// The synchronous callback runs only for a fresh apply, never for replay.
@MainActor struct MCPBatchWritePolicy {
    enum RetainedInspection {
        case terminal(MCPWriteReceipt)
        case reused
        case unavailable(accepted: Bool?)
    }

    let onPendingEditsStop: @MainActor () -> Void
    let makeCommitServices: (@MainActor (ModelContext) throws -> MCPWriteCommitServices)?
    let taskLinkCapability: TaskLinkWriteCapability?
    let afterTaskApply: MCPWriteCommand.AfterTaskApply?
    let validateBeforeApply: @MainActor (MCPWriteCommand, ModelContext) throws -> Void

    /// Swift's forward matching can bind an unlabelled trailing closure to the
    /// optional factory. Preserve the existing two-argument validation API.
    init(validateBeforeApply: @escaping @MainActor (MCPWriteCommand, ModelContext) throws -> Void) {
        self.init(makeCommitServices: nil, onPendingEditsStop: {}, validateBeforeApply: validateBeforeApply)
    }

    init(makeCommitServices: @escaping @MainActor (ModelContext) throws -> MCPWriteCommitServices,
         validateBeforeApply: @escaping @MainActor (MCPWriteCommand, ModelContext) throws -> Void) {
        self.init(makeCommitServices: makeCommitServices, onPendingEditsStop: {},
                  validateBeforeApply: validateBeforeApply)
    }

    init(
        makeCommitServices: (@MainActor (ModelContext) throws -> MCPWriteCommitServices)? = nil,
        onPendingEditsStop: @escaping @MainActor () -> Void = {},
        afterTaskApply: MCPWriteCommand.AfterTaskApply? = nil,
        taskLinkCapability: TaskLinkWriteCapability? = nil,
        validateBeforeApply: @escaping @MainActor (MCPWriteCommand, ModelContext) throws -> Void =
            MCPBatchWritePolicy.validateTaskIdentity
    ) {
        self.taskLinkCapability = taskLinkCapability
        self.afterTaskApply = afterTaskApply
        self.validateBeforeApply = validateBeforeApply
        self.onPendingEditsStop = onPendingEditsStop
        self.makeCommitServices = makeCommitServices
    }

    private static func validateTaskIdentity(_ command: MCPWriteCommand, context: ModelContext) throws {
        guard ["update_task", "update_task_status", "add_comment"].contains(command.tool),
            let rawID = command.arguments["taskId"] as? String, let taskID = UUID(uuidString: rawID)
        else { throw MCPWriteFailure("INVALID_INPUT", "Batch writes require an explicit task UUID") }
        var descriptor = FetchDescriptor<TransitTask>(predicate: #Predicate { $0.id == taskID })
        descriptor.fetchLimit = 2
        descriptor.includePendingChanges = false
        let matches = try context.fetch(descriptor)
        guard !matches.isEmpty else { throw MCPWriteFailure("TASK_NOT_FOUND", "Task UUID was not found") }
        guard matches.count == 1 else {
            throw MCPWriteFailure("DUPLICATE_TASK_IDENTIFIER", "Task UUID identifies multiple saved tasks")
        }
    }

    /// Uses existing durable validation without repairing either store. Models
    /// stay on MainActor and are immediately replayed by their owning caller.
    static func inspectRetained(
        _ command: MCPWriteCommand, payload: String, reservations: MCPLocalReservationStore,
        receipts: MCPWriteReceiptStore, now: Date
    ) -> RetainedInspection {
        do {
            return try reservations.withValidatedBindings {
                if let binding = try reservations.lookup(tool: command.tool, key: command.key) {
                    guard binding.expiresAt.map({ $0 <= now }) != true else {
                        return .unavailable(accepted: nil)
                    }
                    guard binding.requestJSON == payload else { return .reused }
                    guard let receipt = try receipts.lookup(tool: command.tool, key: command.key, durable: true),
                        receipt.id == binding.receiptID, receipt.requestJSON == binding.requestJSON,
                        receipt.formatVersion == binding.formatVersion, receipt.localScopeID == binding.scopeID,
                        binding.expiresAt == nil || binding.expiresAt == receipt.expiresAt,
                        receipt.expiresAt.map({ $0 <= now }) != true
                    else { return .unavailable(accepted: true) }
                    return receipt.resultJSON == nil ? .unavailable(accepted: true) : .terminal(receipt)
                }
                if let receipt = try receipts.lookup(tool: command.tool, key: command.key, durable: true),
                    receipt.expiresAt.map({ $0 <= now }) != true {
                    guard receipt.requestJSON == payload else { return .reused }
                    return receipt.resultJSON == nil ? .unavailable(accepted: true) : .terminal(receipt)
                }
                return .unavailable(accepted: nil)
            }
        } catch { return .unavailable(accepted: nil) }
    }
}
#endif
