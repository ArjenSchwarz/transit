import Foundation

extension MCPReadCoordinator {
    nonisolated final class Entry: @unchecked Sendable {
        let owner: MCPReadAdmissionOwner
        let id: UUID
        let generation: UInt64
        let deadline: ContinuousClock.Instant
        let diagnosticContext: MCPReadDiagnosticContext
        var actorQueuedAt: ContinuousClock.Instant?
        var terminalEvent: MCPReadDiagnosticEvent?
        var terminalDelivered = false
        let physicalCompletion: @Sendable () -> Void
        var timeout: Data
        var responseReady = true
        var invalidated = false
        var selected: Data?
        var continuation: CheckedContinuation<Data, Never>?
        var timer: DispatchSourceTimer?

        init(id: UUID, generation: UInt64, deadline: ContinuousClock.Instant, timeout: Data,
             admittedAt: ContinuousClock.Instant, diagnosticTool: String, owner: MCPReadAdmissionOwner = .application,
             physicalCompletion: @escaping @Sendable () -> Void = {}) {
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

}
