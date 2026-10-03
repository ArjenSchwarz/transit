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
    let successfulImports: [UUID: MCPObservedImport]
    let failedImports: [UUID: UInt64]
    let observationIsValid: Bool
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
    private var observations: [UUID: MCPImportWindowEvidence] = [:]

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
        observations.removeAll()
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
            for id in observations.keys where observations[id]?.applicableImportIDs.contains(event.id) == true {
                observations[id]?.failures[event.id] = generation
            }
            return
        }
        // Invalid completed evidence must never replace the last reliable success.
        guard event.startDate <= end, end <= observedAt else { return }
        let observed = MCPObservedImport(event: event, observedAt: observedAt, monotonicAt: monotonicNow)
        for id in observations.keys where observations[id]?.applicableImportIDs.contains(event.id) == true {
            observations[id]?.successes[event.id] = observed
        }
        if let previous = lastSuccess, let previousEnd = previous.event.endDate, end < previousEnd { return }
        lastSuccess = observed
    }

    /// Register before the decision snapshot to cover completions between decision and polling.
    func beginObservation(applicableImportIDs: Set<UUID>) throws -> MCPImportObservationWindow {
        lock.lock()
        defer { lock.unlock() }
        guard applicableImportIDs.count <= 256 else { throw MCPImportObservationError.tooManyImports }
        guard observations.count < 8, !stopped else { throw MCPImportObservationError.busy }
        let id = UUID()
        var evidence = MCPImportWindowEvidence(applicableImportIDs: applicableImportIDs)
        if let success = lastSuccess, applicableImportIDs.contains(success.event.id) {
            evidence.successes[success.event.id] = success
        }
        observations[id] = evidence
        return MCPImportObservationWindow(id: id, applicableImportIDs: applicableImportIDs, monitor: self)
    }

    func endObservation(_ id: UUID) {
        lock.lock()
        observations.removeValue(forKey: id)
        lock.unlock()
    }

    func snapshot(observation: MCPImportObservationWindow? = nil) -> MCPImportMonitorSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let valid = observation == nil || observation.flatMap { observations[$0.id] } != nil
        var successes = observation.flatMap { observations[$0.id]?.successes } ?? [:]
        var failures = observation.flatMap { observations[$0.id]?.failures } ?? [:]
        if observation == nil, let success = lastSuccess { successes[success.event.id] = success }
        if observation == nil, let failureID = lastFailureID, let failureGeneration = lastFailureGeneration {
            failures[failureID] = failureGeneration
        }
        return MCPImportMonitorSnapshot(syncActive: syncActive, storeIdentifier: storeIdentifier,
                                        generation: generation, lastSuccess: valid ? lastSuccess : nil,
                                        inFlight: valid ? inFlight : [], lastFailureGeneration: lastFailureGeneration,
                                        lastFailureID: valid ? lastFailureID : nil, successfulImports: successes,
                                        failedImports: failures, observationIsValid: valid)
    }

    func freshness(_ snapshot: MCPImportMonitorSnapshot, proof: MCPImportCaptureProof?,
                   asOf: Date, now: ContinuousClock.Instant) -> ReadFreshness {
        let timestamp = Self.timestamp(asOf)
        guard snapshot.syncActive else {
            return ReadFreshness(syncState: .inactive, assessment: .notApplicable, assessedAt: timestamp,
                                 lastImportedAt: nil, evidence: .none, recentImportThresholdMs: 30_000)
        }
        guard snapshot.observationIsValid, let proof, proof.storeIdentifier == snapshot.storeIdentifier,
              let success = snapshot.successfulImports.values.filter({ proof.visibleImportIDs.contains($0.event.id) })
                .max(by: { ($0.event.endDate ?? .distantPast) < ($1.event.endDate ?? .distantPast) }),
              let end = success.event.endDate, end <= asOf,
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
