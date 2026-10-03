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
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> MCPResultSource {
        try MCPResultSource.make(text: text, isError: isError, origin: origin,
                                 evidence: evidence, checkpoint: checkpoint)
    }

    /// Source-only presentation; worker checkpoints preserve the original budget.
    static func present(
        _ source: MCPResultSource,
        context: MCPResultContext,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> MCPResultPresentation {
        try checkpoint()
        let classification = try MCPResultClassification.inspect(source, context: context, checkpoint: checkpoint)
        let links = try MCPResultLinks.build(source, context: context, checkpoint: checkpoint)
        try checkpoint()
        return MCPResultPresentation(evidence: classification.evidence, links: links,
                                     errorCategory: classification.category, recovery: classification.recovery)
    }
}
#endif
