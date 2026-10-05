import Foundation

nonisolated enum MCPReadAdmissionOwner: Equatable, Sendable {
    case application, native, listener(UUID)
}

/// Caller-owned identity and physical-finalizer receipt. This value does not admit work.
/// A live duplicate identity must be rejected without replacing its operation.
nonisolated struct MCPReadAdmission: Sendable {
    let owner: MCPReadAdmissionOwner
    let operationID: UUID
    let physicalCompletion: @Sendable () -> Void

    init(operationID: UUID = UUID(), owner: MCPReadAdmissionOwner = .application,
         physicalCompletion: @escaping @Sendable () -> Void = {}) {
        self.owner = owner
        self.operationID = operationID
        self.physicalCompletion = physicalCompletion
    }
}
