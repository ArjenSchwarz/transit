#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkReadCaptureTests {
    @Test func captureKeepsSavedGraphWhileAllDraftKindsRemainUnsaved() throws {
        let fixture = try TaskLinkReadFixture()
        let context = fixture.owner.context
        fixture.source.name = "draft source"
        fixture.target.name = "draft target"
        fixture.target.status = .abandoned
        fixture.comment.content = "draft comment"
        context.delete(fixture.edge)
        context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "duplicate", sourceTaskID: fixture.source.id,
                                         targetTaskID: fixture.target.id, createdAt: Date()))
        context.insert(TaskLinkRemovalEvidence(id: UUID(), edgeId: fixture.edge.id,
            kindRawValue: fixture.edge.kindRawValue, sourceTaskID: fixture.edge.sourceTaskID,
            targetTaskID: fixture.edge.targetTaskID, createdAt: fixture.edge.createdAt,
            occurrenceRevision: "draft evidence", removedAt: Date()))
        let view = try fixture.builder().capture(fixture.request())
        let graph = try #require(view.taskLinkGraph)
        #expect(graph.tasksById[fixture.source.id]?.first?.name == "source")
        #expect(graph.tasksById[fixture.target.id]?.first?.name == "target")
        #expect(graph.tasksById[fixture.target.id]?.first?.status == "done")
        #expect(graph.occurrences.map(\.id) == [fixture.edge.id])
        #expect(graph.removalEvidence.isEmpty)
        #expect(graph.assessment(for: fixture.source.id) == .unblocked)
        #expect(view.comments.first?.content == "saved comment")
        #expect(context.hasChanges)
    }

    @Test func foreignGraphClosureDoesNotExpandSelectedMembership() throws {
        let fixture = try TaskLinkReadFixture()
        let second = TaskLinkOccurrence(id: UUID(), kindRawValue: "dependency", sourceTaskID: fixture.source.id,
                                        targetTaskID: fixture.target.id, createdAt: Date())
        fixture.owner.context.insert(second)
        try fixture.owner.context.save()
        let view = try fixture.builder().capture(fixture.request())
        let graph = try #require(view.taskLinkGraph)
        #expect(view.tasks.map(\.id) == [fixture.source.id])
        #expect(Set(graph.tasks.map(\.id)) == Set([fixture.source.id, fixture.target.id]))
        #expect(graph.cyclicTasks == Set([fixture.source.id, fixture.target.id]))
        #expect(graph.assessment(for: fixture.source.id) == .invalid)
    }

    @Test func importedPhysicalMultiplicityIsNotCollapsedInCapture() throws {
        let fixture = try TaskLinkReadFixture()
        let copy = TaskLinkOccurrence(id: fixture.edge.id, kindRawValue: fixture.edge.kindRawValue,
                                     sourceTaskID: fixture.edge.sourceTaskID, targetTaskID: fixture.edge.targetTaskID,
                                     createdAt: fixture.edge.createdAt)
        fixture.owner.context.insert(copy)
        try fixture.owner.context.save()
        let view = try fixture.builder().capture(fixture.request())
        let graph = try #require(view.taskLinkGraph)
        #expect(graph.occurrencesById[fixture.edge.id]?.count == 2)
        #expect(Set(graph.occurrences.map(\.physicalKey)).count == 2)
        #expect(graph.assessment(for: fixture.source.id) == .invalid)
    }

    @Test(arguments: ["deadline", "capacity"])
    func originalGraphBudgetFailsEntireReadInsteadOfReturningEmpty(shape: String) throws {
        let fixture = try TaskLinkReadFixture()
        let budget = shape == "deadline"
            ? TaskLinkGraphBudget(deadline: .now.advanced(by: .seconds(-1)))
            : TaskLinkGraphBudget(maximumBytes: 1)
        #expect(throws: TaskLinkGraphError.self) {
            try fixture.builder().capture(fixture.request(budget: budget))
        }
    }

    @Test func laterSavedGraphChangesCannotEnrichFrozenCapture() throws {
        let fixture = try TaskLinkReadFixture()
        let view = try fixture.builder().capture(fixture.request())
        let original = try #require(view.taskLinkGraph)
        let peer = ModelContext(fixture.owner.container)
        peer.autosaveEnabled = false
        let id = fixture.target.id
        let matches = try peer.fetch(FetchDescriptor<TransitTask>(predicate: #Predicate { $0.id == id }))
        let target = try #require(matches.first)
        target.status = .abandoned
        try peer.save()
        #expect(original.assessment(for: fixture.source.id) == .unblocked)
        let fresh = try #require(try fixture.builder().capture(fixture.request()).taskLinkGraph)
        #expect(fresh.assessment(for: fixture.source.id) == .blocked)
        #expect(original.tasksById[id]?.first?.status == "done")
    }
}

@MainActor
private struct TaskLinkReadFixture {
    let owner: TestModelContainer
    let selected: Project
    let source: TransitTask
    let target: TransitTask
    let edge: TaskLinkOccurrence
    let comment: Transit.Comment

    init() throws {
        owner = try TestModelContainer()
        owner.context.autosaveEnabled = false
        selected = Project(name: "selected", description: "", gitRepo: nil, colorHex: "blue")
        let foreign = Project(name: "foreign", description: "", gitRepo: nil, colorHex: "green")
        source = TransitTask(name: "source", type: .feature, project: selected, displayID: .permanent(1))
        target = TransitTask(name: "target", type: .feature, project: foreign, displayID: .permanent(2))
        target.status = .done
        edge = TaskLinkOccurrence(id: UUID(), kindRawValue: "dependency", sourceTaskID: target.id,
                                  targetTaskID: source.id, createdAt: Date())
        comment = Transit.Comment(content: "saved comment", authorName: "fixture", isAgent: true, task: source)
        owner.context.insert(selected)
        owner.context.insert(foreign)
        owner.context.insert(source)
        owner.context.insert(target)
        owner.context.insert(edge)
        owner.context.insert(comment)
        try owner.context.save()
    }

    func builder() -> MCPReadCaptureBuilder {
        MCPReadCaptureBuilder(container: owner.container, fence: .actorOnlyTestFixture)
    }

    func request(budget: TaskLinkGraphBudget? = nil) -> ReadCaptureRequest {
        ReadCaptureRequest(projectSelectors: [.id(selected.id)], selection: .tasks(detail: .fullRecord),
                           completeness: .selectedRead, includeComments: true, taskLinkBudget: budget)
    }
}
#endif
