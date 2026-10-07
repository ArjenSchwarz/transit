import Foundation

nonisolated enum MCPReadLifecycleChange {
    case stopApplication, startApplication, startListener(UUID), stopListener(UUID)
}

extension MCPReadCoordinator {
    nonisolated func stop() { changeLifecycle(.stopApplication) }
    nonisolated func start() { changeLifecycle(.startApplication) }
    nonisolated func startListener(_ id: UUID) { changeLifecycle(.startListener(id)) }
    nonisolated func stopListener(_ id: UUID) { changeLifecycle(.stopListener(id)) }
}

extension MCPReadAdmissionOwner {
    nonisolated func isActive(listener: UUID?) -> Bool {
        if case .listener(let id) = self { return listener == id }
        return true
    }
}

nonisolated enum MCPReadTiming {
    static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

}
