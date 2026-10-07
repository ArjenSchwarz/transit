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
    private let participantQuery: (Int) -> Void
    private var isCapturing = false

    struct Hooks {
        var participantQuery: (Int) -> Void = { _ in }
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
        self.participantQuery = hooks.participantQuery
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
        let charge = ConsolidationCaptureCharge(budget: budget)
        try charge.append(graph.retainedBytes)
        let events = try operationEvents(selected: selected, operationId: operationId,
            context: context, charge: charge)
        var grouped: [UUID: [TaskConsolidationEventValue]] = [:]
        for event in events {
            try budget.check()
            grouped[event.operationId, default: []].append(event)
        }
        let operations = Set(grouped.keys)
        var required: Set<UUID> = request.requireSelectedOriginals ? selected : []
        for id in operations {
            try budget.check()
            let history = try TaskConsolidationHistoryCodec.history(grouped[id, default: []],
                operationId: id)
            required.formUnion([history.apply.survivorTaskId] + history.apply.candidateTaskIds)
        }
        for id in Array(required) {
            required.formUnion(try TaskLinkGraph.duplicateResolution(for: id, in: graph, budget: budget).path)
        }
        let originals = try captureOriginals(request, required: required, context: context,
            graph: graph, charge: charge)
        var history: [ConsolidationHistoryProjection] = []
        for id in operations.sorted(by: { $0.uuidString < $1.uuidString }) {
            try budget.check()
            let projection = try ConsolidationHistoryProjection.make(events: grouped[id, default: []],
                operationId: id, originals: originals, graph: graph, budget: budget)
            try budget.check()
            try charge.append(JSONEncoder().encode(projection).count)
            history.append(projection)
        }
        try budget.check()
        let graphJSON = try graphRepresentation(graph)
        try charge.append(graphJSON.count)
        let wrapper = ConsolidationCaptureRepresentation(selection: selectedTaskIds, originals: originals,
            events: events, history: history, graphJSON: graphJSON)
        try budget.check()
        let bytes = try JSONEncoder().encode(wrapper).count + graph.retainedBytes
        guard bytes <= budget.maximumBytes else { throw TaskLinkGraphError.capacityExceeded }
        try budget.check()
        return ConsolidationSavedEvidence(selectedTaskIds: selectedTaskIds, originals: originals,
            events: events, history: history, graph: graph, encodedByteCount: bytes)
    }

    private func captureOriginals(_ request: ConsolidationCaptureSelection, required: Set<UUID>,
                                  context: ModelContext, graph: TaskLinkGraphView,
                                  charge: ConsolidationCaptureCharge) throws -> [ConsolidationOriginal] {
        let budget = charge.budget
        var descriptor = FetchDescriptor<TransitTask>()
        descriptor.includePendingChanges = false
        let tasks = try context.fetch(descriptor).filter { required.contains($0.id) }
        for id in request.selectedTaskIds where request.requireSelectedOriginals {
            let count = tasks.filter { $0.id == id }.count
            guard count == 1 else {
                throw ConsolidationSelectionFailure(id, count == 0 ? "missing_task" : "ambiguous_task")
            }
        }
        let originals = try tasks.compactMap { task -> ConsolidationOriginal? in
            try budget.check()
            guard let project = task.project else {
                if request.requireSelectedOriginals && request.selectedTaskIds.contains(task.id) {
                    throw ConsolidationSelectionFailure(task.id, "missing_project")
                }
                return nil
            }
            // Description appears twice; raw metadata appears once, while the record
            // retains decoded metadata. Whitespace must not cause a false capacity failure.
            let minimum = task.name.utf8.count + 2 * (task.taskDescription?.utf8.count ?? 0)
                + (task.metadataJSON?.utf8.count ?? 0)
            try charge.checkAdditional(minimum)
            let snapshot = try MCPRecordSnapshot.task(task, incidence: graph.occurrences.filter {
                    $0.source == task.id || $0.target == task.id
                },
                budget: budget, fetchComments: {
                    try captureComments(context, id: $0, charge: charge, minimum: minimum)
                })
            let matching = try graph.tasks.filter { value in
                try value.id == task.id && JSONDecoder().decode(PersistentIdentifier.self, from: value.physicalKey)
                    == task.persistentModelID
            }
            guard matching.count == 1, let physicalKey = matching.first?.physicalKey else {
                throw ConsolidationPlanningError.unavailableEvidence
            }
            try budget.check()
            let original = try ConsolidationOriginal(id: task.id, physicalKey: physicalKey,
                projectId: project.id, projectPhysicalKey: canonicalProjectKey(project),
                fields: TaskConsolidationRawFields.capture(task), revision: snapshot.revision,
                recordJSON: JSONSerialization.data(withJSONObject: snapshot.record, options: [.sortedKeys]))
            try budget.check()
            try charge.append(JSONEncoder().encode(original).count)
            return original
        }.sorted { $0.physicalKey.lexicographicallyPrecedes($1.physicalKey) }
        return originals
    }

    private func captureComments(_ context: ModelContext, id: UUID, charge: ConsolidationCaptureCharge,
                                 minimum: Int) throws -> [Comment] {
        let budget = charge.budget
        let comments = try fetchComments(context, id)
        var bytes = 0
        for comment in comments {
            try budget.check()
            bytes += comment.content.utf8.count + comment.authorName.utf8.count + 128
            try charge.checkAdditional(minimum + bytes)
        }
        return comments
    }

    private func canonicalProjectKey(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(project.persistentModelID)
    }

    private func operationEvents(selected: Set<UUID>, operationId: UUID?, context: ModelContext,
                                 charge: ConsolidationCaptureCharge) throws -> [TaskConsolidationEventValue] {
        let budget = charge.budget
        var operations: Set<UUID> = operationId.map { [$0] } ?? []
        let injected = try fetchEvents?(context)
        // A saved empty-store proof avoids one participant query per ordinary full-read body.
        if fetchEvents == nil {
            var descriptor = FetchDescriptor<TaskConsolidationEvent>()
            descriptor.includePendingChanges = false
            descriptor.fetchLimit = 1
            try budget.check()
            if try context.fetchCount(descriptor) == 0 { return [] }
            try budget.check()
        }
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
            operations.formUnion(try participantOperations(selected, in: context, charge: charge))
        }
        try charge.checkAdditional(operations.count * 128)
        var values: [TaskConsolidationEventValue] = []
        for id in operations.sorted(by: { $0.uuidString < $1.uuidString }) {
            try budget.check()
            let rows = try operationRows(id, injected: injected, context: context)
            for row in rows {
                try budget.check()
                try charge.checkAdditional(row.payloadJSON.utf8.count + row.originScopeId.utf8.count + 256)
                let value = try TaskConsolidationEventValue.capture(row)
                try budget.check()
                try charge.append(JSONEncoder().encode(value).count)
                values.append(value)
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

extension TaskConsolidationSavedCapture {
    private func participantOperations(_ selected: Set<UUID>, in context: ModelContext,
                                       charge: ConsolidationCaptureCharge) throws -> Set<UUID> {
        let budget = charge.budget
        var operations: Set<UUID> = []
        let ordered = selected.sorted { $0.uuidString < $1.uuidString }
        for start in stride(from: 0, to: ordered.count, by: 128) {
            try budget.check()
            let ids = Array(ordered[start..<min(start + 128, ordered.count)])
            // No nil member: absent candidate slots must never match a selected UUID.
            let candidateIds: [UUID?] = ids.map { Optional.some($0) }
            participantQuery(ids.count)
            let first = #Predicate<TaskConsolidationEvent> {
                ids.contains($0.survivorTaskId) || candidateIds.contains($0.candidate1)
                    || candidateIds.contains($0.candidate2)
            }
            let second = #Predicate<TaskConsolidationEvent> {
                candidateIds.contains($0.candidate3) || candidateIds.contains($0.candidate4)
                    || candidateIds.contains($0.candidate5)
            }
            var descriptor = FetchDescriptor<TaskConsolidationEvent>(predicate: #Predicate {
                first.evaluate($0) || second.evaluate($0)
            })
            descriptor.includePendingChanges = false
            guard try context.fetchCount(descriptor) <= budget.maximumBytes / 128 else {
                throw TaskLinkGraphError.capacityExceeded
            }
            for row in try context.fetch(descriptor) {
                try budget.check()
                operations.insert(row.operationId)
                try charge.checkAdditional(operations.count * 128)
            }
        }
        return operations
    }
}

private nonisolated struct ConsolidationCaptureRepresentation: Codable {
    let selection: [UUID]
    let originals: [ConsolidationOriginal]
    let events: [TaskConsolidationEventValue]
    let history: [ConsolidationHistoryProjection]
    let graphJSON: Data
}
