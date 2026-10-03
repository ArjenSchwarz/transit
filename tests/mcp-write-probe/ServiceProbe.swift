import Foundation
import SwiftData

@main
struct MCPWriteServiceProbe {
    // swiftlint:disable:next function_body_length
    @MainActor static func main() async throws {
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self,
                             SyncHeartbeat.self, MCPWriteReceipt.self])
        let config = ModelConfiguration("service-probe", schema: schema,
                                        isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = container.mainContext
        context.autosaveEnabled = false
        let allocator = DisplayIDAllocator(store: ProbeCounter(), isCloudSyncActive: false)
        let tasks = TaskService(modelContext: context, displayIDAllocator: allocator)
        let milestones = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let projects = ProjectService(modelContext: context)
        let project = try projects.createProject(name: " P ", description: "", gitRepo: nil,
                                                  colorHex: "red", save: false)
        precondition(context.hasChanges)
        let unsavedProjects = try ModelContext(container).fetch(FetchDescriptor<Project>())
        precondition(unsavedProjects.isEmpty)
        try context.save()
        let milestonePlan = try await milestones.prepareMilestoneCreation(name: " M ", description: nil,
                                                                           project: project)
        let beforeInsert = try context.fetch(FetchDescriptor<Milestone>())
        precondition(beforeInsert.isEmpty)
        let milestone = try milestones.applyMilestoneCreation(milestonePlan)
        try context.save()
        let taskPlan = try await tasks.prepareTaskCreation(name: " T ", description: nil, type: .feature,
                                                           project: project, milestone: milestone)
        let noTasks = try context.fetch(FetchDescriptor<TransitTask>())
        precondition(noTasks.isEmpty)
        milestone.statusRawValue = MilestoneStatus.done.rawValue
        try context.save()
        do {
            _ = try tasks.applyTaskCreation(taskPlan)
            preconditionFailure("Closed milestone must reject prepared task")
        } catch TaskService.Error.milestoneNotOpen { }
        milestone.statusRawValue = MilestoneStatus.open.rawValue
        try context.save()
        let task = try tasks.applyTaskCreation(taskPlan)
        precondition(task.name == "T" && context.hasChanges)
        try context.save()
        let comments = CommentService(modelContext: context)
        let comment = try tasks.updateStatus(task: task, to: .planning, comment: "hello",
                                              commentAuthor: "agent", commentService: comments, save: false)
        precondition(comment != nil)
        let durable = ModelContext(container)
        let savedTask = try durable.fetch(FetchDescriptor<TransitTask>()).first!
        let savedComments = try durable.fetch(FetchDescriptor<Comment>())
        precondition(savedTask.status == .idea && savedComments.isEmpty)
        try context.save()
        let saved = ModelContext(container)
        let committedTask = try saved.fetch(FetchDescriptor<TransitTask>()).first!
        let committedComments = try saved.fetch(FetchDescriptor<Comment>())
        precondition(committedTask.status == .planning && committedComments.count == 1)
        let duplicatePlan = try await milestones.prepareMilestoneCreation(name: "competing", description: nil,
                                                                           project: project)
        _ = try await milestones.createMilestone(name: "COMPETING", description: nil, project: project)
        do {
            _ = try milestones.applyMilestoneCreation(duplicatePlan)
            preconditionFailure("Competing name must reject")
        } catch MilestoneService.Error.duplicateName { }
        try milestones.deleteMilestone(milestone, save: false)
        let beforeDeletionSave = try ModelContext(container).fetch(FetchDescriptor<Milestone>())
        precondition(beforeDeletionSave.contains { $0.id == milestone.id })
        try context.save()
        let afterDeletionSave = try ModelContext(container).fetch(FetchDescriptor<Milestone>())
        precondition(!afterDeletionSave.contains { $0.id == milestone.id })
        let orphanPlan = try await tasks.prepareTaskCreation(name: "orphan", description: nil,
                                                             type: .feature, project: project)
        context.delete(project)
        try context.save()
        do {
            _ = try tasks.applyTaskCreation(orphanPlan)
            preconditionFailure("Missing pinned project must reject")
        } catch TaskService.Error.projectNotFound { }
        try await suspendedAllocation(container: container, context: context)
        print("PASS preparation has no inserts; pinned references/name revalidate; "
              + "deferred project/delete/status-comment save")
    }

    // swiftlint:disable:next function_body_length
    @MainActor static func suspendedAllocation(container: ModelContainer, context: ModelContext) async throws {
        let project = Project(name: "suspended", description: "", gitRepo: nil, colorHex: "red")
        context.insert(project)
        let milestone = Milestone(name: "open", project: project, displayID: .permanent(80))
        context.insert(milestone)
        try context.save()
        let counter = SuspendedProbeCounter()
        let tasks = TaskService(modelContext: context, displayIDAllocator: DisplayIDAllocator(store: counter))
        let operation = Task {
            try await tasks.prepareTaskCreation(name: "suspended task", description: nil, type: .feature,
                                                 project: project, milestone: milestone)
        }
        await counter.waitForLoad()
        let before = try context.fetch(FetchDescriptor<TransitTask>()).count
        milestone.project = nil
        try context.save()
        await counter.release()
        let prepared = try await operation.value
        do {
            _ = try tasks.applyTaskCreation(prepared)
            preconditionFailure("Reassignment during allocation must reject")
        } catch TaskService.Error.milestoneProjectMismatch { }
        let after = try context.fetch(FetchDescriptor<TransitTask>()).count
        precondition(before == after)
        let cancelCounter = SuspendedProbeCounter()
        let cancelService = TaskService(modelContext: context,
                                        displayIDAllocator: DisplayIDAllocator(store: cancelCounter))
        let cancelled = Task {
            try await cancelService.createTask(name: "cancelled", description: nil, type: .feature, project: project)
        }
        await cancelCounter.waitForLoad()
        cancelled.cancel()
        await cancelCounter.release()
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancellation must prevent insert")
        } catch is CancellationError { }
        let afterCancellation = try context.fetch(FetchDescriptor<TransitTask>()).count
        precondition(before == afterCancellation)
        let deleteCounter = SuspendedProbeCounter()
        let milestones = MilestoneService(modelContext: context,
                                           displayIDAllocator: DisplayIDAllocator(store: deleteCounter))
        let deleted = Task { try await milestones.createMilestone(name: "missing", description: nil, project: project) }
        await deleteCounter.waitForLoad()
        let peer = ModelContext(container)
        let projectID = project.id
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectID })
        if let record = try peer.fetch(descriptor).first { peer.delete(record); try peer.save() }
        await deleteCounter.release()
        do {
            _ = try await deleted.value
            preconditionFailure("Peer deletion during allocation must reject")
        } catch MilestoneService.Error.projectNotFound { }
        print("PASS real suspended allocation: milestone reassignment, cancellation, peer project deletion")
    }

}

private actor ProbeCounter: DisplayIDAllocator.CounterStore {
    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        .init(nextDisplayID: 1, changeTag: nil)
    }
    func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws { }
}

private actor SuspendedProbeCounter: DisplayIDAllocator.CounterStore {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private var started = false

    func waitForLoad() async {
        if started { return }
        await withCheckedContinuation { observer = $0 }
    }

    func release() { continuation?.resume(); continuation = nil }

    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        started = true
        observer?.resume()
        observer = nil
        await withCheckedContinuation { continuation = $0 }
        return .init(nextDisplayID: 100, changeTag: nil)
    }

    func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws { }
}
