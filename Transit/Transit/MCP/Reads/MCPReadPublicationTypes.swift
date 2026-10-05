import Foundation

/// Stable identity of one retention store sharing the common publication domain.
nonisolated struct MCPPublicationStoreID: Hashable, Sendable {
    let rawValue: UUID
}

nonisolated enum PublicationRejection: Error, Hashable, Sendable {
    case busy
    case expired
    case capacity
}

/// Calls occur only under the shared domain lock. Preparation/coalescing happens outside it.
/// Implementations validate all participants before any commit, and discard idempotently.
nonisolated protocol MCPPreparedPublication: Sendable {
    var publicationStoreID: MCPPublicationStoreID { get }
    func validateLocked(in domain: MCPReadPublicationDomain) -> PublicationRejection?
    func commitLocked(in domain: MCPReadPublicationDomain)
    func discardLocked(in domain: MCPReadPublicationDomain)
}

/// Coalesces selected children into one immutable candidate per store before terminal selection.
/// Preparation runs outside the terminal lock; reservation ownership transfers atomically
/// through the same domain, without an independent store lock or a capacity-charge gap.
/// Concrete lookup, reservation, transfer and retirement hooks are supplied in task 9.
nonisolated protocol MCPReadPublicationParticipant: Sendable {
    var publicationStoreID: MCPPublicationStoreID { get }
    func prepareAggregate(
        _ publications: [any MCPPreparedPublication],
        in domain: MCPReadPublicationDomain
    ) throws -> any MCPPreparedPublication
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
    /// Known typed tool outcome only. Nil leaves opaque responses unclassified.
    let diagnosticOutcome: MCPReadDiagnosticOutcome?

    init(encodedResponse: Data, publications: [any MCPPreparedPublication],
         publicationErrors: PreencodedPublicationErrors, diagnosticOutcome: MCPReadDiagnosticOutcome? = nil) {
        self.encodedResponse = encodedResponse
        self.publications = publications
        self.publicationErrors = publicationErrors
        self.diagnosticOutcome = diagnosticOutcome
    }
}
