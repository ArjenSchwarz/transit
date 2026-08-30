#if os(macOS)
import Foundation
import NIOCore

/// Publishes server-wide MCP tool-list invalidations once per active session.
/// A session can own multiple Streamable HTTP listening streams, but MCP
/// requires each JSON-RPC message to be sent on only one of them.
@MainActor
final class MCPToolListChangeBroadcaster {
    private struct StreamRegistration {
        let sessionID: String
        let continuation: AsyncStream<MCPServerNotification>.Continuation
    }

    private var sessionIDs: Set<String> = []
    private var registrations: [UUID: StreamRegistration] = [:]

    var activeStreamCount: Int { registrations.count }

    func createSession() -> String {
        let sessionID = UUID().uuidString
        sessionIDs.insert(sessionID)
        return sessionID
    }

    func stream(
        sessionID: String,
        channelClose: EventLoopFuture<Void>
    ) -> AsyncStream<MCPServerNotification>? {
        guard sessionIDs.contains(sessionID) else { return nil }

        let streamID = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: MCPServerNotification.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        registrations[streamID] = StreamRegistration(
            sessionID: sessionID,
            continuation: continuation
        )
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.removeStream(streamID)
            }
        }
        channelClose.whenComplete { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.finishStream(streamID)
            }
        }
        return stream
    }

    func notifyToolsListChanged() {
        let streamsBySession = Dictionary(grouping: registrations) { $0.value.sessionID }
        for streams in streamsBySession.values {
            // Dictionary order is intentionally not part of the contract: MCP
            // permits any one of a session's concurrently connected streams.
            streams.first?.value.continuation.yield(.toolsListChanged)
        }
    }

    func finishAllSessions() {
        sessionIDs.removeAll()
        let continuations = registrations.values.map(\.continuation)
        registrations.removeAll()
        for continuation in continuations {
            continuation.finish()
        }
    }

    private func finishStream(_ streamID: UUID) {
        guard let registration = registrations.removeValue(forKey: streamID) else { return }
        registration.continuation.finish()
    }

    private func removeStream(_ streamID: UUID) {
        registrations.removeValue(forKey: streamID)
    }
}

#endif
