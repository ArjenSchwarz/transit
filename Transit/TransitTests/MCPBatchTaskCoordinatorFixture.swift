#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Owns persistent test stores for retained replay, restart and durable readback.
/// Stores outlive fixtures because TestModelContainer retains their containers.
@MainActor final class MCPBatchTaskCoordinatorFixture {
    enum Fault: Error { case injected }
    let directory: URL
    let storeURL: URL
    let owner: TestModelContainer
    let project: Project
    let tasks: [TransitTask]
    let services: MCPWriteCommandServices
    var coordinator: MCPWriteCoordinator?
    var now = Date(timeIntervalSince1970: 1_770_000_000)
    var preparation: @MainActor (MCPWriteCommand) async throws -> Void = { _ in }
    var failCommit = false
    var saveStages: [MCPWriteCoordinator.SaveStage] = []
    var recoveryCalls = 0
    private var independentOwners: [TestModelContainer] = []

    init(faultMilestoneReads: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("T2384Task9Coordinator-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("T2384_TASK9_COORDINATOR_DIRECTORY=" + directory.path)
        storeURL = directory.appendingPathComponent("coordinator.store")
        owner = try Self.owner(storeURL)
        owner.context.autosaveEnabled = false
        let savedProject = Project(name: "Batch project", description: "", gitRepo: nil, colorHex: "#112233")
        project = savedProject
        tasks = (0..<3).map {
            let task = TransitTask(name: "Task \($0)", type: .feature, project: savedProject,
                displayID: .permanent($0 + 1))
            task.id = UUID(uuidString: String(format: "ABCDEFAB-1234-4123-A123-%012d", $0 + 1))!
            return task
        }
        owner.context.insert(project)
        for task in tasks { owner.context.insert(task) }
        try owner.context.save()
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(), isCloudSyncActive: false)
        services = MCPWriteCommandServices(tasks: TaskService(modelContext: owner.context,
            displayIDAllocator: allocator),
            projects: ProjectService(modelContext: owner.context),
            comments: CommentService(modelContext: owner.context),
            milestones: MilestoneService(modelContext: owner.context, displayIDAllocator: allocator,
                fetcher: MCPBatchTaskCoordinatorMilestoneFetcher(context: owner.context, fail: faultMilestoneReads)),
            context: owner.context)
        restart()
    }

    static func owner(_ url: URL) throws -> TestModelContainer {
        let schema = Schema([Project.self, TransitTask.self, Transit.Comment.self, Milestone.self,
                             SyncHeartbeat.self, MCPWriteReceipt.self,
                             TaskLinkOccurrence.self, TaskLinkRemovalEvidence.self])
        return try TestModelContainer(schema: schema, configurations: [ModelConfiguration(
            "Task9", schema: schema, url: url, cloudKitDatabase: .none)])
    }

    func restart() {
        coordinator = nil
        coordinator = MCPWriteCoordinator(services: services,
            sidecarDirectory: directory.appendingPathComponent("keys"),
            persistence: PersistenceAvailability(), clock: { [unowned self] in now },
            save: { [unowned self] context, stage in
                saveStages.append(stage)
                if failCommit && stage == .commit { throw Fault.injected }
                try context.save()
            }, preparationHook: { [unowned self] command in try await preparation(command) },
            recoveryHook: { [unowned self] in recoveryCalls += 1 })
    }

    func item(_ index: Int, operation: String = "update_task", changes: [String: Any] = [:]) throws -> [String: Any] {
        var arguments: [String: Any] = ["taskId": tasks[index].id.uuidString,
                                      "idempotencyKey": "task9.key.\(index)"]
        if operation != "add_comment" {
            arguments["expectedRevision"] = try MCPRecordSnapshot.task(tasks[index], in: owner.context).revision
        }
        if operation == "update_task" { arguments["description"] = "Canonical description" }
        if operation == "update_task_status" {
            arguments["status"] = "done"
            arguments["comment"] = "Duplicate of canonical"
            arguments["authorName"] = "Agent"
        }
        if operation == "add_comment" {
            arguments.merge(["content": "Reason", "authorName": "Agent"]) { _, new in new }
        }
        arguments.merge(changes) { _, new in new }
        return ["itemId": "task9.original.\(index)", "operation": operation, "arguments": arguments]
    }

    func request(_ items: [[String: Any]]) throws -> MCPBatchTaskRequest {
        let data = try JSONSerialization.data(withJSONObject: ["mode": "execute", "items": items])
        guard case .valid(let request) = try MCPBatchTaskRequest.parse(MCPJSONDocument.parse(data)) else {
            throw MCPResultBoundaryError.invalidJSON
        }
        return request
    }

    func source(
        _ item: MCPBatchTaskRequest.Item, batchPolicy: MCPBatchWritePolicy? = .init()
    ) async throws -> MCPResultSource {
        let coordinator = try #require(coordinator)
        let result = await coordinator.execute(tool: item.command.tool,
            arguments: item.command.arguments, batchPolicy: batchPolicy)
        return try MCPResultAdapter.source(text: result.content[0].text, isError: result.isError,
            origin: .retainedJSON, evidence: .established)
    }

    func execution(_ item: MCPBatchTaskRequest.Item) async throws -> MCPBatchTaskCoordinator.Execution {
        var stopped = false
        let coordinator = try #require(coordinator)
        let policy = MCPBatchWritePolicy(onPendingEditsStop: { stopped = true })
        let result = await coordinator.execute(tool: item.command.tool, arguments: item.command.arguments,
                                               batchPolicy: policy)
        let source = try MCPResultAdapter.source(text: result.content[0].text, isError: result.isError,
            origin: .retainedJSON, evidence: .established)
        return .init(source: source, pendingEditsStop: stopped)
    }

    func durableTasks() throws -> [TransitTask] {
        let independent = try Self.owner(storeURL)
        independentOwners.append(independent)
        return try independent.context.fetch(FetchDescriptor<TransitTask>())
    }

    func durableComments() throws -> [Transit.Comment] {
        let independent = try Self.owner(storeURL)
        independentOwners.append(independent)
        return try independent.context.fetch(FetchDescriptor<Transit.Comment>())
    }
}
@MainActor private struct MCPBatchTaskCoordinatorMilestoneFetcher: ModelFetching {
    let context: ModelContext
    let fail: Bool

    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        if fail { throw MCPBatchTaskCoordinatorFixture.Fault.injected }
        return try context.fetch(descriptor)
    }
}
#endif
