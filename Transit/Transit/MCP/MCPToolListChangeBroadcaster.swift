#if os(macOS)
import Foundation
import NIOConcurrencyHelpers
import NIOCore

/// A request's terminal state is separate from its bounded invalidation queue.
nonisolated final class MCPSubscriptionDelivery: Sendable {
    private enum State { case open, graceful, disconnected }
    private let state = NIOLockedValueBox(State.open)

    var isWritable: Bool { state.withLockedValue { $0 != .disconnected } }
    var completesGracefully: Bool { state.withLockedValue { $0 == .graceful } }
    func finish() { state.withLockedValue { if $0 == .open { $0 = .graceful } } }
    func disconnect() { state.withLockedValue { $0 = .disconnected } }
}

nonisolated struct MCPToolListSubscription: Sendable {
    let registrationID: UUID
    let acknowledgement: Data
    let completion: Data
    let changes: AsyncStream<Data>
    let delivery: MCPSubscriptionDelivery
}

/// Each POST owns its own registration, even when RPC IDs are equal.
@MainActor
final class MCPToolListChangeBroadcaster {
    private struct Registration {
        let change: Data?
        let continuation: AsyncStream<Data>.Continuation
        let delivery: MCPSubscriptionDelivery
    }
    private var registrations: [UUID: Registration] = [:]
    private var acceptingRequests = true

    func openRequests() { acceptingRequests = true }
    var activeStreamCount: Int { registrations.count }

    func subscribe(id: JSONRPCId, toolsListChanged: Bool,
                   channelClose: EventLoopFuture<Void>) throws -> MCPToolListSubscription {
        guard acceptingRequests else { throw MCPSubscriptionRegistrationError.closed }
        // Freeze all terminal/control frames before exposing the registration.
        let frames = try MCPSubscriptionFrames.make(id: id, toolsListChanged: toolsListChanged)
        let registrationID = UUID()
        let delivery = MCPSubscriptionDelivery()
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .bufferingNewest(1))
        registrations[registrationID] = Registration(change: toolsListChanged ? frames.change : nil,
            continuation: continuation, delivery: delivery)
        continuation.onTermination = { @Sendable [weak self] reason in
            guard case .cancelled = reason else { return }
            delivery.disconnect()
            Task { @MainActor in self?.disconnect(registrationID) }
        }
        channelClose.whenComplete { @Sendable [weak self] _ in
            delivery.disconnect()
            Task { @MainActor in self?.disconnect(registrationID) }
        }
        return MCPToolListSubscription(registrationID: registrationID, acknowledgement: frames.ack,
            completion: frames.complete, changes: stream, delivery: delivery)
    }

    func disconnect(_ id: UUID) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        registration.delivery.disconnect()
        registration.continuation.finish()
    }

    func notifyToolsListChanged() {
        for registration in registrations.values {
            if let change = registration.change { registration.continuation.yield(change) }
        }
    }

    /// Retained Settings calls this name; it now finishes request registrations only.
    func finishAllSessions() {
        acceptingRequests = false
        let current = Array(registrations.values)
        registrations.removeAll()
        for registration in current {
            registration.delivery.finish()
            registration.continuation.finish()
        }
    }
}

nonisolated enum MCPSubscriptionRegistrationError: Error { case closed }

nonisolated private struct MCPSubscriptionMetadata: Encodable {
    let subscriptionId: JSONRPCId
    enum CodingKeys: String, CodingKey {
        case subscriptionId = "io.modelcontextprotocol/subscriptionId"
    }
}
nonisolated private struct MCPSubscriptionParams: Encodable {
    let notifications: [String: Bool]?
    let metadata: MCPSubscriptionMetadata
    enum CodingKeys: String, CodingKey { case notifications; case metadata = "_meta" }
}
nonisolated private struct MCPSubscriptionNotification: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: MCPSubscriptionParams
}
nonisolated private struct MCPSubscriptionCompleteResult: Encodable {
    let resultType = "complete"
    let metadata: MCPSubscriptionMetadata
    enum CodingKeys: String, CodingKey { case resultType; case metadata = "_meta" }
}
nonisolated private struct MCPSubscriptionComplete: Encodable {
    let jsonrpc = "2.0"
    let id: JSONRPCId
    let result: MCPSubscriptionCompleteResult
}
nonisolated private struct MCPSubscriptionFrames {
    let ack: Data
    let change: Data
    let complete: Data

    static func make(id: JSONRPCId, toolsListChanged: Bool) throws -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let meta = MCPSubscriptionMetadata(subscriptionId: id)
        let ack = try encoder.encode(MCPSubscriptionNotification(method: "notifications/subscriptions/acknowledged",
            params: MCPSubscriptionParams(notifications: toolsListChanged ? ["toolsListChanged": true] : [:],
                metadata: meta)))
        let change = try encoder.encode(MCPSubscriptionNotification(method: "notifications/tools/list_changed",
            params: MCPSubscriptionParams(notifications: nil, metadata: meta)))
        let complete = try encoder.encode(MCPSubscriptionComplete(id: id,
            result: MCPSubscriptionCompleteResult(metadata: meta)))
        return Self(ack: ack, change: change, complete: complete)
    }
}
#endif
