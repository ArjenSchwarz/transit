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
        guard snapshot.observationIsValid else { return .skip(.unavailable) }
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
        observation: MCPImportObservationWindow,
        now: @Sendable () -> ContinuousClock.Instant = { .now },
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async -> MCPImportMonitorSnapshot {
        // Caller owns the window from before decision until metadata is frozen after capture.
        let deadline = now().advanced(by: max(.zero, duration))
        while now() < deadline, !Task.isCancelled {
            let state = monitor.snapshot(observation: observation)
            guard state.observationIsValid else { return state }
            let succeeded = state.successfulImports.contains {
                observation.applicableImportIDs.contains($0.key) && initial.successfulImports[$0.key] == nil
            }
            let failed = state.failedImports.contains {
                observation.applicableImportIDs.contains($0.key) && $0.value > initial.generation
            }
            if succeeded || failed { return state }
            do { try await sleep(min(.milliseconds(10), now().duration(to: deadline))) } catch { break }
        }
        return monitor.snapshot(observation: observation)
    }

    static func outcome(initial: MCPImportMonitorSnapshot, final: MCPImportMonitorSnapshot,
                        proof: MCPImportCaptureProof?, applicableInFlightIDs: Set<UUID> = [],
                        triggerAvailable: Bool = false) -> ReadRefreshOutcome {
        guard final.observationIsValid else { return .unavailable }
        if let proof, proof.storeIdentifier == final.storeIdentifier,
           final.successfulImports.contains(where: {
               proof.visibleImportIDs.contains($0.key) && initial.successfulImports[$0.key] == nil
           }) { return .importObserved }
        if final.failedImports.contains(where: {
            applicableInFlightIDs.contains($0.key) && $0.value > initial.generation
        }) { return .failed }
        return triggerAvailable || !initial.inFlight.isDisjoint(with: applicableInFlightIDs)
            ? .timeout : .unavailable
    }
}
#endif
