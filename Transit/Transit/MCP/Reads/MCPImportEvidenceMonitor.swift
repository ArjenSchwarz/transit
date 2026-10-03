#if os(macOS)
import CoreData
import Foundation

/// Copied synchronously from the callback; no Core Data event crosses executors.
nonisolated struct MCPImportEvent: Sendable {
    enum Kind: Sendable { case setup, `import`, export }
    let id: UUID
    let storeIdentifier: String
    let kind: Kind
    let startDate: Date
    let endDate: Date?
    let succeeded: Bool
    let failureCategory: String?

    init(id: UUID, storeIdentifier: String, kind: Kind, startDate: Date, endDate: Date?,
         succeeded: Bool, failureCategory: String? = nil) {
        self.id = id
        self.storeIdentifier = storeIdentifier
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.succeeded = succeeded
        self.failureCategory = failureCategory
    }
}

/// Only a capture producer with independent import-visible history evidence may supply this.
/// Store equality, notification arrival, heartbeat, or equal history fences alone are insufficient.
nonisolated struct MCPImportCaptureProof: Sendable {
    let storeIdentifier: String
    let visibleImportIDs: Set<UUID>
}

nonisolated struct MCPObservedImport: Sendable {
    let event: MCPImportEvent
    let observedAt: Date
    let monotonicAt: ContinuousClock.Instant
}

nonisolated struct MCPImportMonitorSnapshot: Sendable {
    let syncActive: Bool
    let storeIdentifier: String?
    let generation: UInt64
    let lastSuccess: MCPObservedImport?
    let inFlight: Set<UUID>
    let lastFailureGeneration: UInt64?
    let lastFailureID: UUID?
}

/// The lock serializes callback values and capture fences without a MainActor hop.
/// Reads never wait for a queued observer task to catch up.
nonisolated final class MCPImportEvidenceMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private let syncActive: Bool
    private let storeIdentifier: String?
    private var generation: UInt64 = 0
    private var lastSuccess: MCPObservedImport?
    private var inFlight: Set<UUID> = []
    private var lastFailureGeneration: UInt64?
    private var lastFailureID: UUID?
    private var stopped = false
    private var observerEpoch: UInt64 = 0
    private var observer: (any NSObjectProtocol)?
    private var notificationCenter: NotificationCenter?

    init(syncActive: Bool, storeIdentifier: String?) {
        self.syncActive = syncActive
        self.storeIdentifier = storeIdentifier
    }

    /// Subscribe before admission. An unknown public store identity stays fail-closed.
    func start(center: NotificationCenter = .default) {
        lock.lock()
        guard observer == nil, syncActive else { lock.unlock(); return }
        stopped = false
        observerEpoch &+= 1
        let epoch = observerEpoch
        notificationCenter = center
        observer = center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let kind: MCPImportEvent.Kind
            switch event.type {
            case .setup: kind = .setup
            case .import: kind = .import
            case .export: kind = .export
            @unknown default: return
            }
            let copy = MCPImportEvent(id: event.identifier, storeIdentifier: event.storeIdentifier,
                                      kind: kind, startDate: event.startDate, endDate: event.endDate,
                                      succeeded: event.succeeded, failureCategory: event.error.map {
                                          let error = $0 as NSError
                                          return "\(error.domain):\(error.code)"
                                      })
            self?.receive(copy, observerEpoch: epoch)
        }
        lock.unlock()
    }

    func stop() {
        lock.lock()
        stopped = true
        observerEpoch &+= 1
        if !inFlight.isEmpty { generation &+= 1; inFlight.removeAll() }
        let token = observer
        let center = notificationCenter
        observer = nil
        notificationCenter = nil
        lock.unlock()
        if let token { center?.removeObserver(token) }
    }

    deinit { stop() }

    func receive(_ event: MCPImportEvent, observedAt: Date = Date(),
                 monotonicNow: ContinuousClock.Instant = .now, observerEpoch expectedEpoch: UInt64? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, expectedEpoch == nil || expectedEpoch == observerEpoch,
              syncActive, event.kind == .import,
              let storeIdentifier, event.storeIdentifier == storeIdentifier else { return }
        generation &+= 1
        guard let end = event.endDate else {
            inFlight.insert(event.id)
            return
        }
        inFlight.remove(event.id)
        guard event.succeeded else {
            lastFailureGeneration = generation
            lastFailureID = event.id
            return
        }
        // Invalid completed evidence must never replace the last reliable success.
        guard event.startDate <= end, end <= observedAt else { return }
        if let previous = lastSuccess, let previousEnd = previous.event.endDate, end < previousEnd { return }
        lastSuccess = MCPObservedImport(event: event, observedAt: observedAt, monotonicAt: monotonicNow)
    }

    func snapshot() -> MCPImportMonitorSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return MCPImportMonitorSnapshot(syncActive: syncActive, storeIdentifier: storeIdentifier,
                                        generation: generation, lastSuccess: lastSuccess,
                                        inFlight: inFlight, lastFailureGeneration: lastFailureGeneration,
                                        lastFailureID: lastFailureID)
    }

    func freshness(_ snapshot: MCPImportMonitorSnapshot, proof: MCPImportCaptureProof?,
                   asOf: Date, now: ContinuousClock.Instant) -> ReadFreshness {
        let timestamp = Self.timestamp(asOf)
        guard snapshot.syncActive else {
            return ReadFreshness(syncState: .inactive, assessment: .notApplicable, assessedAt: timestamp,
                                 lastImportedAt: nil, evidence: .none, recentImportThresholdMs: 30_000)
        }
        guard let proof, let success = snapshot.lastSuccess, let end = success.event.endDate,
              proof.storeIdentifier == snapshot.storeIdentifier,
              proof.visibleImportIDs.contains(success.event.id), end <= asOf,
              now >= success.monotonicAt else { return Self.unknown(at: timestamp) }
        let monotonicAge = Self.seconds(success.monotonicAt.duration(to: now))
            + success.observedAt.timeIntervalSince(end)
        let wallAge = asOf.timeIntervalSince(end)
        // A changed wall clock cannot make retained evidence younger.
        guard abs(monotonicAge - wallAge) <= 1 else { return Self.unknown(at: timestamp) }
        return ReadFreshness(syncState: .active, assessment: max(monotonicAge, wallAge) <= 30
                             ? .recentImport : .stale, assessedAt: timestamp,
                             lastImportedAt: Self.timestamp(end), evidence: .completedImport,
                             recentImportThresholdMs: 30_000)
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func unknown(at timestamp: String) -> ReadFreshness {
        ReadFreshness(syncState: .active, assessment: .unknown, assessedAt: timestamp,
                      lastImportedAt: nil, evidence: .none, recentImportThresholdMs: 30_000)
    }

    private static func seconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
}
#endif
