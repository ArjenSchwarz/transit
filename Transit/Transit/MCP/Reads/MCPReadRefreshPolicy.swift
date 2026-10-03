#if os(macOS)
import Foundation

nonisolated enum MCPRefreshDecision: Equatable, Sendable {
    case skip(ReadRefreshOutcome)
    case wait(Duration)
}

/// Current public SwiftData APIs supply no force-pull trigger. This adapter never writes.
nonisolated struct MCPUnavailableRefreshTrigger: Sendable {
    let isAvailable = false
}

nonisolated enum MCPReadRefreshPolicy {
    /// Use before cursor lookup; caller preserves existing selector-validation precedence.
    static func parse(_ value: Any?) -> MCPReadPolicy? {
        guard let value else { return .refreshIfNeeded }
        guard let string = value as? String else { return nil }
        return MCPReadPolicy(rawValue: string)
    }

    static func decision(policy: MCPReadPolicy, snapshot: MCPImportMonitorSnapshot,
                         recent: Bool, remaining: Duration, applicableInFlightIDs: Set<UUID> = [],
                         triggerAvailable: Bool = false) -> MCPRefreshDecision {
        guard snapshot.syncActive, policy != .cached else { return .skip(.notRequested) }
        if recent { return .skip(.recentImport) }
        guard triggerAvailable || !snapshot.inFlight.isDisjoint(with: applicableInFlightIDs) else {
            return .skip(.unavailable)
        }
        guard remaining > .zero else { return .skip(.timeout) }
        return .wait(min(.seconds(2), remaining))
    }

    /// Capture-time applicability is evaluated again after this bounded wait. A successful
    /// callback alone never produces import_observed or a recent freshness claim.
    @concurrent static func wait(
        monitor: MCPImportEvidenceMonitor, initial: MCPImportMonitorSnapshot, duration: Duration,
        applicableImportIDs: Set<UUID>,
        now: @Sendable () -> ContinuousClock.Instant = { .now },
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async -> MCPImportMonitorSnapshot {
        let deadline = now().advanced(by: max(.zero, duration))
        while now() < deadline, !Task.isCancelled {
            let state = monitor.snapshot()
            let succeeded = state.lastSuccess.map {
                applicableImportIDs.contains($0.event.id) && $0.event.id != initial.lastSuccess?.event.id
            } ?? false
            let failed = state.lastFailureID.map {
                applicableImportIDs.contains($0) && (state.lastFailureGeneration ?? 0) > initial.generation
            } ?? false
            if succeeded || failed { return state }
            do { try await sleep(min(.milliseconds(10), now().duration(to: deadline))) } catch { break }
        }
        return monitor.snapshot()
    }

    static func outcome(initial: MCPImportMonitorSnapshot, final: MCPImportMonitorSnapshot,
                        proof: MCPImportCaptureProof?, applicableInFlightIDs: Set<UUID> = [],
                        triggerAvailable: Bool = false) -> ReadRefreshOutcome {
        if let proof, proof.storeIdentifier == final.storeIdentifier, let success = final.lastSuccess,
           proof.visibleImportIDs.contains(success.event.id),
           success.event.id != initial.lastSuccess?.event.id { return .importObserved }
        if let failureID = final.lastFailureID, applicableInFlightIDs.contains(failureID),
           (final.lastFailureGeneration ?? 0) > initial.generation { return .failed }
        return triggerAvailable || !initial.inFlight.isDisjoint(with: applicableInFlightIDs)
            ? .timeout : .unavailable
    }
}
#endif
