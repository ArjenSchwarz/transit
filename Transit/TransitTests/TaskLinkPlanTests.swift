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

    @Test func duplicateCardinalityIsValidatedOnCompleteProposedResult() throws {
        let source = task(1), old = task(2), new = task(3)
        let original = TaskLinkOccurrenceValue(physicalKey: Data([1]), id: UUID(), kind: "duplicate",
                                              source: source.id, target: old.id,
                                              createdAt: Date(timeIntervalSince1970: 100))
        let graph = try project([source, old, new], [original])
        #expect(throws: TaskLinkGraphError.self) {
            try TaskLinkPlan.validate(delta: [.add(type: .duplicateOf, target: new.id)], source: source.id,
                preconditions: [new.id: "current"], revisions: [new.id: "current"], savedGraph: graph)
        }
    }

    @Test func duplicateRetargetRemovesOnlyExactOldOccurrence() throws {
        let source = task(1), old = task(2), new = task(3)
        let original = TaskLinkOccurrenceValue(physicalKey: Data([1]), id: UUID(), kind: "duplicate",
                                              source: source.id, target: old.id,
                                              createdAt: Date(timeIntervalSince1970: 100))
        let graph = try project([source, old, new], [original])
        let guards = [old.id: "old", new.id: "new"]
        let plan = try TaskLinkPlan.validate(delta: [
            .remove(edgeId: original.id, occurrenceRevision: TaskLinkGraph.occurrenceRevision(original)),
            .add(type: .duplicateOf, target: new.id)
        ], source: source.id, preconditions: guards, revisions: guards, savedGraph: graph)
        #expect(plan.removals == [original])
        let newRelation = TaskLinkType.duplicateOf.normalized(source: source.id, target: new.id)
        #expect(plan.additions.map(\.relation) == [newRelation])
        #expect(plan.affectedEndpoints == Set([old.id, new.id]))
    }

    @Test(arguments: [false, true])
    func exactRemovedSelectorNoOpRequiresUnexpiredEvidence(expired: Bool) throws {
        let source = task(1), row = edge(1, source.id, UUID())
        let revision = try TaskLinkGraph.occurrenceRevision(row)
        let evidence = TaskLinkRemovalValue(physicalKey: Data([9]), id: UUID(), edgeId: row.id,
            kind: row.kind, source: row.source, target: row.target, createdAt: row.createdAt,
            occurrenceRevision: revision, removedAt: Date(timeIntervalSince1970: 150))
        let graph = try TaskLinkGraph.project(tasks: [source], occurrences: [], removalEvidence: [evidence],
            evaluationInstant: Date(timeIntervalSince1970: expired ? 150 + TaskLinkGraph.evidenceLifetime : 200))
        if expired {
            #expect(throws: TaskLinkGraphError.self) {
                try TaskLinkPlan.validate(delta: [.remove(edgeId: row.id, occurrenceRevision: revision)],
                    source: source.id, preconditions: [:], revisions: [:], savedGraph: graph)
            }
        } else {
            let plan = try TaskLinkPlan.validate(delta: [.remove(edgeId: row.id, occurrenceRevision: revision)],
                source: source.id, preconditions: [:], revisions: [:], savedGraph: graph)
            #expect(plan.isNoOp)
            #expect(plan.affectedEndpoints.isEmpty)
        }
    }

    @Test func removedEvidenceAndSameLogicalReAddRejectsInOneRequest() throws {
        let source = task(1), target = task(2), row = edge(1, source.id, target.id)
        let revision = try TaskLinkGraph.occurrenceRevision(row)
        let evidence = TaskLinkRemovalValue(physicalKey: Data([9]), id: UUID(), edgeId: row.id,
            kind: row.kind, source: row.source, target: row.target, createdAt: row.createdAt,
            occurrenceRevision: revision, removedAt: Date(timeIntervalSince1970: 150))
        let graph = try TaskLinkGraph.project(tasks: [source, target], occurrences: [], removalEvidence: [evidence],
                                             evaluationInstant: Date(timeIntervalSince1970: 200))
        #expect(throws: TaskLinkGraphError.self) {
            try TaskLinkPlan.validate(delta: [.remove(edgeId: row.id, occurrenceRevision: revision),
                                             .add(type: .blocks, target: target.id)], source: source.id,
                preconditions: [target.id: "current"], revisions: [target.id: "current"], savedGraph: graph)
        }
    }

    @Test(arguments: ["missing", "stale", "extra"])
    func endpointGuardsMustExactlyMatchAffectedSavedEndpoints(shape: String) throws {
        let source = task(1), target = task(2), extra = task(3)
        let graph = try project([source, target, extra], [])
        var guards: [UUID: String] = shape == "missing" ? [:] : [target.id: "stale"]
        if shape == "extra" { guards = [target.id: "current", extra.id: "extra"] }
        #expect(throws: TaskLinkGraphError.self) {
            try TaskLinkPlan.validate(delta: [.add(type: .blocks, target: target.id)], source: source.id,
                preconditions: guards, revisions: [target.id: "current", extra.id: "extra"], savedGraph: graph)
        }
    }

    @Test func exactSelfLinkRepairNeedsNoDuplicateSourceEndpointGuard() throws {
        let source = task(1), row = edge(1, source.id, source.id)
        let graph = try project([source], [row])
        let plan = try TaskLinkPlan.validate(delta: [.remove(edgeId: row.id,
                                                           occurrenceRevision: TaskLinkGraph.occurrenceRevision(row))],
            source: source.id, preconditions: [:], revisions: [:], savedGraph: graph)
        #expect(plan.removals == [row])
        #expect(plan.affectedEndpoints.isEmpty)
    }

    @Test(arguments: ["self", "unknown"])
    func exactImportedRepairEvidenceRemainsRecognizable(shape: String) throws {
        let source = task(1)
        let row = TaskLinkOccurrenceValue(physicalKey: Data([1]), id: UUID(),
            kind: shape == "unknown" ? "future-kind" : "dependency", source: source.id,
            target: shape == "self" ? source.id : UUID(), createdAt: Date(timeIntervalSince1970: 100))
        let revision = try TaskLinkGraph.occurrenceRevision(row)
        let evidence = TaskLinkRemovalValue(physicalKey: Data([9]), id: UUID(), edgeId: row.id,
            kind: row.kind, source: row.source, target: row.target, createdAt: row.createdAt,
            occurrenceRevision: revision, removedAt: Date(timeIntervalSince1970: 150))
        let graph = try TaskLinkGraph.project(tasks: [source], occurrences: [], removalEvidence: [evidence],
                                             evaluationInstant: Date(timeIntervalSince1970: 200))
        let plan = try TaskLinkPlan.validate(delta: [.remove(edgeId: row.id, occurrenceRevision: revision)],
            source: source.id, preconditions: [:], revisions: [:], savedGraph: graph)
        #expect(plan.isNoOp)
        #expect(graph.recognizedRemovals[row.id]?.count == 1)
        #expect(graph.diagnostics.isEmpty)
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
