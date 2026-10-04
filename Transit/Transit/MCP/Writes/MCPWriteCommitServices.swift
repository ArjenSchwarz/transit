#if os(macOS)
import SwiftData

/// Sealed construction proves all four service contexts without exposing their
/// private context/fetcher fields or accepting arbitrary service instances.
@MainActor struct MCPWriteCommitServices {
    private let storedServices: MCPWriteCommandServices
    var context: ModelContext { storedServices.context }
    var services: MCPWriteCommandServices { storedServices }

    init(context: ModelContext, taskAllocator: DisplayIDAllocator, milestoneAllocator: DisplayIDAllocator) {
        storedServices = MCPWriteCommandServices(
            tasks: TaskService(modelContext: context, displayIDAllocator: taskAllocator),
            projects: ProjectService(modelContext: context), comments: CommentService(modelContext: context),
            milestones: MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator),
            context: context)
    }
}

/// Retained only for one synchronous validation/apply/result-save phase.
@MainActor struct MCPWriteCommitScope {
    let services: MCPWriteCommandServices
    let receipts: MCPWriteReceiptStore
    var context: ModelContext { services.context }

    init(shared: MCPWriteCommandServices, scopeID: String, policy: MCPBatchWritePolicy?) throws {
        if let factory = policy?.makeCommitServices {
            guard !shared.context.hasChanges else { throw MCPWriteFailure("OUTCOME_UNCERTAIN", "Pending UI edits") }
            let context = ModelContext(shared.context.container)
            context.autosaveEnabled = false
            let wrapper = try factory(context)
            guard wrapper.context === context, !context.hasChanges, !context.autosaveEnabled,
                  !shared.context.hasChanges else {
                throw MCPWriteFailure("OUTCOME_UNCERTAIN", "Unable to establish a clean owned commit scope")
            }
            services = wrapper.services
        } else {
            services = shared
        }
        receipts = MCPWriteReceiptStore(context: services.context, scopeID: scopeID)
    }

    func receipt(for guardRecord: MCPLocalReservation) throws -> MCPWriteReceipt {
        guard let receipt = try receipts.lookup(tool: guardRecord.tool, key: guardRecord.key),
              Self.matches(receipt, guardRecord: guardRecord) else {
            throw MCPWriteFailure("OUTCOME_UNCERTAIN", "Accepted receipt evidence is unavailable")
        }
        return receipt
    }

    static func matches(_ receipt: MCPWriteReceipt, guardRecord: MCPLocalReservation) -> Bool {
        receipt.id == guardRecord.receiptID && receipt.requestJSON == guardRecord.requestJSON
            && receipt.formatVersion == guardRecord.formatVersion && receipt.localScopeID == guardRecord.scopeID
            && receipt.tool == guardRecord.tool && receipt.key == guardRecord.key
    }
}
#endif
