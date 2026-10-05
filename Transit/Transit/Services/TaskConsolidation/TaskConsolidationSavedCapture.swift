import Foundation
import SwiftData

nonisolated enum ConsolidationCaptureFence: Sendable {
    case persistentHistory, actorOnlyTestFixture
}

nonisolated struct ConsolidationCaptureSelection: Sendable {
    let selectedTaskIds: [UUID]
    var operationId: UUID?
    var requireSelectedOriginals = true
}

nonisolated struct ConsolidationSavedEvidence: Sendable {
    let selectedTaskIds: [UUID]
    let originals: [ConsolidationOriginal]
    let events: [TaskConsolidationEventValue]
    let history: [ConsolidationHistoryProjection]
    let graph: TaskLinkGraphView
    let encodedByteCount: Int
}

@MainActor final class TaskConsolidationSavedCapture {
    private let container: ModelContainer
    private let fence: ConsolidationCaptureFence
    private let generation: () -> UInt64
    private let afterCopy: () throws -> Void
    private let fetchEvents: ((ModelContext) throws -> [TaskConsolidationEvent])?
    private let fetchComments: (ModelContext, UUID) throws -> [Comment]
    private var isCapturing = false

    struct Hooks {
        var generation: () -> UInt64 = { 0 }
        var afterCopy: () throws -> Void = {}
        var fetchEvents: ((ModelContext) throws -> [TaskConsolidationEvent])?
        var fetchComments: (ModelContext, UUID) throws -> [Comment] = { context, id in
            var descriptor = CommentService.descriptor(for: id)
            descriptor.includePendingChanges = false
            return try context.fetch(descriptor)
        }
    }

    init(container: ModelContainer, fence: ConsolidationCaptureFence = .persistentHistory, hooks: Hooks = Hooks()) {
        self.container = container
        self.fence = fence
        self.generation = hooks.generation
        self.afterCopy = hooks.afterCopy
        self.fetchEvents = hooks.fetchEvents
        self.fetchComments = hooks.fetchComments
    }

    func capture(selectedTaskIds: [UUID], operationId: UUID? = nil,
                 budget: TaskLinkGraphBudget = TaskLinkGraphBudget()) throws -> ConsolidationSavedEvidence {
        guard !isCapturing else { throw SavedReadBoundaryError.incoherentCapture }
        isCapturing = true
        defer { isCapturing = false }
        try budget.check()
        let initialGeneration = generation()
        let before = try watermark()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let evidence = try copy(.init(selectedTaskIds: selectedTaskIds, operationId: operationId),
            in: context, budget: budget)
        try afterCopy()
        let after = try watermark()
        guard initialGeneration == generation(), before?.token == after?.token,
              before?.storeIdentifier == after?.storeIdentifier else {
            throw SavedReadBoundaryError.incoherentCapture
        }
        try budget.check()
        return evidence
    }

    private func watermark() throws -> DefaultHistoryTransaction? {
        try fence == .persistentHistory ? SavedReadBoundary.watermark(container) : nil
    }

    /// Supplementary dependencies remain separate from the caller's declared selection.
    func copy(_ request: ConsolidationCaptureSelection, in context: ModelContext,
              graph suppliedGraph: TaskLinkGraphView? = nil,
              budget: TaskLinkGraphBudget = TaskLinkGraphBudget()) throws -> ConsolidationSavedEvidence {
        let selectedTaskIds = request.selectedTaskIds, operationId = request.operationId
        try budget.check()
        let graph = try suppliedGraph ?? TaskLinkService.graph(in: context, budget: budget)
        let selected = Set(selectedTaskIds)
        let events = try operationEvents(selected: selected, operationId: operationId,
            context: context, budget: budget)
        let operations = Set(events.map(\.operationId))
        var required = selected
        for id in operations {
            try budget.check()
            let history = try TaskConsolidationHistoryCodec.history(events.filter { $0.operationId == id },
                operationId: id)
            required.formUnion([history.apply.survivorTaskId] + history.apply.candidateTaskIds)
        }
        for id in Array(required) {
            required.formUnion(try TaskLinkGraph.duplicateResolution(for: id, in: graph, budget: budget).path)
        }
        let originals = try captureOriginals(request, required: required, context: context,
            graph: graph, budget: budget)
        let history = try operations.sorted { $0.uuidString < $1.uuidString }.map { id in
            try budget.check()
            return try ConsolidationHistoryProjection.make(events: events.filter { $0.operationId == id },
                operationId: id, originals: originals, graph: graph, budget: budget)
        }
        let graphJSON = try graphRepresentation(graph)
        let wrapper = ConsolidationCaptureRepresentation(selection: selectedTaskIds, originals: originals,
            events: events, history: history, graphJSON: graphJSON)
        let bytes = try JSONEncoder().encode(wrapper).count + graph.retainedBytes
        guard bytes <= budget.maximumBytes else { throw TaskLinkGraphError.capacityExceeded }
        try budget.check()
        return ConsolidationSavedEvidence(selectedTaskIds: selectedTaskIds, originals: originals,
            events: events, history: history, graph: graph, encodedByteCount: bytes)
    }

    private func captureOriginals(_ request: ConsolidationCaptureSelection, required: Set<UUID>,
                                  context: ModelContext, graph: TaskLinkGraphView,
                                  budget: TaskLinkGraphBudget) throws -> [ConsolidationOriginal] {
        var descriptor = FetchDescriptor<TransitTask>()
        descriptor.includePendingChanges = false
        let tasks = try context.fetch(descriptor).filter { required.contains($0.id) }
        let originals = try tasks.compactMap { task -> ConsolidationOriginal? in
            try budget.check()
            guard let project = task.project else {
                if request.requireSelectedOriginals && request.selectedTaskIds.contains(task.id) {
                    throw ConsolidationPlanningError.unavailableEvidence
                }
                return nil
            }
            guard task.name.utf8.count + (task.taskDescription?.utf8.count ?? 0)
                + (task.metadataJSON?.utf8.count ?? 0) <= budget.maximumBytes else {
                throw TaskLinkGraphError.capacityExceeded
            }
            let snapshot = try MCPRecordSnapshot.task(task, incidence: graph.occurrences.filter {
                    $0.source == task.id || $0.target == task.id
                },
                budget: budget, fetchComments: { try captureComments(context, id: $0, budget: budget) })
            let matching = try graph.tasks.filter { value in
                try value.id == task.id && JSONDecoder().decode(PersistentIdentifier.self, from: value.physicalKey)
                    == task.persistentModelID
            }
            guard matching.count == 1, let physicalKey = matching.first?.physicalKey else {
                throw ConsolidationPlanningError.unavailableEvidence
            }
            return try ConsolidationOriginal(id: task.id, physicalKey: physicalKey,
                projectId: project.id, projectPhysicalKey: canonicalProjectKey(project),
                fields: TaskConsolidationRawFields.capture(task), revision: snapshot.revision,
                recordJSON: JSONSerialization.data(withJSONObject: snapshot.record, options: [.sortedKeys]))
        }.sorted { $0.physicalKey.lexicographicallyPrecedes($1.physicalKey) }
        for id in request.selectedTaskIds where request.requireSelectedOriginals {
            guard originals.filter({ $0.id == id }).count == 1 else {
                throw ConsolidationPlanningError.unavailableEvidence
            }
        }
        return originals
    }

    private func captureComments(_ context: ModelContext, id: UUID, budget: TaskLinkGraphBudget) throws -> [Comment] {
        let comments = try fetchComments(context, id)
        var bytes = 0
        for comment in comments {
            try budget.check()
            bytes += comment.content.utf8.count + comment.authorName.utf8.count + 128
            guard bytes <= budget.maximumBytes else { throw TaskLinkGraphError.capacityExceeded }
        }
        return comments
    }

    private func canonicalProjectKey(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(project.persistentModelID)
    }

    private func operationEvents(selected: Set<UUID>, operationId: UUID?, context: ModelContext,
                                 budget: TaskLinkGraphBudget) throws -> [TaskConsolidationEventValue] {
        var operations: Set<UUID> = operationId.map { [$0] } ?? []
        let injected = try fetchEvents?(context)
        if let injected {
            for row in injected {
                try budget.check()
                if selected.contains(row.survivorTaskId)
                    || [row.candidate1, row.candidate2, row.candidate3, row.candidate4, row.candidate5]
                        .compactMap({ $0 }).contains(where: selected.contains) {
                    operations.insert(row.operationId)
                }
            }
        } else {
            for id in selected {
                try budget.check()
                var descriptor = FetchDescriptor<TaskConsolidationEvent>(predicate: #Predicate {
                    $0.survivorTaskId == id || $0.candidate1 == id || $0.candidate2 == id
                        || $0.candidate3 == id || $0.candidate4 == id || $0.candidate5 == id
                })
                descriptor.includePendingChanges = false
                guard try context.fetchCount(descriptor) <= budget.maximumBytes / 128 else {
                    throw TaskLinkGraphError.capacityExceeded
                }
                for row in try context.fetch(descriptor) { operations.insert(row.operationId) }
            }
        }
        var values: [TaskConsolidationEventValue] = []
        var charged = 0
        for id in operations.sorted(by: { $0.uuidString < $1.uuidString }) {
            try budget.check()
            let rows = try operationRows(id, injected: injected, context: context)
            for row in rows {
                try budget.check()
                charged += row.payloadJSON.utf8.count + row.originScopeId.utf8.count + 256
                guard charged <= budget.maximumBytes else { throw TaskLinkGraphError.capacityExceeded }
                values.append(try TaskConsolidationEventValue.capture(row))
            }
        }
        return values
    }

    private func operationRows(_ id: UUID, injected: [TaskConsolidationEvent]?, context: ModelContext) throws
        -> [TaskConsolidationEvent] {
        if let injected { return injected.filter { $0.operationId == id } }
        var descriptor = FetchDescriptor<TaskConsolidationEvent>(predicate: #Predicate { $0.operationId == id })
        descriptor.includePendingChanges = false
        guard try context.fetchCount(descriptor) <= 2 else { throw TaskConsolidationHistoryError.ambiguous }
        return try context.fetch(descriptor)
    }

    private func graphRepresentation(_ graph: TaskLinkGraphView) throws -> Data {
        let tasks: [[String: Any]] = graph.tasks.map {
            ["physicalKey": $0.physicalKey.base64EncodedString(), "id": $0.id.uuidString,
             "name": $0.name, "status": $0.status]
        }
        let occurrences: [[String: Any]] = try graph.occurrences.map {
            ["physicalKey": $0.physicalKey.base64EncodedString(), "id": $0.id.uuidString,
             "kind": $0.kind, "source": $0.source.uuidString, "target": $0.target.uuidString,
             "createdAt": try TaskConsolidationRawFields.exactDate($0.createdAt)]
        }
        let removals: [[String: Any]] = try graph.removalEvidence.map {
            ["physicalKey": $0.physicalKey.base64EncodedString(), "id": $0.id.uuidString,
             "edgeId": $0.edgeId.uuidString, "kind": $0.kind, "source": $0.source.uuidString,
             "target": $0.target.uuidString, "createdAt": try TaskConsolidationRawFields.exactDate($0.createdAt),
             "removedAt": try TaskConsolidationRawFields.exactDate($0.removedAt), "revision": $0.occurrenceRevision]
        }
        return try JSONSerialization.data(withJSONObject: ["tasks": tasks, "occurrences": occurrences,
            "removals": removals], options: [.sortedKeys])
    }
}

private nonisolated struct ConsolidationCaptureRepresentation: Codable {
    let selection: [UUID]
    let originals: [ConsolidationOriginal]
    let events: [TaskConsolidationEventValue]
    let history: [ConsolidationHistoryProjection]
    let graphJSON: Data
}
