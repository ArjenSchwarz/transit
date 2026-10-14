import Foundation
import Synchronization
import OSLog

nonisolated enum MCPReadDiagnosticPhase: Sendable, Equatable {
    case queue, validation, refresh, capture, transform, serialization, aggregation, terminal, physicalFinish, discard
}

nonisolated enum MCPReadDiagnosticOutcome: Sendable, Equatable {
    case success, timeout, busy, failure, discarded, lateCompletion
}

/// Correlation scalars only: diagnostics never retain a captured view or a result buffer.
nonisolated struct MCPReadDiagnosticContext: Sendable {
    let operationID: UUID
    let tool: String
    let generation: UInt64
    let admittedAt: ContinuousClock.Instant
    /// Original external five-second boundary, distinct from the internal selection cutoff.
    let responseDeadline: ContinuousClock.Instant
    let internalCutoff: ContinuousClock.Instant
}

/// Only actual measured intervals belong here; an unmeasured phase produces no fabricated duration.
nonisolated struct MCPReadDiagnosticEvent: Sendable {
    let context: MCPReadDiagnosticContext
    let phase: MCPReadDiagnosticPhase
    let startedAt: ContinuousClock.Instant
    let finishedAt: ContinuousClock.Instant
    let outcome: MCPReadDiagnosticOutcome?
    let unfinishedPhysicalCount: Int
    var failure: MCPReadFailureSnapshot?
}

/// Bounded active-plus-queued records. The writer never holds either publication or sink lock.
nonisolated final class MCPReadDiagnosticSink: Sendable {
    static let disabled = MCPReadDiagnosticSink(capacity: 0, writer: { _ in })
    static let application = MCPReadDiagnosticSink(writer: MCPReadDiagnosticLogging.write)
    let capacity: Int
    private let writer: @Sendable (MCPReadDiagnosticEvent) -> Void
    private let state = Mutex(State())
    private let queue: DispatchQueue?

    private struct State: Sendable {
        var events: [MCPReadDiagnosticEvent] = []
        var unfinished = 0
        var draining = false
        var dropped: UInt64 = 0
    }

    init(capacity: Int = 64, writer: @escaping @Sendable (MCPReadDiagnosticEvent) -> Void) {
        self.capacity = max(0, capacity)
        self.writer = writer
        queue = capacity > 0 ? DispatchQueue(label: "transit.read.diagnostics", qos: .utility) : nil
    }

    var droppedCount: UInt64 { state.withLock { $0.dropped } }

    var pendingCount: Int { state.withLock { $0.unfinished } }

    @discardableResult func enqueue(_ event: MCPReadDiagnosticEvent) -> Bool {
        guard let queue else { return false }
        let admission = state.withLock { state -> (accepted: Bool, start: Bool) in
            if state.unfinished >= capacity {
                // Preserve failure evidence by retiring a queued ordinary debug event.
                if event.failure != nil, let index = state.events.firstIndex(where: { $0.failure == nil }) {
                    state.events.remove(at: index)
                    state.unfinished -= 1
                } else {
                    state.dropped &+= 1
                    return (false, false)
                }
                state.dropped &+= 1
            }
            state.events.append(event)
            state.unfinished += 1
            let start = !state.draining
            state.draining = true
            return (true, start)
        }
        if admission.start { queue.async { self.drain() } }
        return admission.accepted
    }

    private func drain() {
        while true {
            let event = state.withLock { state -> MCPReadDiagnosticEvent? in
                guard !state.events.isEmpty else { state.draining = false; return nil }
                return state.events.removeFirst()
            }
            guard let event else { return }
            var delivered = event
            delivered.failure?.droppedEvents = droppedCount
            writer(delivered)
            state.withLock { $0.unfinished -= 1 }
        }
    }
}

nonisolated private enum MCPReadDiagnosticLogging {
    private static let logger = Logger(subsystem: "me.nore.ig.Transit", category: "MCP.Read")
    private static let journal = MCPReadFailureJournal(url: URL.cachesDirectory
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Transit", isDirectory: true)
        .appendingPathComponent("MCPReadFailures.json"))
    static func write(_ event: MCPReadDiagnosticEvent) {
        if let failure = event.failure {
            do { try journal.append(failure) } catch {
                logger.error("Bounded MCP read failure journal could not be saved")
            }
            logger.notice("""
                Read failure outcome=\(failure.outcome, privacy: .public) tool=\(failure.tool, privacy: .public) \
                phase=\(failure.phase, privacy: .public) process_uptime_ms=\(failure.processUptimeMs ?? -1) \
                admission_elapsed_ms=\(failure.admissionElapsedMs) cutoff_overrun_ms=\(failure.cutoffOverrunMs) \
                phase_age_ms=\(failure.phaseAgeMs) oldest_worker_ms=\(failure.oldestWorkerAgeMs) \
                physical=\(failure.physicalCount) dropped=\(failure.droppedEvents)
                """)
        }
        let elapsed = event.startedAt.duration(to: event.finishedAt).components
        let milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
        let phase = String(describing: event.phase)
        let outcome = event.outcome.map { String(describing: $0) } ?? "unclassified"
        let offset = event.context.admittedAt.duration(to: event.startedAt).components
        let offsetMs = Double(offset.seconds) * 1_000 + Double(offset.attoseconds) / 1e15
        let external = event.context.admittedAt.duration(to: event.context.responseDeadline).components
        let cutoff = event.context.admittedAt.duration(to: event.context.internalCutoff).components
        let externalMs = Double(external.seconds) * 1_000 + Double(external.attoseconds) / 1e15
        let cutoffMs = Double(cutoff.seconds) * 1_000 + Double(cutoff.attoseconds) / 1e15
        logger.debug("""
            read id=\(event.context.operationID.uuidString, privacy: .public) \
            tool=\(event.context.tool, privacy: .public) generation=\(event.context.generation) \
            phase=\(phase, privacy: .public) admission_offset_ms=\(offsetMs) elapsed_ms=\(milliseconds) \
            budget_ms=\(externalMs) cutoff_ms=\(cutoffMs) \
            outcome=\(outcome, privacy: .public) physical=\(event.unfinishedPhysicalCount)
            """)
    }
}
