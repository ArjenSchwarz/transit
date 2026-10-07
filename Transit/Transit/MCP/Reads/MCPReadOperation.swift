import Foundation

nonisolated struct MCPReadOperation: Sendable {
    let id: UUID
    let generation: UInt64
    let diagnosticContext: MCPReadDiagnosticContext
    private let coordinator: MCPReadCoordinator

    init(id: UUID, generation: UInt64, context: MCPReadDiagnosticContext, coordinator: MCPReadCoordinator) {
        self.id = id
        self.generation = generation
        self.coordinator = coordinator
        self.diagnosticContext = context
    }

    func recordDiagnostic(_ phase: MCPReadDiagnosticPhase, startedAt: ContinuousClock.Instant,
                          outcome: MCPReadDiagnosticOutcome? = nil) {
        coordinator.recordDiagnostic(context: diagnosticContext, phase: phase, startedAt: startedAt, outcome: outcome)
    }

    func beginActorQueue() { coordinator.beginActorQueue(id: id) }
    func finishActorQueue() { coordinator.finishActorQueue(id: id) }

    func shouldContinue() -> Bool { coordinator.canContinue(id: id, generation: generation) }

    /// Remaining original admission budget, never a clock restarted by a handler.
    func remainingBudget() -> Duration { coordinator.remainingBudget(id: id, generation: generation) }
}

extension MCPReadCoordinator {
    nonisolated func recordDiagnostic(context: MCPReadDiagnosticContext, phase: MCPReadDiagnosticPhase,
                                      startedAt: ContinuousClock.Instant, outcome: MCPReadDiagnosticOutcome? = nil) {
        guard diagnostics.capacity > 0 else { return }
        let finished = ContinuousClock.now
        let count = unfinishedCount
        diagnostics.enqueue(MCPReadDiagnosticEvent(context: context, phase: phase, startedAt: startedAt,
            finishedAt: finished, outcome: outcome, unfinishedPhysicalCount: count))
    }

}
