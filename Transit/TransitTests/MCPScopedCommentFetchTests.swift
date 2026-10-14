#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPScopedCommentFetchTests {
    @Test func singleFullReadMaterializesOnlySelectedCommentsAndPreservesRevision() throws {
        let data = try fixture(unrelatedComments: 1_000)
        var fetched = 0
        let builder = MCPReadCaptureBuilder(container: data.owner.container, fetchComments: { context, descriptor in
            let values = try context.fetch(descriptor)
            fetched += values.count
            return values
        })
        let request = selected([data.tasks[0].id], comments: false)
        let view = try builder.capture(request)
        #expect(fetched == 2) // Regression: the old unscoped descriptor materializes all 1,002 rows.
        #expect(view.comments.count == 2)
        let task = try #require(view.tasks.first { $0.id == data.tasks[0].id })
        #expect(task.revision == (try MCPRecordSnapshot.task(data.tasks[0], in: data.owner.context).revision))
        #expect(task.requestedCommentRecordsJSON == nil)
        #expect(!data.owner.context.hasChanges)
    }

    @Test func batchAndDuplicateLogicalOwnersMatchUnscopedCapture() throws {
        let data = try fixture(unrelatedComments: 6)
        data.tasks[2].id = data.tasks[0].id
        data.comments[2].id = data.comments[0].id
        try data.owner.context.save()
        for include in [false, true] {
            let request = selected([data.tasks[0].id, data.tasks[1].id], comments: include)
            try compareWithUnscoped(request, owner: data.owner)
        }
    }

    @Test func onePhysicalOwnerStillIncludesForeignDuplicateLogicalComments() throws {
        let data = try fixture(unrelatedComments: 6)
        let foreign = Project(name: "Foreign", description: "", gitRepo: nil, colorHex: "red")
        data.owner.context.insert(foreign)
        data.tasks[2].id = data.tasks[0].id
        data.tasks[2].project = foreign
        try data.owner.context.save()
        let request = ReadCaptureRequest(projectSelectors: [.id(data.project.id)],
            selection: .tasks(detail: .fullRecord), completeness: .selectedRead, includeComments: true,
            selectTaskBodies: { values in Set(values.filter { $0.permanentDisplayId == 1 }.map(\.physicalKey)) })
        let view = try MCPReadCaptureBuilder(container: data.owner.container).capture(request)
        let task = try #require(view.tasks.first { $0.permanentDisplayId == 1 })
        #expect(task.commentKeys.count == 2)
        #expect(view.comments.count == 5) // Both physical owners belong to the canonical logical-ID evidence.
        #expect(view.comments.contains { $0.taskKey != task.physicalKey })
        #expect(task.revision == (try MCPRecordSnapshot.task(data.tasks[0], in: data.owner.context).revision))
        try compareWithUnscoped(request, owner: data.owner)
    }

    @Test func fullBulkAndSummaryCommentRequestsKeepEquivalentEvidence() throws {
        let data = try fixture(unrelatedComments: 6)
        let bulk = ReadCaptureRequest(projectSelectors: nil, selection: .tasks(detail: .fullRecord),
                                      completeness: .selectedRead, includeComments: true)
        try compareWithUnscoped(bulk, owner: data.owner)
        let id = data.tasks[0].id
        let summary = ReadCaptureRequest(projectSelectors: nil, selection: .tasks(detail: .summary),
            completeness: .selectedRead, includeComments: true,
            selectTaskBodies: { values in Set(values.filter { $0.id == id }.map(\.physicalKey)) })
        try compareWithUnscoped(summary, owner: data.owner)
        #expect(try MCPReadCaptureBuilder(container: data.owner.container).capture(summary).comments.count == 2)
    }

    @Test func reparentedEditedOrphanAndPendingCommentsKeepSavedSemantics() throws {
        let data = try fixture(unrelatedComments: 6)
        let request = selected([data.tasks[0].id], comments: true)
        let initial = try MCPReadCaptureBuilder(container: data.owner.container).capture(request)
        let oldRevision = initial.tasks.first { $0.id == data.tasks[0].id }?.revision
        data.comments[0].task = data.tasks[1]
        data.comments[1].task = nil
        data.comments[2].task = data.tasks[0]
        data.comments[2].content = "Saved edit"
        try data.owner.context.save()
        let savedRevision = try MCPRecordSnapshot.task(data.tasks[0], in: data.owner.context).revision
        #expect(savedRevision != oldRevision)
        data.comments[2].content = "Pending edit"
        data.comments[3].task = data.tasks[0]
        let view = try MCPReadCaptureBuilder(container: data.owner.container).capture(request)
        #expect(view.tasks.first { $0.id == data.tasks[0].id }?.revision == savedRevision)
        #expect(view.comments.count == 1 && view.comments.first?.content == "Saved edit")
        try compareWithUnscoped(request, owner: data.owner)
        #expect(data.owner.context.hasChanges)
    }

    @Test func completePortfoliosKeepOrphansAndProjectIdentityClosure() throws {
        let data = try fixture(unrelatedComments: 6)
        data.comments[0].task = nil
        try data.owner.context.save()
        for selectors: [ReadProjectSelector]? in [nil, [.id(data.project.id)]] {
            let request = ReadCaptureRequest(projectSelectors: selectors, selection: .portfolio,
                                             completeness: .completePortfolio, includeComments: true)
            var fetched = 0
            let view = try MCPReadCaptureBuilder(container: data.owner.container,
                fetchComments: { context, descriptor in
                    let values = try context.fetch(descriptor)
                    fetched += values.count
                    return values
                }).capture(request)
            #expect(fetched == data.comments.count)
            #expect(view.comments.contains { $0.taskKey == nil })
            try compareWithUnscoped(request, owner: data.owner)
        }
    }

    @Test func emptySelectionAndSummaryWithoutCommentsDoNotFetch() throws {
        let data = try fixture(unrelatedComments: 2)
        var calls = 0
        let builder = MCPReadCaptureBuilder(container: data.owner.container, fetchComments: { _, _ in
            calls += 1
            throw CocoaError(.fileReadUnknown)
        })
        let empty = try builder.capture(selected([UUID()], comments: false))
        #expect(empty.comments.isEmpty)
        let summary = ReadCaptureRequest(projectSelectors: nil, selection: .tasks(detail: .summary),
                                         completeness: .selectedRead, includeComments: false)
        #expect(try builder.capture(summary).comments.isEmpty)
        #expect(calls == 0)
        #expect(throws: MCPReadCaptureError.storageFailure) {
            try builder.capture(selected([data.tasks[0].id], comments: false))
        }
    }

    @Test func savedCommentChangeDuringFetchFailsHistoryFence() throws {
        let data = try fixture(unrelatedComments: 2)
        let builder = MCPReadCaptureBuilder(container: data.owner.container, fetchComments: { context, descriptor in
            let values = try context.fetch(descriptor)
            data.comments[0].content = "Concurrent saved edit"
            try data.owner.context.save()
            return values
        })
        #expect(throws: MCPReadCaptureError.incoherentCapture) {
            try builder.capture(selected([data.tasks[0].id], comments: false))
        }
        try compareWithUnscoped(selected([data.tasks[0].id], comments: false), owner: data.owner)
    }

    @Test func syntheticVolumeComparesScopedAndUnscopedMaterialization() throws {
        let data = try fixture(unrelatedComments: 5_000)
        let request = selected([data.tasks[0].id], comments: false)
        var scopedRows: [Int] = []
        var oldRows: [Int] = []
        let scoped = MCPReadCaptureBuilder(container: data.owner.container, fetchComments: { context, descriptor in
            let values = try context.fetch(descriptor)
            scopedRows.append(values.count)
            return values
        })
        let old = MCPReadCaptureBuilder(container: data.owner.container, fetchComments: { context, _ in
            let values = try context.fetch(FetchDescriptor<Transit.Comment>())
            oldRows.append(values.count)
            return values
        })
        let warm = try scoped.capture(request)
        _ = try old.capture(request)
        var scopedMs: [Double] = []
        var oldMs: [Double] = []
        for round in 0..<4 {
            for useScoped in round.isMultiple(of: 2) ? [true, false] : [false, true] {
                let start = ContinuousClock.now
                let view = try (useScoped ? scoped : old).capture(request)
                let elapsed = MCPReadTiming.seconds(start.duration(to: .now)) * 1_000
                if useScoped { scopedMs.append(elapsed) } else { oldMs.append(elapsed) }
                #expect(view.tasks.map(\.selectedRecordJSON) == warm.tasks.map(\.selectedRecordJSON))
                #expect(view.tasks.map(\.revision) == warm.tasks.map(\.revision))
                #expect(view.comments.map(\.selectedRecordJSON) == warm.comments.map(\.selectedRecordJSON))
            }
        }
        #expect(scopedRows == Array(repeating: 2, count: 5))
        #expect(oldRows == Array(repeating: 5_002, count: 5))
        let metrics: [String: Any] = ["scopedRows": scopedRows, "baselineRows": oldRows,
                                      "scopedMs": scopedMs, "baselineMs": oldMs]
        let encoded = try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys])
        print("T2455_SCOPED_COST \(String(decoding: encoded, as: UTF8.self))")
        #expect(!data.owner.context.hasChanges)
    }

    private func selected(_ ids: [UUID], comments: Bool) -> ReadCaptureRequest {
        ReadCaptureRequest(projectSelectors: nil, selection: .tasks(detail: .fullRecord),
            completeness: .selectedRead, includeComments: comments, selectTaskBodies: { values in
                Set(values.filter { ids.contains($0.id) }.map(\.physicalKey))
            })
    }

    private func compareWithUnscoped(_ request: ReadCaptureRequest, owner: TestModelContainer) throws {
        let scoped = try MCPReadCaptureBuilder(container: owner.container).capture(request)
        let old = try MCPReadCaptureBuilder(container: owner.container, fetchComments: { context, _ in
            try context.fetch(FetchDescriptor<Transit.Comment>())
        }).capture(request)
        #expect(scoped.tasks.map(\.physicalKey) == old.tasks.map(\.physicalKey))
        for task in scoped.tasks {
            let previous = try #require(old.tasks.first { $0.physicalKey == task.physicalKey })
            #expect(task.revision == previous.revision)
            #expect(task.selectedRecordJSON == previous.selectedRecordJSON)
            #expect(task.commentKeys == previous.commentKeys)
            #expect(task.requestedCommentRecordsJSON == previous.requestedCommentRecordsJSON)
        }
        #expect(scoped.comments.map(\.physicalKey) == old.comments.map(\.physicalKey))
        #expect(scoped.comments.map(\.selectedRecordJSON) == old.comments.map(\.selectedRecordJSON))
    }

    private struct Fixture {
        let owner: TestModelContainer
        let project: Project
        let tasks: [TransitTask]
        let comments: [Transit.Comment]
    }

    private func fixture(unrelatedComments: Int) throws -> Fixture {
        let schema = Schema([Project.self, TransitTask.self, Transit.Comment.self, Milestone.self,
                             SyncHeartbeat.self, MCPWriteReceipt.self, TaskLinkOccurrence.self,
                             TaskLinkRemovalEvidence.self, TaskConsolidationEvent.self])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("fixture.store"),
                                        cloudKitDatabase: .none)
        let owner = try TestModelContainer(schema: schema, configurations: [config])
        owner.context.autosaveEnabled = false
        let project = Project(name: "Synthetic", description: "", gitRepo: nil, colorHex: "blue")
        owner.context.insert(project)
        let tasks = (1...3).map { index in
            let task = TransitTask(name: "Task \(index)", type: .feature, project: project,
                                   displayID: .permanent(index))
            owner.context.insert(task)
            return task
        }
        var comments: [Transit.Comment] = []
        for index in 0..<(2 + unrelatedComments) {
            let comment = Transit.Comment(content: "Comment \(index)", authorName: "Fixture", isAgent: true,
                                          task: tasks[index < 2 ? 0 : (index % 2 + 1)])
            owner.context.insert(comment)
            comments.append(comment)
        }
        try owner.context.save()
        return Fixture(owner: owner, project: project, tasks: tasks, comments: comments)
    }
}
#endif
