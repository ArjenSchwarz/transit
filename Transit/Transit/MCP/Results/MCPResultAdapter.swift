#if os(macOS)
import Foundation

nonisolated struct MCPUnavailableLink: Sendable {
    let entityType: MCPResultEntityType
    let entityId: UUID
    let sourcePath: String
    let availability = "unavailable"
    let reason = "navigation_not_supported"
}

nonisolated struct MCPResultPresentation: Sendable {
    let evidence: MCPResultEvidence
    let links: [MCPUnavailableLink]
    let errorCategory: MCPResultErrorCategory?
    let recovery: MCPResultRecovery?
}

nonisolated enum MCPResultAdapter {
    static func source(
        text: String,
        isError: Bool?,
        origin: MCPResultOrigin,
        evidence: MCPResultEvidence,
        checkpoint: @Sendable () throws -> Void = {}
    ) throws -> MCPResultSource {
        throw MCPResultBoundaryError.notImplemented
    }

    /// Declaration-stage placeholder; deterministic selectors arrive after RED.
    static func present(
        _ source: MCPResultSource,
        context: MCPResultContext
    ) -> MCPResultPresentation {
        MCPResultPresentation(evidence: .unestablished, links: [], errorCategory: nil, recovery: nil)
    }
}
#endif
