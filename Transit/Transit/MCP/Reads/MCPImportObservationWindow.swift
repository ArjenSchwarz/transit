#if os(macOS)
import Foundation

nonisolated enum MCPImportObservationError: Error { case busy, tooManyImports }

/// Hold from refresh decision through capture. At most eight admitted observations exist;
/// each retains at most 256 declared event IDs, never a global event history.
/// Overflow rejects registration; callers use unavailable/unknown fallback.
nonisolated final class MCPImportObservationWindow: @unchecked Sendable {
    let id: UUID
    let applicableImportIDs: Set<UUID>
    private weak var monitor: MCPImportEvidenceMonitor?

    init(id: UUID, applicableImportIDs: Set<UUID>, monitor: MCPImportEvidenceMonitor) {
        self.id = id
        self.applicableImportIDs = applicableImportIDs
        self.monitor = monitor
    }

    func close() { monitor?.endObservation(id) }
    deinit { close() }
}

nonisolated struct MCPImportWindowEvidence: Sendable {
    let applicableImportIDs: Set<UUID>
    var successes: [UUID: MCPObservedImport] = [:]
    var failures: [UUID: UInt64] = [:]
}
#endif
