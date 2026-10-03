#if os(macOS)
import Foundation

/// Caller-owned identity and physical-finalizer receipt. This value does not admit work.
/// A live duplicate identity must be rejected without replacing its operation.
nonisolated struct MCPReadAdmission: Sendable {
    let operationID: UUID
    let physicalCompletion: @Sendable () -> Void

    init(operationID: UUID = UUID(), physicalCompletion: @escaping @Sendable () -> Void = {}) {
        self.operationID = operationID
        self.physicalCompletion = physicalCompletion
    }
}
#endif
