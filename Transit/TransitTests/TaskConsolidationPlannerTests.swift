import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskConsolidationPlannerTests {
    @Test func seededGroupPlanningMatchesIndependentClosureReference() throws {
        for seed in 1...25 {
            let fixture = try ConsolidationPlanningFixture(seed: seed, count: seed % 5 + 1)
            let before = fixture.originals
            let plan = try ConsolidationPlanner.plan(fixture.request, originals: before, graph: fixture.graph)
            let unfinished = before.dropFirst().filter { !["done", "abandoned"].contains($0.fields.statusRawValue) }
            #expect(Set(plan.changes.map(\.taskId)) == Set(unfinished.map(\.id)))
            #expect(plan.links.additions.count == fixture.request.candidateTaskIds.count)
            #expect(plan.links.removals.isEmpty && plan.originals == before && fixture.originals == before)
            for change in plan.changes {
                #expect(change.after.statusRawValue == "abandoned")
                #expect(change.before.description == change.after.description)
                #expect(change.before.metadataJSON == change.after.metadataJSON)
                #expect(change.before.lastStatusChangeDate == change.after.lastStatusChangeDate)
            }
        }
    }

    @Test func retainedCanonicalChainAndIncomingLinksStayUntouched() throws {
        let base = try ConsolidationPlanningFixture(seed: 2, count: 1)
        let candidate = base.originals[1].id, survivor = base.originals[0].id, middle = UUID(), incoming = UUID()
        let tasks = base.graph.tasks + [TaskLinkTaskValue(physicalKey: Data([9]), id: middle, name: "middle",
            status: "done"),
            TaskLinkTaskValue(physicalKey: Data([10]), id: incoming, name: "incoming", status: "idea")]
        let rows = [base.edge(candidate, middle), base.edge(middle, survivor), base.edge(incoming, candidate)]
        let graph = try TaskLinkGraph.project(tasks: tasks, occurrences: rows, removalEvidence: [],
            evaluationInstant: base.graph.evaluationInstant)
        let plan = try ConsolidationPlanner.plan(base.request, originals: base.originals, graph: graph)
        #expect(plan.links.isNoOp)
        #expect(Set(plan.retainedOccurrences.map(\.id)) == Set(rows.prefix(2).map(\.id)))
        #expect(graph.occurrences == rows)
    }

    @Test(arguments: ["repeat", "self", "bounds", "project", "physical", "status", "metadata", "canonical", "cycle"])
    func invalidGroupEvidenceRejectsWholePlan(fault: String) throws {
        let base = try ConsolidationPlanningFixture(seed: 1, count: 2)
        var request = base.request, originals = base.originals, rows: [TaskLinkOccurrenceValue] = []
        switch fault {
        case "repeat": request = base.requestWith(candidates: [originals[1].id, originals[1].id])
        case "self": request = base.requestWith(candidates: [originals[0].id])
        case "bounds": request = base.requestWith(candidates: [])
        case "physical": originals.append(originals[1])
        case "project": originals[1] = base.copy(originals[1], project: Data([42]))
        case "status": originals[1] = base.copy(originals[1], status: "future")
        case "metadata": originals[1] = base.copy(originals[1], metadata: "{invalid")
        case "canonical": rows = [base.edge(originals[1].id, originals[2].id)]
        default: rows = [base.edge(originals[1].id, originals[2].id), base.edge(originals[2].id, originals[1].id)]
        }
        let graph = try TaskLinkGraph.project(tasks: base.graph.tasks, occurrences: rows, removalEvidence: [],
            evaluationInstant: base.graph.evaluationInstant)
        #expect(throws: (any Error).self) { try ConsolidationPlanner.plan(request, originals: originals, graph: graph) }
    }

    @Test func mixedAccountingAndExplicitEditsAreBoundToOriginals() throws {
        let base = try ConsolidationPlanningFixture(seed: 1, count: 2)
        var request = base.request
        request.survivorEdits = ConsolidationEdits(description: .replace(nil), metadata: ["merged": "caller-authored"])
        request = ConsolidationRequest(survivorTaskId: request.survivorTaskId,
            candidateTaskIds: request.candidateTaskIds, reason: request.reason,
            preservation: Dictionary(uniqueKeysWithValues: request.candidateTaskIds.map {
                ($0.uuidString, ConsolidationDisposition(incorporated: [
                    .init(sourceDetail: "original metadata", survivorField: "metadata")],
                    retainedExplanation: "original description stays"))
            }), survivorEdits: request.survivorEdits)
        let plan = try ConsolidationPlanner.plan(request, originals: base.originals, graph: base.graph)
        let survivor = try #require(plan.changes.first { $0.taskId == base.originals[0].id })
        #expect(survivor.after.description == nil && survivor.before.description != nil)
        #expect(survivor.after.statusRawValue == survivor.before.statusRawValue)
        #expect(plan.reviewRevision.hasPrefix("p1:"))
        #expect(try ConsolidationPlanner.plan(request, originals: base.originals, graph: base.graph).reviewRevision
            == plan.reviewRevision)
        request.survivorEdits = ConsolidationEdits()
        #expect(throws: (any Error).self) {
            try ConsolidationPlanner.plan(request, originals: base.originals, graph: base.graph)
        }
    }

    @Test func seededApplyUndoRestoresOnlyAttributableFieldsAndGraph() throws {
        for seed in 1...12 {
            let fixture = try ConsolidationPlanningFixture(seed: seed, count: seed % 5 + 1)
            let plan = try ConsolidationPlanner.plan(fixture.request, originals: fixture.originals,
                graph: fixture.graph)
            let applied = try fixture.applied(plan)
            let undo = try ConsolidationPlanner.undo(events: [applied.event], operationId: applied.event.operationId,
                originals: applied.originals, graph: applied.graph)
            #expect(undo.links.additions.isEmpty && undo.links.removals.count == plan.links.additions.count)
            #expect(try ConsolidationHistoryProjection.make(events: [applied.event],
                operationId: applied.event.operationId, originals: applied.originals,
                graph: applied.graph).undoAvailable)
            for change in undo.changes {
                let original = try #require(fixture.originals.first { $0.id == change.taskId })
                #expect(change.after == original.fields)
            }
            let stale = applied.originals.enumerated().map { index, original in
                index == 0 ? fixture.copy(original, revision: "r1:" + String(repeating: "f", count: 64)) : original
            }
            #expect(throws: (any Error).self) {
                try ConsolidationPlanner.undo(events: [applied.event], operationId: applied.event.operationId,
                    originals: stale, graph: applied.graph)
            }
            #expect(try ConsolidationHistoryProjection.make(events: [applied.event],
                operationId: applied.event.operationId, originals: stale, graph: applied.graph).undoUnavailableReason
                == "REVISION_CONFLICT")
        }
    }
#if os(macOS)
    @Test func ownedServiceConsumesThePureRetainedPlan() async throws {
        let fixture = try TaskConsolidationCommitFixture()
        let context = fixture.base.owner.context
        let tasks = [fixture.base.target, fixture.base.source, fixture.extra]
        let originals = try tasks.map { task in
            let project = try #require(task.project)
            let snapshot = try MCPRecordSnapshot.task(task, in: context)
            return ConsolidationOriginal(id: task.id, physicalKey: try JSONEncoder().encode(task.persistentModelID),
                projectId: project.id, projectPhysicalKey: try JSONEncoder().encode(project.persistentModelID),
                fields: try TaskConsolidationRawFields.capture(task), revision: snapshot.revision,
                recordJSON: try JSONSerialization.data(withJSONObject: snapshot.record))
        }
        let request = ConsolidationRequest(survivorTaskId: tasks[0].id,
            candidateTaskIds: tasks.dropFirst().map(\.id), reason: "pure planned operation",
            preservation: Dictionary(uniqueKeysWithValues: tasks.dropFirst().map {
                ($0.id.uuidString, ConsolidationDisposition(retainedExplanation: "original retained"))
            }))
        let plan = try ConsolidationPlanner.plan(request, originals: originals,
            graph: TaskLinkService.graph(in: context, evaluationInstant: fixture.base.instant))
        let scope = try #require(fixture.coordinator.localScopeId)
        let review = try TaskConsolidationOwnedReview.make(plan: plan, scope: scope)
        let adapter = MCPConsolidationWriteAdapter(taskAllocator: fixture.base.allocator,
            milestoneAllocator: fixture.base.allocator,
            configuration: .init(originScopeId: scope, reviewSource: { _, _ in review },
                clock: { fixture.base.instant }))
        let result = await fixture.coordinator.execute(tool: "consolidate_tasks", arguments: [
            "reviewId": review.id.uuidString, "reviewRevision": review.revision,
            "preservationAcknowledged": true, "idempotencyKey": "pure-planned"], batchPolicy: adapter.policy())
        #expect(try fixture.base.decode(result)["outcome"] as? String == "committed")
        #expect(fixture.observation.commitSaves == 1)
    }
#endif

}

@MainActor struct ConsolidationPlanningFixture {
    let originals: [ConsolidationOriginal]
    let request: ConsolidationRequest
    let graph: TaskLinkGraphView

    init(seed: Int, count: Int) throws {
        let project = UUID(), keys = (0...count).map { Data([UInt8($0 + 1)]) }
        let states = ["idea", "planning", "done", "abandoned", "in-progress"]
        originals = try keys.enumerated().map { index, key in
            ConsolidationOriginal(id: UUID(), physicalKey: key, projectId: project, projectPhysicalKey: Data([0]),
                fields: TaskConsolidationRawFields(description: "original \(seed)-\(index)",
                    metadataJSON: "{ \"seed\" : \"\(seed)\" }", statusRawValue: states[(seed + index) % states.count],
                    lastStatusChangeDate: try TaskConsolidationRawFields.exactDate(
                        Date(timeIntervalSinceReferenceDate: 10)),
                    completionDate: index == 0 ? "0" : nil),
                revision: "r1:" + String(repeating: "a", count: 64), recordJSON: Data("{}".utf8))
        }
        request = ConsolidationRequest(survivorTaskId: originals[0].id,
            candidateTaskIds: originals.dropFirst().map(\.id),
            reason: "caller reason", preservation: Dictionary(uniqueKeysWithValues: originals.dropFirst().map {
                ($0.id.uuidString, ConsolidationDisposition(retainedExplanation: "all originals retained"))
            }))
        graph = try TaskLinkGraph.project(tasks: originals.map {
            TaskLinkTaskValue(physicalKey: $0.physicalKey, id: $0.id, name: "original",
                status: $0.fields.statusRawValue)
        }, occurrences: [], removalEvidence: [], evaluationInstant: Date(timeIntervalSinceReferenceDate: 20))
    }

    func edge(_ source: UUID, _ target: UUID) -> TaskLinkOccurrenceValue {
        let id = UUID()
        return TaskLinkOccurrenceValue(physicalKey: Data(id.uuidString.utf8), id: id, kind: "duplicate",
            source: source, target: target, createdAt: graph.evaluationInstant)
    }

    func requestWith(candidates: [UUID]) -> ConsolidationRequest {
        ConsolidationRequest(survivorTaskId: request.survivorTaskId, candidateTaskIds: candidates,
            reason: request.reason, preservation: request.preservation)
    }

    func copy(_ original: ConsolidationOriginal, project: Data? = nil, status: String? = nil,
              metadata: String? = nil, revision: String? = nil) -> ConsolidationOriginal {
        ConsolidationOriginal(id: original.id, physicalKey: original.physicalKey, projectId: original.projectId,
            projectPhysicalKey: project ?? original.projectPhysicalKey,
            fields: TaskConsolidationRawFields(description: original.fields.description,
                metadataJSON: metadata ?? original.fields.metadataJSON,
                    statusRawValue: status ?? original.fields.statusRawValue,
                lastStatusChangeDate: original.fields.lastStatusChangeDate,
                    completionDate: original.fields.completionDate),
            revision: revision ?? original.revision, recordJSON: original.recordJSON)
    }

    struct Applied {
        let event: TaskConsolidationEventValue
        let originals: [ConsolidationOriginal]
        let graph: TaskLinkGraphView
    }

    func applied(_ plan: ConsolidationPlan) throws -> Applied {
        let changes = plan.changes.map { change in
            TaskConsolidationReviewedTaskChange(taskId: change.taskId, before: change.before,
                after: TaskConsolidationRawFields(description: change.after.description,
                    metadataJSON: change.after.metadataJSON, statusRawValue: change.after.statusRawValue,
                    lastStatusChangeDate: "4034000000000000", completionDate: "4034000000000000"))
        }
        let after = originals.map { original in
            ConsolidationOriginal(id: original.id, physicalKey: original.physicalKey, projectId: original.projectId,
                projectPhysicalKey: original.projectPhysicalKey,
                fields: changes.first { $0.taskId == original.id }?.after ?? original.fields,
                revision: "r1:" + String(repeating: "b", count: 64), recordJSON: original.recordJSON)
        }
        let rows = plan.links.additions.map { edge($0.relation.source, $0.relation.target) }
        let payload = TaskConsolidationPayload(operationId: UUID(), kind: "apply",
            survivorTaskId: request.survivorTaskId,
            candidateTaskIds: request.candidateTaskIds, reason: request.reason,
            preservationJSON: try String(data: JSONEncoder().encode(request.preservation), encoding: .utf8)!,
            changes: changes.map(\.delta),
            appliedRevisions: Dictionary(uniqueKeysWithValues: after.map { ($0.id.uuidString, $0.revision) }),
            createdOccurrences: try rows.map { .init(id: $0.id, kind: $0.kind, source: $0.source, target: $0.target,
                createdAt: try TaskConsolidationRawFields.exactDate($0.createdAt),
                revision: try TaskLinkGraph.occurrenceRevision($0)) },
            retainedOccurrences: [], requestKey: "generated", reviewId: UUID(), reviewRevision: plan.reviewRevision)
        let event = TaskConsolidationEventValue(physicalKey: Data(payload.operationId.uuidString.utf8),
            id: payload.operationId,
            operationId: payload.operationId, kind: "apply", createdAt: "4034000000000000", originScopeId: "fixture",
            survivorTaskId: payload.survivorTaskId, candidateSlots: request.candidateTaskIds.map(Optional.some)
                + Array(repeating: nil, count: 5 - request.candidateTaskIds.count),
            payloadJSON: try TaskConsolidationHistoryCodec.encode(payload))
        let savedGraph = try TaskLinkGraph.project(tasks: after.map {
            .init(physicalKey: $0.physicalKey, id: $0.id, name: "after", status: $0.fields.statusRawValue)
        }, occurrences: rows, removalEvidence: [], evaluationInstant: graph.evaluationInstant)
        return Applied(event: event, originals: after, graph: savedGraph)
    }
}
