#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct ConsolidationCaptureAggregateTests {
    @Test func emptySupplementaryHistoryDoesNotRecopySelectedTaskBodies() throws {
        let fixture = try TaskConsolidationCommitFixture()
        var commentFetches = 0
        let capture = TaskConsolidationSavedCapture(container: fixture.base.owner.container,
            fence: .actorOnlyTestFixture, hooks: .init(fetchComments: { _, _ in
                commentFetches += 1
                return []
            }))
        let ids = [fixture.base.source.id, fixture.base.target.id, fixture.extra.id]
        let evidence = try capture.copy(.init(selectedTaskIds: ids, requireSelectedOriginals: false),
            in: fixture.base.owner.context)
        #expect(evidence.selectedTaskIds == ids)
        #expect(evidence.originals.isEmpty && evidence.events.isEmpty && evidence.history.isEmpty)
        #expect(evidence.graph.tasks.count == 3 && commentFetches == 0)
        #expect(!fixture.base.owner.context.hasChanges && fixture.observation.commitSaves == 0)
    }

    @Test func whitespaceHeavyRawMetadataFitsItsMeasuredCompleteWrapperBudget() throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "isolated", description: "", gitRepo: nil, colorHex: "blue")
        let task = TransitTask(name: "original", type: .feature, project: project, displayID: .permanent(1))
        let spaces = String(repeating: " ", count: 20_000)
        let metadata = "{" + spaces + "\"k\":\"v\"" + spaces + "}"
        task.metadataJSON = metadata
        fixture.context.insert(project)
        fixture.context.insert(task)
        try fixture.context.save()
        let capture = TaskConsolidationSavedCapture(container: fixture.container, fence: .actorOnlyTestFixture)
        let measured = try capture.capture(selectedTaskIds: [task.id])
        let exact = try capture.capture(selectedTaskIds: [task.id],
            budget: TaskLinkGraphBudget(maximumBytes: measured.encodedByteCount))
        #expect(exact.encodedByteCount == measured.encodedByteCount)
        #expect(exact.originals.first?.fields.metadataJSON == metadata)
    }

    @Test func individuallyFittingOriginalsStopBeforeCollectingOversizedGroup() throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "isolated", description: "", gitRepo: nil, colorHex: "blue")
        fixture.context.insert(project)
        let tasks = (1...6).map { number in
            let task = TransitTask(name: "original \(number)", type: .feature, project: project,
                                   displayID: .permanent(number))
            task.taskDescription = String(repeating: "x", count: 4_000)
            fixture.context.insert(task)
            return task
        }
        try fixture.context.save()
        var commentFetches = 0
        let capture = TaskConsolidationSavedCapture(container: fixture.container, fence: .actorOnlyTestFixture,
            hooks: .init(fetchComments: { _, _ in commentFetches += 1; return [] }))
        let budget = TaskLinkGraphBudget(maximumBytes: 20_000)
        for task in tasks {
            #expect(try capture.capture(selectedTaskIds: [task.id], budget: budget).originals.count == 1)
        }
        commentFetches = 0
        #expect(throws: (any Error).self) {
            try capture.capture(selectedTaskIds: tasks.map(\.id), budget: budget)
        }
        #expect(commentFetches < tasks.count)
    }
}
#endif
