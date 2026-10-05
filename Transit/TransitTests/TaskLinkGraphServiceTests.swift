import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkGraphServiceTests {
    @Test func savedDetailIgnoresUnsavedLabelAndGraphDrafts() throws {
        let owner = try TestModelContainer()
        let project = Project(name: "saved graph", description: "", gitRepo: nil, colorHex: "#000000")
        let source = TransitTask(name: "saved source", type: .feature, project: project, displayID: .provisional)
        let target = TransitTask(name: "saved target", type: .feature, project: project, displayID: .provisional)
        target.status = .done
        let row = TaskLinkOccurrence(id: UUID(), kindRawValue: "dependency", sourceTaskID: target.id,
                                     targetTaskID: source.id, createdAt: Date())
        owner.context.insert(project)
        owner.context.insert(source)
        owner.context.insert(target)
        owner.context.insert(row)
        try owner.context.save()
        source.name = "draft source"
        target.name = "draft target"
        owner.context.delete(row)
        let detail = try TaskLinkService(container: owner.container).savedDetail(for: source.id)
        #expect(detail.source.name == "saved source")
        #expect(detail.graph.tasksById[target.id]?.first?.name == "saved target")
        #expect(detail.graph.occurrences.map(\.id) == [row.id])
        #expect(detail.graph.assessment(for: source.id) == .unblocked)
        #expect(source.name == "draft source")
        #expect(owner.context.hasChanges)
    }

    @Test func unsavedSourceIsUnavailableInsteadOfEmptyGraph() throws {
        let owner = try TestModelContainer()
        let project = Project(name: "private", description: "", gitRepo: nil, colorHex: "#000000")
        owner.context.insert(project)
        try owner.context.save()
        let source = TransitTask(name: "not saved", type: .feature, project: project, displayID: .provisional)
        owner.context.insert(source)
        #expect(throws: TaskLinkGraphError.self) {
            try TaskLinkService(container: owner.container).savedDetail(for: source.id)
        }
        #expect(owner.context.hasChanges)
    }
}
