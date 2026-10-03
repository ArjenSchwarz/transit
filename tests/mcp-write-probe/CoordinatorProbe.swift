import Foundation
import SwiftData

@main
struct MCPWriteCoordinatorProbe {
    // swiftlint:disable:next function_body_length
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([
            Project.self, TransitTask.self, Comment.self, Milestone.self,
            SyncHeartbeat.self, MCPWriteReceipt.self
        ])
        let configuration = ModelConfiguration(
            schema: schema, url: directory.appendingPathComponent("probe.store"),
            cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        context.autosaveEnabled = false
        let allocator = DisplayIDAllocator(store: CoordinatorCounter(), isCloudSyncActive: false)
        let tasks = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projects = ProjectService(modelContext: context)
        let comments = CommentService(modelContext: context)
        let milestones = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let services = MCPWriteCommandServices(
            tasks: tasks, projects: projects, comments: comments,
            milestones: milestones, context: context)
        var coordinator: MCPWriteCoordinator? = MCPWriteCoordinator(
            services: services, sidecarDirectory: directory.appendingPathComponent("sidecar")
        )
        let projectArgs: [String: Any] = ["name": " P ", "colorHex": "#112233", "idempotencyKey": "project"]
        let first = try decode(await coordinator!.execute(tool: "create_project", arguments: projectArgs))
        precondition(first["outcome"] as? String == "committed")
        let project = try context.fetch(FetchDescriptor<Project>())[0]
        precondition(project.name == "P")
        project.name = "later edit"
        try context.save()
        let replay = try decode(await coordinator!.execute(tool: "create_project", arguments: projectArgs))
        let sameReplay = try MCPCanonicalJSON.encode(first) == MCPCanonicalJSON.encode(replay)
        precondition(sameReplay)
        let taskArgs: [String: Any] = [
            "name": "T", "type": "feature", "projectId": project.id.uuidString,
            "idempotencyKey": "task"
        ]
        let created = try decode(await coordinator!.execute(tool: "create_task", arguments: taskArgs))
        precondition(created["outcome"] as? String == "committed")
        let task = try context.fetch(FetchDescriptor<TransitTask>())[0]
        let revision = try MCPRecordSnapshot.task(task, in: context).revision
        let statusArgs: [String: Any] = [
            "taskId": task.id.uuidString, "status": "done", "comment": "saved",
            "authorName": "agent", "expectedRevision": revision,
            "idempotencyKey": "status"
        ]
        let status = try decode(await coordinator!.execute(tool: "update_task_status", arguments: statusArgs))
        precondition(status["outcome"] as? String == "committed")
        precondition(task.status == .done)
        let savedComments = try context.fetch(FetchDescriptor<Comment>())
        precondition(savedComments.count == 1)
        var stale = statusArgs
        stale["idempotencyKey"] = "stale"
        let conflict = try decode(await coordinator!.execute(tool: "update_task_status", arguments: stale))
        precondition((conflict["error"] as? [String: Any])?["code"] as? String == "REVISION_CONFLICT")
        let noMoreComments = try context.fetch(FetchDescriptor<Comment>())
        precondition(noMoreComments.count == 1)
        coordinator = nil
        coordinator = MCPWriteCoordinator(
            services: services,
            sidecarDirectory: directory.appendingPathComponent("sidecar"))
        let restarted = try decode(await coordinator!.execute(tool: "update_task_status", arguments: statusArgs))
        let sameRestarted = try MCPCanonicalJSON.encode(status) == MCPCanonicalJSON.encode(restarted)
        precondition(sameRestarted)
        context.delete(task)
        try context.save()
        let deletedReplay = try decode(await coordinator!.execute(tool: "create_task", arguments: taskArgs))
        let sameDeletedreplay = try MCPCanonicalJSON.encode(created) == MCPCanonicalJSON.encode(deletedReplay)
        precondition(sameDeletedreplay)
        let receipt = try context.fetch(FetchDescriptor<MCPWriteReceipt>()).first { $0.key == "task" }!
        context.delete(receipt)
        try context.save()
        let uncertain = try decode(await coordinator!.execute(tool: "create_task", arguments: taskArgs))
        precondition((uncertain["error"] as? [String: Any])?["code"] as? String == "OUTCOME_UNCERTAIN")
        let noRepeatedTasks = try context.fetch(FetchDescriptor<TransitTask>())
        precondition(noRepeatedTasks.isEmpty)
        print("PASS real-service coordinator commit/replay/restart/deleted-target/conflict/uncertainty")
        coordinator = nil
        try await remainingCommands(services: services, directory: directory)
        try await faults(services: services, directory: directory)
        try await activeKeys(services: services, directory: directory)
        try await expiryAndAvailability(services: services, directory: directory)
        try await malformedTerminals(services: services, directory: directory)
        try await phaseSuspension(services: services, directory: directory)
        integerBoundaries()
        schemas()
    }

    // swiftlint:disable:next function_body_length
    @MainActor static func remainingCommands(services: MCPWriteCommandServices, directory: URL) async throws {
        let coordinator = MCPWriteCoordinator(
            services: services, sidecarDirectory: directory.appendingPathComponent("all-tools"))
        let project = try services.projects.createProject(
            name: "all-tools", description: "", gitRepo: nil, colorHex: "red")
        let context = services.context
        let create = try decode(
            await coordinator.execute(
                tool: "create_milestone",
                arguments: [
                    "projectId": project.id.uuidString, "name": "M", "idempotencyKey": "m"
                ]))
        precondition(create["outcome"] as? String == "committed")
        let milestone = try context.fetch(FetchDescriptor<Milestone>()).first { $0.project?.id == project.id }!
        let task = try await services.tasks.createTask(
            name: "T", description: nil, type: .feature, project: project)
        let comment = try decode(
            await coordinator.execute(
                tool: "add_comment",
                arguments: [
                    "taskId": task.id.uuidString, "content": "C", "authorName": "agent", "idempotencyKey": "c"
                ]))
        precondition(comment["outcome"] as? String == "committed")
        let mixedMetadata: [String: Any] = [
            "name": "metadata", "type": "feature", "projectId": project.id.uuidString,
            "metadata": ["owner": "sam", "count": 4, "labels": ["one"]],
            "idempotencyKey": "mixed-metadata"
        ]
        let metadataResult = try decode(await coordinator.execute(tool: "create_task", arguments: mixedMetadata))
        precondition(metadataResult["outcome"] as? String == "committed")
        let metadataRecord = metadataResult["record"] as? [String: Any]
        precondition(metadataRecord?["metadata"] as? [String: String] == ["owner": "sam"])
        let metadataReplay = try decode(await coordinator.execute(tool: "create_task", arguments: mixedMetadata))
        let identicalMetadataReplay =
            try MCPCanonicalJSON.encode(metadataResult) == MCPCanonicalJSON.encode(metadataReplay)
        precondition(identicalMetadataReplay)
        try await distinctNumericMetadata(coordinator: coordinator, metadata: mixedMetadata)
        print("PASS mixed metadata retains original retry payload and drops nonstring domain entries")
        let revision = try MCPRecordSnapshot.task(task, in: context).revision
        let update = try decode(
            await coordinator.execute(
                tool: "update_task",
                arguments: [
                    "taskId": task.id.uuidString, "name": "edited", "expectedRevision": revision,
                    "idempotencyKey": "u"
                ]))
        precondition(update["outcome"] as? String == "committed" && task.name == "edited")
        let milestoneRevision = try MCPRecordSnapshot.milestone(milestone).revision
        let updatedMilestone = try decode(
            await coordinator.execute(
                tool: "update_milestone",
                arguments: [
                    "milestoneId": milestone.id.uuidString, "name": "edited milestone",
                    "expectedRevision": milestoneRevision,
                    "idempotencyKey": "um"
                ]))
        precondition(updatedMilestone["outcome"] as? String == "committed")
        let before = try MCPRecordSnapshot.milestone(milestone)
        let deleted = try decode(
            await coordinator.execute(
                tool: "delete_milestone",
                arguments: [
                    "milestoneId": milestone.id.uuidString, "expectedRevision": before.revision,
                    "idempotencyKey": "dm"
                ]))
        precondition(deleted["deleted"] as? Bool == true)
        precondition((deleted["recordBeforeDeletion"] as? [String: Any])?["revision"] as? String == before.revision)
        print("PASS all eight command families and milestone deletion preimage")
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    @MainActor static func faults(services: MCPWriteCommandServices, directory: URL) async throws {
        let context = services.context
        for kind in ["before", "after", "serialize", "recovery", "acceptance", "baseline"] {
            var fired = false
            var pendingProject: Project?
            let coordinator = MCPWriteCoordinator(
                services: services, sidecarDirectory: directory.appendingPathComponent(kind),
                save: { context, stage in
                    if kind == "acceptance", stage == .acceptance, !fired {
                        fired = true
                        throw CocoaError(.fileWriteUnknown)
                    }
                    if kind == "baseline", stage == .baseline, !fired {
                        fired = true
                        throw CocoaError(.fileWriteUnknown)
                    }
                    if ["before", "after", "recovery"].contains(kind), stage == .commit, !fired {
                        fired = true
                        if kind == "after" { try context.save() }
                        throw CocoaError(.fileWriteUnknown)
                    }
                    try context.save()
                },
                encode: { envelope in
                    if kind == "serialize", envelope["outcome"] as? String == "committed", !fired {
                        fired = true
                        throw CocoaError(.coderInvalidValue)
                    }
                    return try MCPWriteOutcome.encode(envelope)
                },
                recoveryHook: { if kind == "recovery" { throw CocoaError(.fileReadUnknown) } }
            )
            if kind == "baseline" {
                let userEdit = try context.fetch(FetchDescriptor<Project>())[0]
                userEdit.name = "pending user edit"
                pendingProject = userEdit
            }
            let args: [String: Any] = ["name": "fault-" + kind, "colorHex": "#112233", "idempotencyKey": kind]
            let outcome = try decode(await coordinator.execute(tool: "create_project", arguments: args))
            precondition(
                outcome["outcome"] as? String
                    == (kind == "after" ? "committed" : kind == "recovery" ? "uncertain" : "rejected"))
            if kind == "baseline" {
                precondition(outcome["accepted"] as? Bool == false && context.hasChanges)
                precondition(pendingProject?.name == "pending user edit")
            }
            try context.save()
            let freshProjects = try ModelContext(context.container).fetch(FetchDescriptor<Project>())
            if let pendingProject {
                precondition(freshProjects.first { $0.id == pendingProject.id }?.name == "pending user edit")
            }
            precondition(freshProjects.contains { $0.name == "fault-" + kind } == (kind == "after"))
            if kind != "baseline" {
                let replay = try decode(await coordinator.execute(tool: "create_project", arguments: args))
                precondition(replay["outcome"] as? String == outcome["outcome"] as? String)
            }
        }
        print(
            "PASS commit-before/after-throw; serialization/recovery/acceptance faults; pending baseline edits survive"
        )
    }

    @MainActor static func activeKeys(services: MCPWriteCommandServices, directory: URL) async throws {
        let gate = CoordinatorGate()
        let coordinator = MCPWriteCoordinator(
            services: services,
            sidecarDirectory: directory.appendingPathComponent("active"),
            preparationHook: { _ in await gate.park() })
        let args: [String: Any] = ["name": "active", "colorHex": "#112233", "idempotencyKey": "active"]
        let first = Task { await coordinator.execute(tool: "create_project", arguments: args) }
        await gate.waitForStart()
        let concurrent = try decode(await coordinator.execute(tool: "create_project", arguments: args))
        precondition(concurrent["outcome"] as? String == "in_progress")
        var mismatched = args
        mismatched["name"] = "different"
        let mismatch = try decode(await coordinator.execute(tool: "create_project", arguments: mismatched))
        precondition((mismatch["error"] as? [String: Any])?["code"] as? String == "IDEMPOTENCY_KEY_REUSED")
        await gate.release()
        let committed = try decode(await first.value)
        precondition(committed["outcome"] as? String == "committed")
        print("PASS suspended concurrent matching/mismatched keys")
    }

    @MainActor static func decode(_ result: MCPToolResult) throws -> [String: Any] {
        guard
            let decoded = try JSONSerialization.jsonObject(with: Data(result.content[0].text.utf8))
                as? [String: Any]
        else {
            throw CocoaError(.coderInvalidValue)
        }
        return decoded
    }

}

extension MCPWriteCoordinatorProbe {
    @MainActor static func schemas() {
        for definition in MCPToolDefinitions.coreTools
        where MCPWriteCommand.protectedTools.contains(definition.name) {
            precondition(definition.inputSchema.required?.contains("idempotencyKey") == true)
            if MCPWriteCommand.revisionTools.contains(definition.name) {
                precondition(definition.inputSchema.required?.contains("expectedRevision") == true)
            }
        }
        print("PASS eight protected published schemas and four required preconditions")
    }

    @MainActor static func expiryAndAvailability(services: MCPWriteCommandServices, directory: URL) async throws {
        var now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let coordinator = MCPWriteCoordinator(
            services: services,
            sidecarDirectory: directory.appendingPathComponent("expiry"), clock: { now })
        let args: [String: Any] = ["name": "expiry", "colorHex": "#112233", "idempotencyKey": "expiry"]
        let first = try decode(await coordinator.execute(tool: "create_project", arguments: args))
        now = now.addingTimeInterval(604799)
        let replay = try decode(await coordinator.execute(tool: "create_project", arguments: args))
        precondition(first["replayExpiresAt"] as? String == replay["replayExpiresAt"] as? String)
        now = now.addingTimeInterval(1)
        var next = args
        next["name"] = "reused after expiry"
        let expired = try decode(await coordinator.execute(tool: "create_project", arguments: next))
        precondition(expired["outcome"] as? String == "committed")
        let badDirectory = directory.appendingPathComponent("unreadable")
        try FileManager.default.createDirectory(at: badDirectory, withIntermediateDirectories: true)
        try Data("broken scope".utf8).write(to: badDirectory.appendingPathComponent("scope"))
        let unreadable = MCPWriteCoordinator(services: services, sidecarDirectory: badDirectory)
        let uncertain = try decode(await unreadable.execute(tool: "create_project", arguments: args))
        precondition(uncertain["accepted"] is NSNull && uncertain["outcome"] as? String == "uncertain")
        let busy = MCPWriteCoordinator(
            services: services, sidecarDirectory: directory.appendingPathComponent("expiry"))
        let contention = try decode(await busy.execute(tool: "create_project", arguments: args))
        precondition((contention["error"] as? [String: Any])?["code"] as? String == "STORE_BUSY")
        print(
            "PASS fixed seven-day expiry and fresh acceptance after removal; unreadable null acceptance; busy scope"
        )
    }
}

actor CoordinatorCounter {}
extension CoordinatorCounter: DisplayIDAllocator.CounterStore {
    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        .init(nextDisplayID: 1, changeTag: "probe")
    }
    func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws {}
}

actor CoordinatorGate {
    private var parked: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var started = false
    func park() async {
        started = true
        waiter?.resume()
        waiter = nil
        await withCheckedContinuation { parked = $0 }
    }
    func waitForStart() async {
        if !started { await withCheckedContinuation { waiter = $0 } }
    }
    func release() {
        parked?.resume()
        parked = nil
    }
}

extension MCPWriteCoordinatorProbe {
    @MainActor static func distinctNumericMetadata(
        coordinator: MCPWriteCoordinator, metadata: [String: Any]
    ) async throws {
        var differentNumericMetadata = metadata
        differentNumericMetadata["metadata"] = ["owner": "sam", "count": 1.0000000000000002]
        differentNumericMetadata["idempotencyKey"] = "adjacent-metadata"
        differentNumericMetadata["name"] = "adjacent metadata"
        let numericFirst = try decode(
            await coordinator.execute(tool: "create_task", arguments: differentNumericMetadata))
        precondition(numericFirst["outcome"] as? String == "committed")
        differentNumericMetadata["metadata"] = ["owner": "sam", "count": 1.0000000000000004]
        let reusedNumber = try decode(
            await coordinator.execute(tool: "create_task", arguments: differentNumericMetadata))
        precondition((reusedNumber["error"] as? [String: Any])?["code"] as? String == "IDEMPOTENCY_KEY_REUSED")
    }
}
