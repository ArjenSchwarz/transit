import Foundation
import Testing
@testable import Transit

@MainActor
struct TaskLinkPlanTests {
    @Test func additionCannotCloseDependencyCycle() throws {
        let source = task(1), target = task(2)
        let graph = try project([source, target], [edge(1, target.id, source.id)])
        #expect(throws: TaskLinkGraphError.self) {
            try TaskLinkPlan.validate(delta: [.add(type: .blocks, target: target.id)], source: source.id,
                                      preconditions: [target.id: "current"],
                                      revisions: [target.id: "current"], savedGraph: graph)
        }
    }

    @Test func exactRemovalCanIncrementallyRepairCycle() throws {
        let source = task(1), target = task(2), row = edge(1, source.id, target.id)
        let graph = try project([source, target], [row, edge(2, target.id, source.id)])
        let plan = try TaskLinkPlan.validate(delta: [.remove(edgeId: row.id,
                                                           occurrenceRevision: TaskLinkGraph.occurrenceRevision(row))],
            source: source.id, preconditions: [target.id: "current"],
                                      revisions: [target.id: "current"], savedGraph: graph)
        #expect(plan.removals == [row])
        #expect(plan.additions.isEmpty)
    }

    @Test func missingEndpointRemovalDoesNotInventGuard() throws {
        let source = task(1), row = edge(1, source.id, UUID())
        let graph = try project([source], [row])
        let plan = try TaskLinkPlan.validate(delta: [.remove(edgeId: row.id,
                                                           occurrenceRevision: TaskLinkGraph.occurrenceRevision(row))],
            source: source.id, preconditions: [:], revisions: [:], savedGraph: graph)
        #expect(plan.affectedEndpoints.isEmpty)
        #expect(plan.removals == [row])
    }

    @Test func alreadyPresentAddIsNoOpWithoutExtraEndpointGuard() throws {
        let source = task(1), target = task(2), row = edge(1, source.id, target.id)
        let graph = try project([source, target], [row])
        let plan = try TaskLinkPlan.validate(delta: [.add(type: .blocks, target: target.id)], source: source.id,
                                            preconditions: [:], revisions: [:], savedGraph: graph)
        #expect(plan.isNoOp)
        #expect(throws: TaskLinkGraphError.self) {
            try TaskLinkPlan.validate(delta: [.add(type: .blocks, target: target.id)], source: source.id,
                                      preconditions: [target.id: "extra"],
                                      revisions: [target.id: "extra"], savedGraph: graph)
        }
    }

    @Test func removeAndAddSameRelationRejectsEvenIfAddWasNoOp() throws {
        let source = task(1), target = task(2), row = edge(1, source.id, target.id)
        let graph = try project([source, target], [row])
        #expect(throws: TaskLinkGraphError.self) {
            try TaskLinkPlan.validate(delta: [.remove(edgeId: row.id,
                                                      occurrenceRevision: TaskLinkGraph.occurrenceRevision(row)),
                                             .add(type: .blocks, target: target.id)], source: source.id,
                                      preconditions: [target.id: "current"],
                                      revisions: [target.id: "current"], savedGraph: graph)
        }
    }

    @Test func physicalSelectorCollisionNeverChoosesFirst() throws {
        let source = task(1), target = task(2), row = edge(1, source.id, target.id)
        let collision = TaskLinkOccurrenceValue(physicalKey: Data([9]), id: row.id, kind: row.kind,
                                               source: row.source, target: row.target, createdAt: row.createdAt)
        let graph = try project([source, target], [row, collision])
        #expect(throws: TaskLinkGraphError.self) {
            try TaskLinkPlan.validate(delta: [.remove(edgeId: row.id,
                                                      occurrenceRevision: TaskLinkGraph.occurrenceRevision(row))],
                source: source.id, preconditions: [target.id: "current"],
                                      revisions: [target.id: "current"], savedGraph: graph)
        }
    }

    private func task(_ number: UInt8) -> TaskLinkTaskValue {
        TaskLinkTaskValue(physicalKey: Data([number]), id: UUID(), name: "task", status: "idea")
    }

    private func edge(_ number: UInt8, _ source: UUID, _ target: UUID) -> TaskLinkOccurrenceValue {
        TaskLinkOccurrenceValue(physicalKey: Data([number]), id: UUID(), kind: "dependency",
                                source: source, target: target, createdAt: Date(timeIntervalSince1970: 100))
    }

    private func project(_ tasks: [TaskLinkTaskValue], _ edges: [TaskLinkOccurrenceValue]) throws -> TaskLinkGraphView {
        try TaskLinkGraph.project(tasks: tasks, occurrences: edges, removalEvidence: [],
                                  evaluationInstant: Date(timeIntervalSince1970: 200))
    }
}
