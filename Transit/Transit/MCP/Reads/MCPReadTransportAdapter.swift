#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import NIOFoundationCompat

nonisolated enum MCPReadTransportAdapter {
    @concurrent static func response(
        coordinator: MCPReadCoordinator, timeout: Data, busy: Data,
        admittedAt: ContinuousClock.Instant = .now,
        worker: @escaping @Sendable (MCPReadOperation) async -> PreparedReadResult
    ) async -> Response {
        let bytes = await coordinator.execute(timeout: timeout, busy: busy, admittedAt: admittedAt, worker: worker)
        return Response(status: .ok, headers: [.contentType: "application/json"],
                        body: .init(byteBuffer: ByteBuffer(data: bytes)))
    }
}
#endif
