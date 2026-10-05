import Foundation
import SwiftData

nonisolated struct TaskLinkSavedDetail: Sendable {
    let source: TaskLinkTaskValue
    let graph: TaskLinkGraphView
    let duplicateResolution: TaskLinkDuplicateResolution
}

/// Saved-only adapters never borrow UI models or save during read/preview.
@MainActor
final class TaskLinkService {
    private let container: ModelContainer

    init(container: ModelContainer) { self.container = container }

    /// A separate bounded owned context; never called by read, preview or graph apply.
    func cleanupExpiredEvidence(evaluationInstant: Date = Date(), limit: Int = 128,
                                budget: TaskLinkGraphBudget = TaskLinkGraphBudget()) throws -> Int {
        try TaskLinkEvidenceMaintenance.cleanup(container: container, instant: evaluationInstant,
                                               limit: limit, budget: budget)
    }

    func savedGraph(budget: TaskLinkGraphBudget = TaskLinkGraphBudget()) throws -> TaskLinkGraphView {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try Self.graph(in: context, budget: budget)
    }

    func savedDetail(
        for source: UUID, budget: TaskLinkGraphBudget = TaskLinkGraphBudget()
    ) throws -> TaskLinkSavedDetail {
        let graph = try savedGraph(budget: budget)
        guard let matches = graph.tasksById[source], matches.count == 1, let task = matches.first else {
            throw TaskLinkGraphError.ambiguousIdentity
        }
        return try TaskLinkSavedDetail(source: task, graph: graph,
            duplicateResolution: TaskLinkGraph.duplicateResolution(for: source, in: graph, budget: budget))
    }

    /// The caller supplies a clean, fresh owned context for write validation.
    /// Capture uses the same context as the existing read fence when integrated there.
    static func graph(
        in context: ModelContext, capturedTasks: [TransitTask]? = nil, evaluationInstant: Date = Date(),
        budget: TaskLinkGraphBudget = TaskLinkGraphBudget()
    ) throws -> TaskLinkGraphView {
        try budget.check()
        var taskFetch = FetchDescriptor<TransitTask>()
        taskFetch.includePendingChanges = false
        var edgeFetch = FetchDescriptor<TaskLinkOccurrence>()
        edgeFetch.includePendingChanges = false
        var removalFetch = FetchDescriptor<TaskLinkRemovalEvidence>()
        removalFetch.includePendingChanges = false
        let population = try capturedTasks ?? context.fetch(taskFetch)
        let tasks = try population.map { task in
            try budget.check()
            return try TaskLinkTaskValue(physicalKey: key(task), id: task.id, name: task.name,
                                         status: task.statusRawValue)
        }
        let edges = try context.fetch(edgeFetch).map { row in
            try budget.check()
            return try TaskLinkOccurrenceValue(physicalKey: key(row), id: row.id, kind: row.kindRawValue,
                source: row.sourceTaskID, target: row.targetTaskID, createdAt: row.createdAt)
        }
        let removals = try context.fetch(removalFetch).map { row in
            try budget.check()
            return try TaskLinkRemovalValue(physicalKey: key(row), id: row.id, edgeId: row.edgeId,
                kind: row.kindRawValue, source: row.sourceTaskID, target: row.targetTaskID, createdAt: row.createdAt,
                occurrenceRevision: row.occurrenceRevision, removedAt: row.removedAt)
        }
        return try TaskLinkGraph.project(tasks: tasks, occurrences: edges, removalEvidence: removals,
                                         evaluationInstant: evaluationInstant, budget: budget)
    }

    private static func key(_ model: some PersistentModel) throws -> Data {
        try JSONEncoder().encode(model.persistentModelID)
    }
}
