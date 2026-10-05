#if os(macOS)
import Foundation

nonisolated enum MCPReadBatchUtilities {
    static func result(_ bytes: Data) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: bytes, publications: [],
            publicationErrors: PreencodedPublicationErrors(busy: bytes, expired: bytes, capacity: bytes))
    }

    static func discard(_ publications: [any MCPPreparedPublication], in domain: MCPReadPublicationDomain) {
        domain.withLock { for publication in publications { publication.discardLocked(in: domain) } }
    }
}
#endif
