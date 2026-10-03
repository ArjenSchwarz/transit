#if os(macOS)
import Foundation

/// All mutable coordinator and retention state uses this single short lock domain.
nonisolated final class MCPReadPublicationDomain: @unchecked Sendable {
    final class StoreState {
        var version: UInt64 = 0
        var index: any MCPPublicationIndex
        var descriptor: MCPPublicationIndexDescriptor
        let maxEntries: Int
        let maxBytes: Int
        var pending: [UUID: MCPPublicationReservation] = [:]
        var pendingEntries = 0
        var pendingBytes = 0

        init(index: any MCPPublicationIndex, descriptor: MCPPublicationIndexDescriptor,
             maxEntries: Int, maxBytes: Int) {
            self.index = index
            self.descriptor = descriptor
            self.maxEntries = maxEntries
            self.maxBytes = maxBytes
        }
    }

    /// A linked bundle avoids bulk array copying and destruction inside terminal gates.
    final class Retirement {
        let value: AnyObject
        let next: Retirement?
        init(_ value: AnyObject, next: Retirement?) { self.value = value; self.next = next }
    }

    private let lock = NSLock()
    private var retirement: Retirement?
    var stores: [MCPPublicationStoreID: StoreState] = [:]
    var tokenVersion: UInt64 = 0
    private var testingInstant: ContinuousClock.Instant?

    init(testingInstant: ContinuousClock.Instant? = nil) { self.testingInstant = testingInstant }

    /// Scalar deterministic-clock seam; production uses the system clock directly.
    func setTestingInstant(_ instant: ContinuousClock.Instant) {
        withLock { testingInstant = instant }
    }

    var currentInstantLocked: ContinuousClock.Instant { testingInstant ?? .now }

    func withLock<Value>(_ operation: () throws -> Value) rethrows -> Value {
        lock.lock()
        do {
            let result = try operation()
            let retired = retirement
            retirement = nil
            lock.unlock()
            withExtendedLifetime(retired) {}
            return result
        } catch {
            let retired = retirement
            retirement = nil
            lock.unlock()
            withExtendedLifetime(retired) {}
            throw error
        }
    }

    /// Response selectors resume the continuation before draining this bundle;
    /// physical worker ownership remains held until the outside-lock cleanup ends.
    func withLockRetainingRetirement<Value>(_ operation: () -> Value) -> (Value, Retirement?) {
        lock.lock()
        let result = operation()
        let retired = retirement
        retirement = nil
        lock.unlock()
        return (result, retired)
    }

    func retireLocked(_ value: AnyObject) { retirement = Retirement(value, next: retirement) }

    func register(storeID: MCPPublicationStoreID, index: any MCPPublicationIndex,
                  maxEntries: Int, maxBytes: Int) throws {
        let descriptor = index.descriptor
        guard maxEntries >= 0, maxEntries <= 8, maxBytes >= 0,
              descriptor.entryCount <= maxEntries, descriptor.encodedByteCount <= maxBytes else {
            throw PublicationRejection.capacity
        }
        let state = StoreState(index: index, descriptor: descriptor, maxEntries: maxEntries, maxBytes: maxBytes)
        // Registration also pins a token snapshot; no token union is built under the gate.
        if descriptor.tokens.isEmpty {
            try withLock {
                guard stores[storeID] == nil else { throw PublicationRejection.busy }
                stores[storeID] = state
                tokenVersion &+= 1
            }
            return
        }
        let allocation = withLock { (tokenVersion, allocatedTokensLocked()) }
        guard allocation.1.allSatisfy({ descriptor.tokens.isDisjoint(with: $0) }) else {
            throw PublicationRejection.busy
        }
        try withLock {
            guard stores[storeID] == nil, tokenVersion == allocation.0 else { throw PublicationRejection.busy }
            stores[storeID] = state
            tokenVersion &+= 1
        }
    }

    func snapshot(for storeID: MCPPublicationStoreID) throws -> MCPPublicationStoreSnapshot {
        try withLock {
            guard let store = stores[storeID] else { throw PublicationRejection.busy }
            return MCPPublicationStoreSnapshot(version: store.version, tokenVersion: tokenVersion,
                                               index: store.index, allocatedTokenSets: allocatedTokensLocked())
        }
    }

    private func allocatedTokensLocked() -> [Set<String>] {
        stores.values.flatMap { [$0.descriptor.tokens] + $0.pending.values.map(\.newTokens) }
    }

    func accounting(for storeID: MCPPublicationStoreID) throws -> MCPPublicationAccounting {
        try withLock {
            guard let store = stores[storeID] else { throw PublicationRejection.busy }
            return MCPPublicationAccounting(visibleEntries: store.descriptor.entryCount,
                visibleBytes: store.descriptor.encodedByteCount, pendingEntries: store.pendingEntries,
                pendingBytes: store.pendingBytes)
        }
    }

    func validateLocked(_ reservation: MCPPublicationReservation) -> PublicationRejection? {
        guard reservation.domain === self, reservation.status == .pending,
              let store = stores[reservation.publicationStoreID],
              store.pending[reservation.operationID] === reservation,
              store.version == reservation.expectedVersion else { return .busy }
        let instant = currentInstantLocked
        guard instant < reservation.deadline,
              reservation.descriptor.roots.values.allSatisfy({ instant < $0.deadline }) else { return .expired }
        return nil
    }

    func commitLocked(_ reservation: MCPPublicationReservation) {
        guard reservation.domain === self, reservation.status == .pending,
              let store = stores[reservation.publicationStoreID],
              store.version == reservation.expectedVersion,
              store.pending[reservation.operationID] === reservation else { return }
        retireLocked(store.index)
        store.index = reservation.index
        store.descriptor = reservation.descriptor
        store.version &+= 1
        removeLocked(reservation, from: store)
        reservation.status = .committed
        tokenVersion &+= 1
    }

    func discardLocked(_ reservation: MCPPublicationReservation) {
        guard reservation.domain === self, reservation.status == .pending,
              let store = stores[reservation.publicationStoreID],
              store.pending[reservation.operationID] === reservation else { return }
        removeLocked(reservation, from: store)
        reservation.status = .discarded
        tokenVersion &+= 1
    }

    func removeLocked(_ reservation: MCPPublicationReservation, from store: StoreState) {
        retireLocked(reservation)
        store.pending.removeValue(forKey: reservation.operationID)
        store.pendingEntries -= reservation.chargeEntries
        store.pendingBytes -= reservation.chargeBytes
    }
}
#endif
