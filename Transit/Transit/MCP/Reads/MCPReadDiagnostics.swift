#if os(macOS)
import Foundation
import NIOConcurrencyHelpers
import OSLog

nonisolated enum MCPReadDiagnosticPhase: Sendable, Equatable {
    case queue, refresh, capture, transform, serialization, aggregation, terminal, physicalFinish, discard
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
}

/// Bounded active-plus-queued records. The writer never holds either publication or sink lock.
nonisolated final class MCPReadDiagnosticSink: Sendable {
    static let disabled = MCPReadDiagnosticSink(capacity: 0, writer: { _ in })
    static let application = MCPReadDiagnosticSink(writer: MCPReadDiagnosticLogging.write)
    let capacity: Int
    private let writer: @Sendable (MCPReadDiagnosticEvent) -> Void
    private let state = NIOLockedValueBox(State())
    private let queue: DispatchQueue?

    private struct State: Sendable {
        var events: [MCPReadDiagnosticEvent] = []
        var unfinished = 0
        var draining = false
    }

    init(capacity: Int = 64, writer: @escaping @Sendable (MCPReadDiagnosticEvent) -> Void) {
        self.capacity = max(0, capacity)
        self.writer = writer
        queue = capacity > 0 ? DispatchQueue(label: "transit.read.diagnostics", qos: .utility) : nil
    }

    var pendingCount: Int { state.withLockedValue { $0.unfinished } }

    @discardableResult func enqueue(_ event: MCPReadDiagnosticEvent) -> Bool {
        guard let queue else { return false }
        let admission = state.withLockedValue { state -> (accepted: Bool, start: Bool) in
            guard state.unfinished < capacity else { return (false, false) }
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
            let event = state.withLockedValue { state -> MCPReadDiagnosticEvent? in
                guard !state.events.isEmpty else { state.draining = false; return nil }
                return state.events.removeFirst()
            }
            guard let event else { return }
            writer(event)
            state.withLockedValue { $0.unfinished -= 1 }
        }
    }
}

nonisolated private enum MCPReadDiagnosticLogging {
    private static let logger = Logger(subsystem: "me.nore.ig.Transit", category: "MCP.Read")
    static func write(_ event: MCPReadDiagnosticEvent) {
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
#endif
