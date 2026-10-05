#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Persistent saved evidence with a separate dirty UI context. No coordinator,
/// sidecar, recovery store or write admission is constructed by this fixture.
@MainActor final class MCPBatchTaskPreviewFixture {
    enum Fault: Error { case injected }
    let directory: URL
    let storeURL: URL
    let owner: TestModelContainer
    let project: Project
    let targets: [TransitTask]
    let deletion: TransitTask
    let milestone: Milestone
    let comment: Transit.Comment
    let deletedComment: Transit.Comment
    let deletedMilestone: Milestone
    let markerURL: URL
    let marker = Data("preview must not touch reservation evidence".utf8)
    private var savedTaskEvidence: [UUID: String] = [:]
    private var savedCommentEvidence: [UUID: String] = [:]
    private var savedMilestoneEvidence: [UUID: String] = [:]
    var pending: TransitTask?
    var taskReads = 0
    var commentReads = 0
    var milestoneReads = 0
    var privateContexts: [ModelContext] = []
    var taskFault: UUID?
    var commentFault: UUID?
    var milestoneFault = false
    var forcedMatches: Int?
    var failEveryCommentRead = false
    var pendingComment: Transit.Comment?
    var pendingMilestone: Milestone?

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("T2384Task7Preview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("T2384_TASK7_PREVIEW_DIRECTORY=" + directory.path)
        storeURL = directory.appendingPathComponent("preview.store")
        markerURL = directory.appendingPathComponent("untouched.guard")
        owner = try Self.diskOwner(storeURL)
        let savedProject = Project(name: "Saved project", description: "", gitRepo: nil, colorHex: "#112233")
        project = savedProject
        targets = (1...3).map {
            TransitTask(name: "Saved \($0)", type: .feature, project: savedProject, displayID: .permanent($0))
        }
        deletion = TransitTask(name: "Saved deletion", type: .feature, project: project, displayID: .permanent(4))
        milestone = Milestone(name: "Saved milestone", project: project, displayID: .permanent(9))
        comment = Comment(content: "Saved full comment", authorName: "Saved author", isAgent: true, task: targets[0])
        deletedComment = Comment(content: "Saved deleted comment", authorName: "Saved author",
                                 isAgent: true, task: targets[0])
        deletedMilestone = Milestone(name: "Saved deleted milestone", project: project, displayID: .permanent(10))
        owner.context.insert(project)
        for task in targets + [deletion] { owner.context.insert(task) }
        owner.context.insert(milestone)
        owner.context.insert(comment)
        owner.context.insert(deletedComment)
        owner.context.insert(deletedMilestone)
        try owner.context.save()
        try marker.write(to: markerURL)
        for task in targets + [deletion] {
            let snapshot = try MCPRecordSnapshot.task(task, in: owner.context)
            savedTaskEvidence[task.id] = try MCPCanonicalJSON.encode(snapshot.coveredFields)
        }
        for value in [comment, deletedComment] {
            savedCommentEvidence[value.id] = try MCPCanonicalJSON.encode(MCPRecordSnapshot.comment(value).coveredFields)
        }
        for value in [milestone, deletedMilestone] {
            let snapshot = try MCPRecordSnapshot.milestone(value)
            savedMilestoneEvidence[value.id] = try MCPCanonicalJSON.encode(snapshot.coveredFields)
        }
    }

    // TestModelContainer retains every container for the test process lifetime.
    // Its backing files must outlive this fixture too. The pinned off-process
    // cleanup consumes only the marker above after all owned hosts drain.

    static func diskOwner(_ url: URL) throws -> TestModelContainer {
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self,
                             SyncHeartbeat.self, MCPWriteReceipt.self])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let owner = try TestModelContainer(schema: schema, configurations: [configuration])
        owner.context.autosaveEnabled = false
        return owner
    }

    func revision(_ index: Int = 0) throws -> String {
        try MCPRecordSnapshot.task(targets[index], in: owner.context).revision
    }

    func item(_ index: Int = 0, operation: String = "update_task",
              changes: [String: Any] = [:]) throws -> [String: Any] {
        var arguments: [String: Any] = ["taskId": targets[index].id.uuidString,
                                        "idempotencyKey": "preview.\(index)"]
        if operation != "add_comment" { arguments["expectedRevision"] = try revision(index) }
        if operation == "update_task_status" { arguments["status"] = "done" }
        if operation == "add_comment" {
            arguments["content"] = " reason "
            arguments["authorName"] = " agent "
        }
        arguments.merge(changes) { _, new in new }
        return ["itemId": "original.\(index)", "operation": operation, "arguments": arguments]
    }

    func request(_ items: [[String: Any]]) throws -> MCPBatchTaskRequest {
        try MCPBatchTaskRequestFixtures.valid(MCPBatchTaskRequestFixtures.document(mode: "dry_run", items: items))
    }

    func reads() -> MCPBatchTaskPreview.Reads {
        MCPBatchTaskPreview.Reads(tasks: { [unowned self] descriptor, context in
            observe(context, pending: descriptor.includePendingChanges)
            taskReads += 1
            let matches = try context.fetch(descriptor)
            if let taskFault, matches.contains(where: { $0.id == taskFault }) { throw Fault.injected }
            if let forcedMatches {
                return Array(matches.prefix(1)).flatMap { Array(repeating: $0, count: forcedMatches) }
            }
            return matches
        }, comments: { [unowned self] descriptor, context in
            observe(context, pending: descriptor.includePendingChanges)
            commentReads += 1
            if failEveryCommentRead { throw Fault.injected }
            let matches = try context.fetch(descriptor)
            if let commentFault, matches.contains(where: { $0.task?.id == commentFault }) { throw Fault.injected }
            return matches
        }, milestones: { [unowned self] context in
            PreviewMilestoneFetcher(context: context, fixture: self)
        })
    }

    func observe(_ context: ModelContext, pending: Bool) {
        #expect(context !== owner.context)
        #expect(!context.autosaveEnabled)
        #expect(!pending)
        #expect(!context.hasChanges)
        if !privateContexts.contains(where: { $0 === context }) { privateContexts.append(context) }
    }

    func makePending(autosave: Bool) {
        targets[0].name = "UI unsaved edit"
        owner.context.delete(deletion)
        let task = TransitTask(name: "UI unsaved insert", type: .feature, project: project, displayID: .provisional)
        owner.context.insert(task)
        pending = task
        comment.content = "UI unsaved comment edit"
        owner.context.delete(deletedComment)
        let insertedComment = Comment(content: "UI unsaved comment insert", authorName: "UI",
                                      isAgent: false, task: targets[0])
        owner.context.insert(insertedComment)
        pendingComment = insertedComment
        milestone.name = "UI unsaved milestone edit"
        owner.context.delete(deletedMilestone)
        let insertedMilestone = Milestone(name: "UI unsaved milestone insert", project: project,
                                         displayID: .permanent(11))
        owner.context.insert(insertedMilestone)
        pendingMilestone = insertedMilestone
        owner.context.autosaveEnabled = autosave
    }

    func assertUntouched(autosave: Bool? = nil) throws {
        #expect(try Data(contentsOf: markerURL) == marker)
        #expect(privateContexts.allSatisfy { !$0.hasChanges && !$0.autosaveEnabled })
        #expect(try owner.context.fetch(FetchDescriptor<MCPWriteReceipt>()).isEmpty)
        if let autosave {
            #expect(owner.context.autosaveEnabled == autosave)
            #expect(owner.context.hasChanges)
            #expect(targets[0].name == "UI unsaved edit")
            #expect(owner.context.insertedModelsArray.contains { $0 === pending })
            #expect(owner.context.deletedModelsArray.contains { $0 === deletion })
            #expect(comment.content == "UI unsaved comment edit")
            #expect(milestone.name == "UI unsaved milestone edit")
            #expect(owner.context.insertedModelsArray.contains { $0 === pendingComment })
            #expect(owner.context.insertedModelsArray.contains { $0 === pendingMilestone })
            #expect(owner.context.deletedModelsArray.contains { $0 === deletedComment })
            #expect(owner.context.deletedModelsArray.contains { $0 === deletedMilestone })
        }
        let durable = try Self.diskOwner(storeURL)
        let tasks = try durable.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.count == 4)
        #expect(tasks.first { $0.id == targets[0].id }?.name == "Saved 1")
        #expect(tasks.contains { $0.id == deletion.id })
        #expect(!tasks.contains { $0.name == "UI unsaved insert" })
        for task in tasks {
            let snapshot = try MCPRecordSnapshot.task(task, in: durable.context)
            #expect(try MCPCanonicalJSON.encode(snapshot.coveredFields) == savedTaskEvidence[task.id])
        }
        let comments = try durable.context.fetch(FetchDescriptor<Transit.Comment>())
        #expect(comments.count == 2)
        #expect(comments.first { $0.id == comment.id }?.content == "Saved full comment")
        #expect(comments.contains { $0.id == deletedComment.id })
        for value in comments {
            let snapshot = try MCPRecordSnapshot.comment(value)
            #expect(try MCPCanonicalJSON.encode(snapshot.coveredFields) == savedCommentEvidence[value.id])
        }
        let milestones = try durable.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.count == 2)
        #expect(milestones.first { $0.id == milestone.id }?.name == "Saved milestone")
        #expect(milestones.contains { $0.id == deletedMilestone.id })
        for value in milestones {
            let snapshot = try MCPRecordSnapshot.milestone(value)
            #expect(try MCPCanonicalJSON.encode(snapshot.coveredFields) == savedMilestoneEvidence[value.id])
        }
        #expect(try durable.context.fetch(FetchDescriptor<Project>()).count == 1)
        #expect(try durable.context.fetch(FetchDescriptor<SyncHeartbeat>()).isEmpty)
        #expect(try durable.context.fetch(FetchDescriptor<MCPWriteReceipt>()).isEmpty)
    }

    func verifyPendingAfterReturn(autosave: Bool) {
        do {
            try assertUntouched(autosave: autosave)
        } catch { Issue.record("Pending/durable verification failed: \(error)") }
    }

    func preview(_ items: [[String: Any]], includeComments: Bool = true,
                 fallback: Bool = false) throws -> MCPBatchTaskPreview.Report {
        try MCPBatchTaskPreview.evaluate(request(items), container: owner.container,
            persistence: PersistenceAvailability(isFallbackStorageActive: fallback),
            includeComments: includeComments, reads: reads())
    }

    static func field(_ name: String, _ document: MCPJSONDocument?) -> MCPJSONValue? {
        MCPBatchTaskRequestFixtures.field(name, in: document?.value)
    }
}

@MainActor private struct PreviewMilestoneFetcher: ModelFetching {
    let context: ModelContext
    unowned let fixture: MCPBatchTaskPreviewFixture

    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        fixture.observe(context, pending: descriptor.includePendingChanges)
        fixture.milestoneReads += 1
        if fixture.milestoneFault { throw MCPBatchTaskPreviewFixture.Fault.injected }
        return try context.fetch(descriptor)
    }
}
#endif
