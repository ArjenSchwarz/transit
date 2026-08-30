#if os(macOS)
import Hummingbird
import NIOCore

/// Hummingbird request context retaining the transport channel for the request.
/// BasicRequestContext intentionally discards it after initialization, while
/// long-lived SSE responses need `closeFuture` to end idle registrations when
/// the peer disconnects.
nonisolated struct MCPRequestContext: RequestContext {
    var coreContext: CoreRequestContextStorage
    let channel: any Channel

    init(source: ApplicationRequestContextSource) {
        self.coreContext = .init(source: source)
        self.channel = source.channel
    }
}

#endif
