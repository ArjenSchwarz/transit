import Foundation
import Testing
@testable import Transit

@MainActor
struct TaskLinkGraphTests {
    @Test func inverseAndAssociationNormalization() {
        let source = UUID(), target = UUID()
        #expect(TaskLinkType.blocks.normalized(source: source, target: target)
                == TaskLinkType.blockedBy.normalized(source: target, target: source))
        #expect(TaskLinkType.relatesTo.normalized(source: source, target: target)
                == TaskLinkType.relatesTo.normalized(source: target, target: source))
    }

    @Test(arguments: ["done", "abandoned", "in-progress", "future-status"])
    func directSavedBlockerStatus(status: String) throws {
        let source = task(1, status: status), target = task(2)
        let view = try project([source, target], [edge(1, source.id, target.id)])
        let expected: TaskLinkBlockerAssessment = status == "done" ? .unblocked
            : status == "future-status" ? .invalid : .blocked
        #expect(view.assessment(for: target.id) == expected)
    }

    @Test func dependencyCycleIsInvalidEvenWhenDone() throws {
        let first = task(1, status: "done"), second = task(2, status: "done")
        let view = try project([first, second], [edge(1, first.id, second.id), edge(2, second.id, first.id)])
        #expect(view.cyclicTasks == Set([first.id, second.id]))
        #expect(view.assessment(for: first.id) == .invalid)
        #expect(view.assessment(for: second.id) == .invalid)
    }

    @Test func repeatedLogicalRowsCannotCertifyUnblocked() throws {
        let first = task(1, status: "done"), second = task(2)
        let view = try project([first, second], [edge(1, first.id, second.id), edge(2, first.id, second.id)])
        #expect(view.assessment(for: second.id) == .invalid)
        #expect(view.diagnostics.filter { $0.code == "equivalent_occurrences" }.count == 2)
        #expect(view.incidence[second.id]?.count == 2)
    }

    @Test func doneBlockerDoesNotPropagateItsBadAncestry() throws {
        let blocker = task(1, status: "done"), target = task(2)
        let view = try project([blocker, target], [edge(1, UUID(), blocker.id), edge(2, blocker.id, target.id)])
        #expect(view.assessment(for: blocker.id) == .invalid)
        #expect(view.assessment(for: target.id) == .unblocked)
    }

    @Test func physicalIdentityCollisionAndMissingEndpointRemainVisible() throws {
        let source = task(1)
        let repeated = TaskLinkTaskValue(physicalKey: Data([9]), id: source.id, name: "collision", status: "done")
        let row = edge(1, source.id, UUID())
        let view = try project([source, repeated], [row])
        #expect(view.tasksById[source.id]?.count == 2)
        #expect(Set(view.diagnostics.map(\.code)) == ["ambiguous_endpoint", "missing_endpoint"])
        #expect(view.assessment(for: source.id) == .invalid)
    }

    private func task(_ number: UInt8, status: String = "idea") -> TaskLinkTaskValue {
        TaskLinkTaskValue(physicalKey: Data([number]), id: UUID(), name: "task", status: status)
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
