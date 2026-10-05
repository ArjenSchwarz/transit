#if os(macOS)
import Foundation
import SwiftData

/// One synchronous operation. Independent store/import writers remain outside
/// this coordination contract; no saved predicate fence is claimed.
@MainActor final class TaskLinkOwnedPlan {
    private var context: ModelContext?
    private var sourceID: UUID?
    private var plan: TaskLinkPlan?
    private var budget = TaskLinkGraphBudget()
    private var instant = Date()

    func validate(_ command: MCPWriteCommand, prepared: PreparedMCPWrite,
                  services: MCPWriteCommandServices) throws {
        guard context == nil, !services.context.hasChanges, !services.context.autosaveEnabled else {
            throw MCPWriteFailure("OUTCOME_UNCERTAIN", "Unable to establish owned graph validation")
        }
        context = services.context
        budget = TaskLinkGraphBudget()
        instant = Date()
        guard let source = try validateSource(command, prepared: prepared, in: services.context) else { return }
        let (id, creating) = source
        sourceID = id
        let requestValue = try TaskLinkWireRequest.parse(tool: command.tool, arguments: command.arguments)
        guard let request = requestValue else { return }
        guard !request.changes.isEmpty else {
            guard request.endpointPreconditions.isEmpty else {
                throw MCPWriteFailure("INVALID_INPUT", "No link changes require no endpoint guards")
            }
            return
        }
        do {
            var graph = try TaskLinkService.graph(in: services.context, evaluationInstant: instant, budget: budget)
            if let creating {
                let virtual = TaskLinkTaskValue(physicalKey: Data(("prepared:" + id.uuidString).utf8),
                                               id: id, name: creating.name, status: TaskStatus.idea.rawValue)
                graph = try TaskLinkGraph.project(tasks: graph.tasks + [virtual], occurrences: graph.occurrences,
                    removalEvidence: graph.removalEvidence, evaluationInstant: instant, budget: budget)
            }
            var revisions: [UUID: String] = [:]
            for endpoint in request.endpointPreconditions.keys {
                try budget.check()
                let snapshot = try endpointSnapshot(endpoint, in: services.context)
                revisions[endpoint] = snapshot.revision
                guard request.endpointPreconditions[endpoint] == snapshot.revision else {
                    throw MCPWriteFailure("REVISION_CONFLICT", "Endpoint content changed",
                                          currentRecord: snapshot.record)
                }
            }
            plan = try TaskLinkPlan.validate(delta: request.changes, source: id,
                preconditions: request.endpointPreconditions, revisions: revisions, savedGraph: graph, budget: budget)
        } catch {
            let failure = TaskLinkWriteFailure.map(error)
            if failure.code == "REVISION_CONFLICT", failure.currentRecord == nil, creating == nil {
                let current = try endpointSnapshot(id, in: services.context)
                throw MCPWriteFailure(failure.code, failure.message, currentRecord: current.record)
            }
            throw failure
        }
    }

    func apply(_ command: MCPWriteCommand, task: TransitTask, services: MCPWriteCommandServices) throws {
        guard services.context === context, task.modelContext === context, task.id == sourceID else {
            throw MCPWriteFailure("OUTCOME_UNCERTAIN", "Owned graph plan/context identity changed")
        }
        guard let plan else { return }
        try budget.check()
        try TaskLinkOwnedApply.apply(plan, in: services.context, instant: instant, budget: budget)
        self.plan = nil
    }

    private func validateSource(_ command: MCPWriteCommand, prepared: PreparedMCPWrite,
                                in context: ModelContext) throws -> (UUID, TaskService.PreparedCreation?)? {
        let creating: TaskService.PreparedCreation?
        let id: UUID
        switch prepared {
        case let .taskCreation(creation, identity): id = identity; creating = creation
        case let .task(identity): id = identity; creating = nil
        default: return nil
        }
        var descriptor = FetchDescriptor<TransitTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 2
        descriptor.includePendingChanges = false
        let rows = try context.fetch(descriptor)
        if creating != nil {
            guard rows.isEmpty else {
                throw MCPWriteFailure("DUPLICATE_TASK_IDENTIFIER", "Prepared task UUID already exists")
            }
        } else {
            let snapshot = try endpointSnapshot(id, in: context)
            if let expected = command.expectedRevision, expected != snapshot.revision {
                throw MCPWriteFailure("REVISION_CONFLICT", "Task content changed", currentRecord: snapshot.record)
            }
        }
        return (id, creating)
    }

    private func endpointSnapshot(_ id: UUID, in context: ModelContext) throws -> MCPRecordSnapshot {
        var descriptor = FetchDescriptor<TransitTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 2
        descriptor.includePendingChanges = false
        let rows = try context.fetch(descriptor)
        guard rows.count == 1, let task = rows.first else {
            throw MCPWriteFailure(rows.isEmpty ? "TASK_NOT_FOUND" : "DUPLICATE_TASK_IDENTIFIER",
                                  "Affected endpoint is unavailable or ambiguous")
        }
        return try MCPRecordSnapshot.task(task, in: context)
    }
}
#endif
