import Foundation

extension MCPReadCoordinator {
    nonisolated final class Entry: @unchecked Sendable {
        let owner: MCPReadAdmissionOwner
        let id: UUID
        let generation: UInt64
        let deadline: ContinuousClock.Instant
        let diagnosticContext: MCPReadDiagnosticContext
        var currentPhase: MCPReadDiagnosticPhase = .queue
        var phaseStartedAt: ContinuousClock.Instant
        var actorQueuedAt: ContinuousClock.Instant?
        var terminalEvent: MCPReadDiagnosticEvent?
        var terminalDelivered = false
        let physicalCompletion: @Sendable () -> Void
        var timeout: Data
        var responseReady = true
        var invalidated = false
        var invalidationReason: MCPReadFailureReason = .deadline
        var selected: Data?
        var continuation: CheckedContinuation<Data, Never>?
        var timer: DispatchSourceTimer?

        init(id: UUID, generation: UInt64, deadline: ContinuousClock.Instant, timeout: Data,
             admittedAt: ContinuousClock.Instant, diagnosticTool: String, owner: MCPReadAdmissionOwner = .application,
             physicalCompletion: @escaping @Sendable () -> Void = {}) {
            self.phaseStartedAt = admittedAt
            self.owner = owner
            self.id = id
            self.generation = generation
            self.deadline = deadline
            self.diagnosticContext = MCPReadDiagnosticContext(operationID: id, tool: diagnosticTool,
                generation: generation, admittedAt: admittedAt, responseDeadline: admittedAt + .seconds(5),
                internalCutoff: deadline)
            self.timeout = timeout
            self.physicalCompletion = physicalCompletion
        }
    }

    nonisolated func beginPhase(id: UUID, phase: MCPReadDiagnosticPhase) {
        guard diagnostics.capacity > 0 else { return }
        domain.withLock {
            guard let entry = entries[id], entry.selected == nil else { return }
            entry.currentPhase = phase
            entry.phaseStartedAt = .now
        }
    }

    // Called under the publication lock: bounded scalars only, no logging or file I/O.
    // swiftlint:disable:next function_parameter_count
    nonisolated func failureSnapshot(context: MCPReadDiagnosticContext, phase: MCPReadDiagnosticPhase,
                                     startedAt: ContinuousClock.Instant, outcome: MCPReadDiagnosticOutcome,
                                     reason: MCPReadFailureReason, now: ContinuousClock.Instant)
        -> MCPReadFailureSnapshot {
        MCPReadFailureSnapshot(tool: context.tool, phase: phase, outcome: outcome, generation: context.generation,
            reason: reason, processUptimeMs: MCPReadProcessClock.uptimeMilliseconds(),
            admissionElapsedMs: MCPReadTiming.seconds(context.admittedAt.duration(to: now)) * 1_000,
            cutoffOverrunMs: MCPReadTiming.seconds(context.internalCutoff.duration(to: now)) * 1_000,
            phaseAgeMs: MCPReadTiming.seconds(startedAt.duration(to: now)) * 1_000,
            oldestWorkerAgeMs: entries.values.map {
                MCPReadTiming.seconds($0.diagnosticContext.admittedAt.duration(to: now)) * 1_000
            }.max() ?? 0, physicalCount: entries.count)
    }

    nonisolated func beginActorQueue(id: UUID) {
        guard diagnostics.capacity > 0 else { return }
        beginPhase(id: id, phase: .queue)
        domain.withLock { entries[id]?.actorQueuedAt = .now }
    }

    nonisolated func finishActorQueue(id: UUID) {
        guard diagnostics.capacity > 0 else { return }
        let interval = domain.withLock { () -> (MCPReadDiagnosticContext, ContinuousClock.Instant)? in
            guard let entry = entries[id], let started = entry.actorQueuedAt else { return nil }
            entry.actorQueuedAt = nil
            return (entry.diagnosticContext, started)
        }
        if let (context, started) = interval { recordDiagnostic(context: context, phase: .queue, startedAt: started) }
    }
}
