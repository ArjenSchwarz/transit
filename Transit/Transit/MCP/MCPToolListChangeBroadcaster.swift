#if os(macOS)
import Foundation

/// Publishes server-wide MCP tool-list invalidations to every active
/// Streamable HTTP listening stream.
@MainActor
final class MCPToolListChangeBroadcaster {
    private var continuations: [UUID: AsyncStream<MCPServerNotification>.Continuation] = [:]

    func stream() -> AsyncStream<MCPServerNotification> {
        let streamID = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: MCPServerNotification.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        continuations[streamID] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.continuations.removeValue(forKey: streamID)
            }
        }
        return stream
    }

    func notifyToolsListChanged() {
        for continuation in continuations.values {
            continuation.yield(.toolsListChanged)
        }
    }
}

#endif
