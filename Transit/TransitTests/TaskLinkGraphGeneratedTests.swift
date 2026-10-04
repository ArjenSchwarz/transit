import Foundation
import Testing
@testable import Transit

@MainActor
struct TaskLinkGraphGeneratedTests {
    @Test(arguments: Array(UInt64(1)...8))
    func generatedSCCMatchesIndependentReachability(seed: UInt64) throws {
        var state = seed
        let tasks = (0..<6).map { index in
            TaskLinkTaskValue(physicalKey: Data([UInt8(index)]), id: UUID(), name: "generated", status: "done")
        }
        var rows: [TaskLinkOccurrenceValue] = []
        for source in tasks.indices {
            for target in tasks.indices where target != source {
                state = state &* 6_364_136_223_846_793_005 &+ 1
                if state >> 61 < 2 {
                    rows.append(edge(UInt8(rows.count), kind: "dependency", tasks[source].id, tasks[target].id))
                }
            }
        }
        let view = try project(tasks, rows)
        var expected: Set<UUID> = []
        for task in tasks {
            for other in tasks where other.id != task.id {
                if reaches(task.id, other.id, rows), reaches(other.id, task.id, rows) {
                    expected.insert(task.id)
                }
            }
        }
        #expect(view.cyclicTasks == expected)
        let reversed = try project(tasks.reversed(), rows.reversed())
        #expect(reversed.cyclicTasks == view.cyclicTasks)
        #expect(reversed.blockers == view.blockers)
        #expect(reversed.diagnostics == view.diagnostics)
    }

    @Test(arguments: ["chain", "cardinality", "cycle"])
    func duplicatePathsPreserveOriginalAndReportFaults(shape: String) throws {
        let tasks = (0..<3).map { index in
            TaskLinkTaskValue(physicalKey: Data([UInt8(index)]), id: UUID(), name: "duplicate", status: "abandoned")
        }
        var rows = [edge(1, kind: "duplicate", tasks[0].id, tasks[1].id)]
        if shape == "cardinality" { rows.append(edge(2, kind: "duplicate", tasks[0].id, tasks[2].id)) } else {
            rows.append(edge(2, kind: "duplicate", tasks[1].id, shape == "cycle" ? tasks[0].id : tasks[2].id))
        }
        let view = try project(tasks, rows)
        let result = try TaskLinkGraph.duplicateResolution(for: tasks[0].id, in: view)
        #expect(result.path.first == tasks[0].id)
        if shape == "chain" {
            #expect(result.path == tasks.map(\.id))
            #expect(result.canonical == tasks[2].id)
        } else {
            #expect(result.canonical == nil)
            #expect(result.diagnostic == (shape == "cycle" ? "duplicate_cycle" : "duplicate_cardinality"))
        }
        #expect(view.occurrences == rows)
        #expect(view.assessment(for: tasks[0].id) == .unblocked)
    }

    @Test func evidenceExpiryChangesAssessmentWithoutChangingActiveIncidence() throws {
        let tasks = [TaskLinkTaskValue(physicalKey: Data([1]), id: UUID(), name: "blocker", status: "done"),
                     TaskLinkTaskValue(physicalKey: Data([2]), id: UUID(), name: "target", status: "idea")]
        let row = edge(1, kind: "dependency", tasks[0].id, tasks[1].id)
        let removed = Date(timeIntervalSince1970: 200)
        let evidence = TaskLinkRemovalValue(physicalKey: Data([3]), id: UUID(), edgeId: row.id,
            kind: row.kind, source: row.source, target: row.target, createdAt: row.createdAt,
            occurrenceRevision: try TaskLinkGraph.occurrenceRevision(row), removedAt: removed)
        let fresh = try TaskLinkGraph.project(tasks: tasks, occurrences: [row], removalEvidence: [evidence],
                                             evaluationInstant: removed)
        let expired = try TaskLinkGraph.project(tasks: tasks, occurrences: [row], removalEvidence: [evidence],
            evaluationInstant: removed.addingTimeInterval(TaskLinkGraph.evidenceLifetime))
        #expect(fresh.assessment(for: tasks[1].id) == .invalid)
        #expect(expired.assessment(for: tasks[1].id) == .unblocked)
        #expect(fresh.occurrences == expired.occurrences)
        #expect(fresh.incidence == expired.incidence)
        #expect(expired.recognizedRemovals.isEmpty)
    }

    @Test func graphBudgetFailsWholeProjection() {
        #expect(throws: TaskLinkGraphError.self) {
            try TaskLinkGraph.project(tasks: [], occurrences: [], removalEvidence: [], evaluationInstant: Date(),
                                     budget: TaskLinkGraphBudget(deadline: .now.advanced(by: .seconds(-1))))
        }
        #expect(throws: TaskLinkGraphError.self) {
            try TaskLinkGraph.project(tasks: [TaskLinkTaskValue(physicalKey: Data([1]), id: UUID(),
                                                               name: "capacity", status: "idea")],
                occurrences: [], removalEvidence: [], evaluationInstant: Date(),
                budget: TaskLinkGraphBudget(maximumBytes: 1))
        }
    }

    @Test func repeatedOccurrenceUUIDCannotIssueActionableIdentity() throws {
        let source = TaskLinkTaskValue(physicalKey: Data([1]), id: UUID(),
                                       name: "source", status: "done")
        let target = TaskLinkTaskValue(physicalKey: Data([2]), id: UUID(), name: "target", status: "idea")
        let original = edge(1, kind: "dependency", source.id, target.id)
        let copy = TaskLinkOccurrenceValue(physicalKey: Data([9]), id: original.id, kind: original.kind,
                                          source: original.source, target: original.target,
                                          createdAt: original.createdAt)
        let view = try project([source, target], [original, copy])
        #expect(view.occurrencesById[original.id]?.count == 2)
        #expect(view.invalidOccurrences == Set([original.physicalKey, copy.physicalKey]))
        #expect(view.assessment(for: target.id) == .invalid)
    }

    /// Independent reachability reference uses breadth-first traversal, not SCC implementation.
    private func reaches(_ source: UUID, _ target: UUID, _ edges: [TaskLinkOccurrenceValue]) -> Bool {
        var queue = [source], seen: Set<UUID> = [source], offset = 0
        while offset < queue.count {
            let current = queue[offset]; offset += 1
            for edge in edges where edge.source == current {
                if edge.target == target { return true }
                if seen.insert(edge.target).inserted { queue.append(edge.target) }
            }
        }
        return false
    }

    private func edge(_ number: UInt8, kind: String, _ source: UUID, _ target: UUID) -> TaskLinkOccurrenceValue {
        TaskLinkOccurrenceValue(physicalKey: Data([number]), id: UUID(), kind: kind,
                                source: source, target: target, createdAt: Date(timeIntervalSince1970: 100))
    }

    private func project(_ tasks: [TaskLinkTaskValue], _ edges: [TaskLinkOccurrenceValue]) throws -> TaskLinkGraphView {
        try TaskLinkGraph.project(tasks: tasks, occurrences: edges, removalEvidence: [],
                                  evaluationInstant: Date(timeIntervalSince1970: 200))
    }
}
