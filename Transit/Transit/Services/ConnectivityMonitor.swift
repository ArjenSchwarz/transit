import Foundation
import Network

/// Monitors network connectivity using NWPathMonitor and fires a callback
/// when connectivity is restored (transition from unsatisfied to satisfied).
@Observable
final class ConnectivityMonitor: @unchecked Sendable {

    private(set) var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "me.nore.ig.Transit.connectivity")
    nonisolated(unsafe) private var wasConnected = true

    /// Called on the main actor when connectivity is restored.
    var onRestore: (@Sendable () async -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            let restored = !self.wasConnected && connected
            self.wasConnected = connected

            Task { @MainActor in
                self.isConnected = connected
                if restored, let onRestore = self.onRestore {
                    await onRestore()
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
