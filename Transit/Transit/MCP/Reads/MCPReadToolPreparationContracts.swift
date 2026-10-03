#if os(macOS)
import Foundation

/// Fresh or retained capture identity plus the original complete outer read metadata bytes.
/// A retained query consumes this value without capture, waiting or reassessment.
nonisolated struct MCPPreparedReadCapture: Sendable {
    let view: CapturedReadView
    let frozenMetadataBytes: Data
}

/// Pure value transformation can run off MainActor. Model/store access must explicitly hop.
typealias MCPReadCaptureTransform = @Sendable (MCPPreparedReadCapture, MCPReadOperation)
    async throws -> MCPPreparedToolRead

/// T63 owns the concrete policy/observation implementation. This is an interface-only seam.
/// The observation remains held through transform/encoding/private reservation preparation.
/// The operation always uses its original admission deadline. No helper publishes here.
nonisolated protocol MCPReadCapturedPreparing: Sendable {
    func prepareCapturedRead(request: ReadCaptureRequest, policy: MCPReadPolicy,
                             operation: MCPReadOperation, transform: @escaping MCPReadCaptureTransform)
        async throws -> MCPPreparedToolRead
}
#endif
