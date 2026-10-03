#if os(macOS)
import Foundation

/// All mutable coordinator and retention state uses this single short lock domain.
nonisolated final class MCPReadPublicationDomain: @unchecked Sendable {
    private let lock = NSLock()

    func withLock<Value>(_ operation: () throws -> Value) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
#endif
