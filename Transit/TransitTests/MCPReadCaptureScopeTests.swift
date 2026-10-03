#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadCaptureScopeTests {
    @Test func scopedCaptureKeepsCanonicalSelectedBodiesAndMinimalForeignIdentity() throws {
        let fixture = try TestModelContainer()
        let selected = Project(name: "Selected", description: "", gitRepo: nil, colorHex: "blue")
        let foreign = Project(name: "Foreign", description: "", gitRepo: nil, colorHex: "red")
        let task = TransitTask(name: "Selected task", type: .feature, project: selected, displayID: .permanent(1))
        let unrelated = TransitTask(name: "Foreign identity", type: .bug, project: foreign, displayID: .permanent(2))
        unrelated.id = task.id
        unrelated.taskDescription = "Unrelated full body must not be retained"
        unrelated.metadata = ["secret": "Unrelated metadata"]
        let ownComment = Comment(content: "Own", authorName: "A", isAgent: true, task: task)
        let foreignComment = Comment(content: "UUID canonical coverage", authorName: "B",
                                     isAgent: true, task: unrelated)
        fixture.context.insert(selected)
        fixture.context.insert(foreign)
        fixture.context.insert(task)
        fixture.context.insert(unrelated)
        fixture.context.insert(ownComment)
        fixture.context.insert(foreignComment)
        try fixture.context.save()
        let revision = try MCPRecordSnapshot.task(task, in: fixture.context).revision
        let view = try MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture)
            .capture(ReadCaptureRequest(projectSelectors: [.id(selected.id)], selection: .portfolio,
                                        completeness: .completePortfolio, includeComments: false))
        let selectedKey = try #require(view.projects.first { $0.id == selected.id }?.physicalKey)
        #expect(view.captureScope == .projects([selectedKey]))
        let captured = try #require(view.tasks.first { $0.projectKey == selectedKey })
        #expect(captured.revision == revision)
        #expect(captured.fullRecordWithoutCommentsJSON != nil)
        #expect(captured.commentKeys.count == 1)
        #expect(view.comments.count == 2)
        let closure = try #require(view.tasks.first { $0.projectKey != selectedKey })
        #expect(closure.revision == nil && closure.fullRecordWithoutCommentsJSON == nil)
        #expect(closure.requestedCommentRecordsJSON == nil)
        #expect(closure.taskDescription == nil && closure.metadata.isEmpty && closure.metadataJSON == nil)
        let identity = try #require(JSONSerialization.jsonObject(with: closure.selectedRecordJSON) as? [String: Any])
        #expect(identity["description"] == nil && identity["metadata"] == nil && identity["comments"] == nil)
    }

    @Test func scopedForeignMilestoneKeepsClosureWithoutCanonicalDateSerialization() throws {
        let fixture = try TestModelContainer()
        let selected = Project(name: "Selected", description: "", gitRepo: nil, colorHex: "blue")
        let foreign = Project(name: "Foreign", description: "", gitRepo: nil, colorHex: "red")
        let milestone = Milestone(name: "Foreign milestone", project: foreign, displayID: .permanent(9))
        let task = TransitTask(name: "Selected task", type: .feature, project: selected, displayID: .permanent(1))
        task.milestone = milestone
        fixture.context.insert(selected)
        fixture.context.insert(foreign)
        fixture.context.insert(milestone)
        fixture.context.insert(task)
        try fixture.context.save()
        let revision = try MCPRecordSnapshot.task(task, in: fixture.context).revision
        let builder = MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture,
            fetchMilestones: { context in
                let values = try context.fetch(FetchDescriptor<Milestone>())
                let corrupt = try #require(values.first)
                corrupt.creationDate = Date(timeIntervalSinceReferenceDate: .nan)
                #expect(throws: (any Error).self) { try MCPRecordSnapshot.milestone(corrupt) }
                return values
            })
        let view = try builder.capture(ReadCaptureRequest(projectSelectors: [.id(selected.id)], selection: .portfolio,
                                                         completeness: .completePortfolio, includeComments: false))
        let captured = try #require(view.tasks.first { $0.id == task.id })
        let closure = try #require(view.milestones.first { $0.id == milestone.id })
        let foreignKey = try #require(view.projects.first { $0.id == foreign.id }?.physicalKey)
        #expect(captured.revision == revision && captured.fullRecordWithoutCommentsJSON != nil)
        #expect(captured.milestoneKey == closure.physicalKey)
        #expect(closure.projectKey == foreignKey && closure.taskKeys == [captured.physicalKey])
        #expect(closure.permanentDisplayId == 9 && closure.name == "Foreign milestone")
        #expect(closure.rawStatus == "open" && closure.effectiveStatus == "open")
        #expect(closure.creationDate.timeIntervalSinceReferenceDate.isNaN)
        let record = try #require(JSONSerialization.jsonObject(with: closure.selectedRecordJSON) as? [String: String])
        #expect(record == ["milestoneId": milestone.id.uuidString, "name": "Foreign milestone"])
        try MCPReadCaptureValidation.validateReusableCapture(view)
        #expect(throws: MCPReadCaptureError.serializationFailure) {
            try builder.capture(ReadCaptureRequest(projectSelectors: nil, selection: .portfolio,
                                                   completeness: .completePortfolio, includeComments: false))
        }
    }

    @Test func volumeCaptureReportsPhysicalAndEncodingCostsSeparately() throws {
        let setupStart = ContinuousClock.now
        let fixture = try TestModelContainer()
        let project = Project(name: "Volume", description: "", gitRepo: nil, colorHex: "blue")
        fixture.context.insert(project)
        var tasks: [TransitTask] = []
        for number in 0..<2_375 {
            let task = TransitTask(name: "Task \(number)", type: .feature, project: project,
                                   displayID: .permanent(number + 1))
            fixture.context.insert(task)
            fixture.context.insert(Comment(content: "Comment \(number)", authorName: "A", isAgent: true, task: task))
            tasks.append(task)
        }
        fixture.context.insert(Comment(content: "Extra", authorName: "A", isAgent: true, task: tasks[0]))
        try fixture.context.save()
        print("T63_PROVIDER setup=\(setupStart.duration(to: .now))")
        let captureStart = ContinuousClock.now
        let view = try MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture)
            .capture(ReadCaptureRequest(projectSelectors: nil, selection: .portfolio,
                                        completeness: .completePortfolio, includeComments: false))
        print("T63_PROVIDER physical_capture=\(captureStart.duration(to: .now))")
        let encodingStart = ContinuousClock.now
        let bytes = try JSONEncoder().encode(view.tasks.map(\.fullRecordWithoutCommentsJSON))
        print("T63_PROVIDER frozen_record_encoding=\(encodingStart.duration(to: .now)) bytes=\(bytes.count)")
        #expect(view.tasks.count == 2_375 && view.comments.count == 2_376)
        #expect(view.tasks.allSatisfy { $0.revision != nil && $0.fullRecordWithoutCommentsJSON != nil })
        for model in [tasks[0], tasks[2_374]] {
            #expect(view.tasks.first { $0.id == model.id }?.revision
                    == (try MCPRecordSnapshot.task(model, in: fixture.context).revision))
        }
    }
}
#endif
