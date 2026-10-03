#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadCaptureBuilderTests {
    @Test func savedCaptureExcludesPendingUIEditsAndFreezesCanonicalRevision() throws {
        let fixture = try TestModelContainer()
        fixture.context.autosaveEnabled = false
        let project = Project(name: "Saved", description: "", gitRepo: nil, colorHex: "blue")
        let task = TransitTask(name: "Saved task", type: .feature, project: project, displayID: .permanent(63))
        let comment = Comment(content: "Saved comment", authorName: "Agent", isAgent: true, task: task)
        fixture.context.insert(project)
        fixture.context.insert(task)
        fixture.context.insert(comment)
        try fixture.context.save()
        let revision = try MCPRecordSnapshot.task(task, in: fixture.context).revision
        project.name = "Unsaved"
        task.name = "Unsaved task"
        comment.content = "Unsaved comment"
        let builder = MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture)
        let view = try builder.capture(portfolioRequest())
        #expect(view.projects.first?.name == "Saved")
        #expect(view.tasks.first?.name == "Saved task")
        #expect(view.tasks.first?.revision == revision)
        #expect(view.tasks.first?.requestedCommentRecordsJSON == nil)
        #expect(view.comments.first?.content == "Saved comment")
        #expect(view.tasks.first?.commentKeys == view.comments.map(\.physicalKey))
        #expect(view.tasks.first?.projectKey == view.projects.first?.physicalKey)
        #expect(fixture.context.hasChanges)
    }

    @Test func persistentHistoryRejectsSaveBetweenEntityFetches() throws {
        let fixture = try diskFixture()
        let project = Project(name: "Old", description: "", gitRepo: nil, colorHex: "blue")
        fixture.context.insert(project)
        try fixture.context.save()
        let builder = MCPReadCaptureBuilder(container: fixture.container, afterProjects: {
            project.name = "New"
            try fixture.context.save()
        })
        #expect(throws: MCPReadCaptureError.incoherentCapture) {
            try builder.capture(portfolioRequest())
        }
        let fresh = try MCPReadCaptureBuilder(container: fixture.container).capture(portfolioRequest())
        #expect(fresh.projects.first?.name == "New")
    }

    @Test func emptySelectionWithPurgedHistoryFailsClosed() throws {
        let fixture = try diskFixture()
        let project = Project(name: "Saved", description: "", gitRepo: nil, colorHex: "blue")
        fixture.context.insert(project)
        try fixture.context.save()
        try fixture.context.deleteHistory(HistoryDescriptor<DefaultHistoryTransaction>())
        #expect(throws: MCPReadCaptureError.incoherentCapture) {
            try MCPReadCaptureBuilder(container: fixture.container).capture(
                ReadCaptureRequest(projectSelectors: [.name("Missing")], selection: .portfolio,
                                   completeness: .completePortfolio, includeComments: false))
        }
    }

    @Test func trulyEmptyPersistentDomainCapturesEmptySuccessfully() throws {
        let fixture = try diskFixture()
        let view = try MCPReadCaptureBuilder(container: fixture.container).capture(portfolioRequest())
        #expect(view.projects.isEmpty && view.tasks.isEmpty && view.comments.isEmpty)
        #expect(!view.metadata.snapshotId.isEmpty)
        #expect(view.metadata.asOf == view.metadata.freshness.assessedAt)
    }

    @Test func duplicateTaskUUIDsKeepPhysicalCommentOwnership() throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        let first = TransitTask(name: "First", type: .feature, project: project, displayID: .permanent(1))
        let second = TransitTask(name: "Second", type: .feature, project: project, displayID: .permanent(2))
        second.id = first.id
        let firstComment = Comment(content: "First", authorName: "A", isAgent: true, task: first)
        let secondComment = Comment(content: "Second", authorName: "A", isAgent: true, task: second)
        fixture.context.insert(project)
        fixture.context.insert(first)
        fixture.context.insert(second)
        fixture.context.insert(firstComment)
        fixture.context.insert(secondComment)
        try fixture.context.save()
        let view = try MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture)
            .capture(portfolioRequest())
        for task in view.tasks {
            #expect(task.commentKeys == view.comments.filter { $0.taskKey == task.physicalKey }.map(\.physicalKey))
            #expect(task.commentKeys.count == 1)
            let model = task.name == "First" ? first : second
            #expect(task.revision == (try MCPRecordSnapshot.task(model, in: fixture.context).revision))
        }
    }

    @Test func importGenerationChangeRejectsCapture() throws {
        let fixture = try TestModelContainer()
        var generation: UInt64 = 0
        let builder = MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture,
                                            generation: { generation }, afterProjects: { generation += 1 })
        #expect(throws: MCPReadCaptureError.incoherentCapture) { try builder.capture(portfolioRequest()) }
    }

    @Test func scopedPortfolioRetainsForeignMilestoneAndOrphanIdentityClosure() throws {
        let fixture = try TestModelContainer()
        let selected = Project(name: "Selected", description: "", gitRepo: nil, colorHex: "blue")
        let foreign = Project(name: "Foreign", description: "", gitRepo: nil, colorHex: "green")
        let milestone = Milestone(name: "Foreign milestone", project: foreign, displayID: .permanent(1))
        let task = TransitTask(name: "Selected task", type: .feature, project: selected, displayID: .permanent(1))
        task.milestone = milestone
        let orphan = Comment(content: "Orphan", authorName: "A", isAgent: true, task: task)
        orphan.task = nil
        fixture.context.insert(selected)
        fixture.context.insert(foreign)
        fixture.context.insert(milestone)
        fixture.context.insert(task)
        fixture.context.insert(orphan)
        try fixture.context.save()
        let view = try MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture)
            .capture(ReadCaptureRequest(projectSelectors: [.id(selected.id)], selection: .portfolio,
                                        completeness: .completePortfolio, includeComments: false))
        let selectedKey = try #require(view.projects.first { $0.id == selected.id }?.physicalKey)
        #expect(view.captureScope == .projects([selectedKey]))
        #expect(view.tasks.first?.milestoneKey == view.milestones.first?.physicalKey)
        #expect(view.milestones.first?.storedProjectID == foreign.id)
        #expect(view.comments.first?.taskKey == nil)
        #expect(view.comments.first?.content == "Orphan")
    }

    private func portfolioRequest() -> ReadCaptureRequest {
        ReadCaptureRequest(projectSelectors: nil, selection: .portfolio,
                           completeness: .completePortfolio, includeComments: false)
    }

    private func diskFixture() throws -> TestModelContainer {
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self,
                             SyncHeartbeat.self, MCPWriteReceipt.self])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("fixture.store"),
                                        cloudKitDatabase: .none)
        return try TestModelContainer(schema: schema, configurations: [config])
    }
}
#endif
