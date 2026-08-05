#if os(macOS)
import Foundation

/// Value state for port commits from Settings. It is deliberately separate from
/// the asynchronous coordinator so duplicate, disabled, and presentation rules
/// remain directly testable without a listener.
nonisolated struct MCPPortChangeState: Equatable {
    private(set) var pendingPort: Int?
    private var lastEnqueuedPort: Int?

    /// Records a committed port only when the server is enabled. Repeating the
    /// latest value is a no-op, preventing a Return submission from restarting
    /// a listener already requested by a focus-loss commit.
    mutating func enqueueCommittedPort(_ port: Int, isEnabled: Bool) -> Bool {
        guard isEnabled, lastEnqueuedPort != port else { return false }
        pendingPort = port
        lastEnqueuedPort = port
        return true
    }

    mutating func takePendingPort() -> Int? {
        defer { pendingPort = nil }
        return pendingPort
    }

    /// Drops both scheduled work and its duplicate-suppression marker. A later
    /// enabled session must be allowed to submit its persisted port again.
    mutating func cancelPendingPort() {
        pendingPort = nil
        lastEnqueuedPort = nil
    }

    /// Connection instructions must only advertise the listener currently
    /// owned by the server, never a persisted port awaiting reconciliation.
    static func setupCommandPort(isEnabled: Bool, activeListenerPort: Int?) -> Int? {
        isEnabled ? activeListenerPort : nil
    }
}

/// Bridges committed Settings values to `MCPServer`'s desired-state lifecycle.
/// This class never owns listener state: it debounces UI commits, then delegates
/// all start/restart/invalid-port handling to the existing server coordinator.
@MainActor
final class MCPPortChangeCoordinator {
    typealias PortChangeApplier = @MainActor (Int) async -> Void

    private var state = MCPPortChangeState()
    private var debounceTask: Task<Void, Never>?
    private var apply: PortChangeApplier?
    private let debounce: Duration

    init(debounce: Duration = .milliseconds(250)) {
        self.debounce = debounce
    }

    deinit {
        debounceTask?.cancel()
    }

    func enqueueCommittedPort(
        _ port: Int,
        isEnabled: Bool,
        apply: @escaping PortChangeApplier
    ) {
        self.apply = apply
        guard state.enqueueCommittedPort(port, isEnabled: isEnabled) else { return }

        debounceTask?.cancel()
        let debounce = debounce
        debounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: debounce)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyPendingPortChange()
        }
    }

    /// Flushes the final committed value as Settings disappears so closing the
    /// window cannot strand the persisted port behind the live listener.
    func flushPendingPortChange() async {
        debounceTask?.cancel()
        debounceTask = nil
        await applyPendingPortChange()
    }

    /// Disabling MCP cancels pending work before the server receives its stop
    /// request, so an old debounce cannot start it again afterward.
    func cancelPendingPortChange() {
        debounceTask?.cancel()
        debounceTask = nil
        state.cancelPendingPort()
    }

    private func applyPendingPortChange() async {
        guard let port = state.takePendingPort(), let apply else { return }
        await apply(port)
    }
}
#endif
