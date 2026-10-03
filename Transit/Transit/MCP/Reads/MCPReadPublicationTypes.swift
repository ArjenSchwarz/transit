#if os(macOS)
import Foundation

/// Identity/injection seam only. Task 9 supplies the common lock and transactional behavior.
/// No instance of this scaffold can publish or claim deadline/capacity guarantees.
nonisolated final class MCPReadPublicationDomain: Sendable {}

nonisolated enum PublicationRejection: Hashable, Sendable {
    case busy
    case expired
    case capacity
}

/// Calls occur only under the shared domain lock. Preparation/coalescing happens outside it.
/// Implementations validate all participants before any commit, and discard idempotently.
nonisolated protocol MCPPreparedPublication: Sendable {
    func validateLocked(in domain: MCPReadPublicationDomain) -> PublicationRejection?
    func commitLocked(in domain: MCPReadPublicationDomain)
    func discardLocked(in domain: MCPReadPublicationDomain)
}

/// All failure bytes must be ready before entering the terminal-selection lock.
nonisolated struct PreencodedPublicationErrors: Sendable {
    let busy: Data
    let expired: Data
    let capacity: Data
}

nonisolated struct PreparedReadResult: Sendable {
    let encodedResponse: Data
    let publications: [any MCPPreparedPublication]
    let publicationErrors: PreencodedPublicationErrors
}
#endif
