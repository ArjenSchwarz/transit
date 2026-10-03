#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPWriteCoordinatorTests {
    @Test func requiredSafetyAndUnknownFieldsReserveNothing() throws {
        for tool in MCPWriteCommand.protectedTools {
            #expect(throws: (any Error).self) { try MCPWriteCommand.validate(tool: tool, arguments: [:]) }
            #expect(throws: (any Error).self) {
                try MCPWriteCommand.validate(tool: tool, arguments: ["idempotencyKey": "key", "unknown": 1])
            }
        }
    }

    // swiftlint:disable:next function_body_length
    @Test func malformedTerminalReplayFailsClosed() async throws {
        let fixture = try MCPWriteCoordinatorTestFixture()
        let services = fixture.services
        let coordinator = fixture.coordinator!
        let projectArgs: [String: Any] = [
            "name": "malformed P", "colorHex": "#112233", "idempotencyKey": "malformed-project"
        ]
        let project = try fixture.decode(await coordinator.execute(tool: "create_project", arguments: projectArgs))
        let task = try await services.tasks.createTask(
            name: "malformed T", description: nil, type: .feature,
            project: services.projects.findProject(id: UUID(uuidString: project["entityId"] as? String ?? "")!)
                .get())
        let statusArgs: [String: Any] = [
            "taskId": task.id.uuidString, "status": "done", "comment": "C",
            "authorName": "A", "expectedRevision": try MCPRecordSnapshot.task(task, in: services.context).revision,
            "idempotencyKey": "malformed-status"
        ]
        let status = try fixture.decode(
            await coordinator.execute(tool: "update_task_status", arguments: statusArgs))
        var conflictArgs = statusArgs
        conflictArgs["idempotencyKey"] = "malformed-conflict"
        let conflict = try fixture.decode(
            await coordinator.execute(tool: "update_task_status", arguments: conflictArgs))
        let milestone = try await services.milestones.createMilestone(
            name: "malformed M", description: nil, project: task.project!)
        let deleteArgs: [String: Any] = [
            "milestoneId": milestone.id.uuidString,
            "expectedRevision": try MCPRecordSnapshot.milestone(milestone).revision,
            "idempotencyKey": "malformed-delete"
        ]
        let deletion = try fixture.decode(
            await coordinator.execute(tool: "delete_milestone", arguments: deleteArgs))
        let rejectArgs: [String: Any] = [
            "name": "reject", "colorHex": "invalid", "idempotencyKey": "malformed-reject"
        ]
        let rejection = try fixture.decode(await coordinator.execute(tool: "create_project", arguments: rejectArgs))
        let cases: [((String, [String: Any]), ([String: Any], [String]))] = [
            (
                ("create_project", projectArgs),
                (
                    project,
                    [
                        "entityId", "record", "record.revision", "record.name", "completedAt", "replayExpiresAt",
                        "completedAtMismatch", "entityIdMismatch"
                    ]
                )
            ),
            (
                ("update_task_status", statusArgs),
                (status, ["record.comments", "record.creationDate", "comment", "comment.revision"])
            ),
            (
                ("delete_milestone", deleteArgs),
                (deletion, ["deleted", "recordBeforeDeletion", "recordBeforeDeletion.revision"])
            ),
            (("update_task_status", conflictArgs), (conflict, ["currentRecord", "currentRecord.revision"])),
            (("create_project", rejectArgs), (rejection, ["error", "error.code", "error.message", "retryAction"]))
        ]
        for ((tool, args), (original, fields)) in cases {
            let receipt = try services.context.fetch(FetchDescriptor<MCPWriteReceipt>()).first {
                $0.key == args["idempotencyKey"] as? String
            }!
            let saved = receipt.resultJSON!
            for field in fields {
                var malformed = original
                let components = field.split(separator: ".").map(String.init)
                if field == "completedAtMismatch" {
                    malformed["completedAt"] = MCPRecordSnapshot.timestamp(.distantPast)
                } else if field == "entityIdMismatch" {
                    malformed["entityId"] = UUID().uuidString
                } else if components.count == 2 {
                    var record = try #require(malformed[components[0]] as? [String: Any])
                    record.removeValue(forKey: components[1])
                    malformed[components[0]] = record
                } else {
                    malformed.removeValue(forKey: field)
                }
                receipt.resultJSON = try MCPWriteOutcome.encode(malformed)
                try services.context.save()
                let result = try fixture.decode(await coordinator.execute(tool: tool, arguments: args))
                #expect(result["outcome"] as? String == "uncertain")
                #expect((result["error"] as? [String: Any])?["code"] as? String == "OUTCOME_UNCERTAIN")
                #expect(result["retryAction"] as? String == "reconcile")
                #expect(receipt.resultJSON == (try MCPWriteOutcome.encode(malformed)))
                let files = try FileManager.default.contentsOfDirectory(
                    at: fixture.directory.appendingPathComponent("guards"),
                    includingPropertiesForKeys: nil)
                let bindings = try files.filter { $0.pathExtension == "json" }.map {
                    try JSONDecoder().decode(MCPLocalReservation.self, from: Data(contentsOf: $0))
                }
                #expect(bindings.contains { $0.tool == tool && $0.key == args["idempotencyKey"] as? String })
            }
            receipt.resultJSON = saved
            try services.context.save()
            let replay = try fixture.decode(await coordinator.execute(tool: tool, arguments: args))
            let identical = try MCPCanonicalJSON.encode(replay) == MCPCanonicalJSON.encode(original)
            #expect(identical)
        }
    }

    @Test func committedReplayPreservesSavedProjectionAfterEdit() async throws {
        let fixture = try MCPWriteCoordinatorTestFixture()
        let args: [String: Any] = ["name": " original ", "colorHex": "#112233", "idempotencyKey": "key"]
        let first = await fixture.coordinator.execute(tool: "create_project", arguments: args)
        let project = try #require(try fixture.owner.context.fetch(FetchDescriptor<Project>()).first)
        project.name = "changed later"
        try fixture.owner.context.save()
        let replay = await fixture.coordinator.execute(tool: "create_project", arguments: args)
        #expect(first.content.first?.text == replay.content.first?.text)
        #expect(try fixture.owner.context.fetch(FetchDescriptor<Project>()).count == 1)
    }

    @Test func staleStatusWithCommentPreservesInterveningEdit() async throws {
        let fixture = try MCPWriteCoordinatorTestFixture()
        let context = fixture.owner.context
        let project = try fixture.services.projects.createProject(
            name: "P", description: "", gitRepo: nil,
            colorHex: "#112233")
        let task = try await fixture.services.tasks.createTask(
            name: "T", description: nil, type: .feature, project: project)
        let oldRevision = try MCPRecordSnapshot.task(task, in: context).revision
        task.name = "UI edit"
        try context.save()
        let result = await fixture.coordinator.execute(
            tool: "update_task_status",
            arguments: [
                "taskId": task.id.uuidString, "status": "done", "comment": "must not appear", "authorName": "A",
                "expectedRevision": oldRevision, "idempotencyKey": "conflict"
            ])
        let envelope = try fixture.decode(result)
        #expect((envelope["error"] as? [String: Any])?["code"] as? String == "REVISION_CONFLICT")
        #expect(task.name == "UI edit" && task.status == .idea)
        #expect(try context.fetch(FetchDescriptor<Transit.Comment>()).isEmpty)
        #expect(envelope["replayExpiresAt"] is String)
    }

    @Test func missingReceiptDoesNotRunAgainAcrossRestart() async throws {
        let fixture = try MCPWriteCoordinatorTestFixture()
        let args: [String: Any] = ["name": "P", "colorHex": "#112233", "idempotencyKey": "missing"]
        _ = await fixture.coordinator.execute(tool: "create_project", arguments: args)
        let receipt = try #require(try fixture.owner.context.fetch(FetchDescriptor<MCPWriteReceipt>()).first)
        fixture.owner.context.delete(receipt)
        try fixture.owner.context.save()
        fixture.coordinator = nil
        fixture.coordinator = MCPWriteCoordinator(services: fixture.services, sidecarDirectory: fixture.directory)
        let envelope = try fixture.decode(
            await fixture.coordinator.execute(tool: "create_project", arguments: args))
        #expect(envelope["outcome"] as? String == "uncertain")
        #expect(envelope["retryAction"] as? String == "reconcile")
        #expect(try fixture.owner.context.fetch(FetchDescriptor<Project>()).count == 1)
    }
}

@MainActor private final class MCPWriteCoordinatorTestFixture {
    let owner: TestModelContainer
    let directory: URL
    let services: MCPWriteCommandServices
    var coordinator: MCPWriteCoordinator!

    init() throws {
        owner = try TestModelContainer()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context = owner.context
        context.autosaveEnabled = false
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(), isCloudSyncActive: false)
        services = MCPWriteCommandServices(
            tasks: TaskService(modelContext: context, displayIDAllocator: allocator),
            projects: ProjectService(modelContext: context), comments: CommentService(modelContext: context),
            milestones: MilestoneService(modelContext: context, displayIDAllocator: allocator), context: context
        )
        coordinator = MCPWriteCoordinator(services: services, sidecarDirectory: directory)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func decode(_ result: MCPToolResult) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(result.content[0].text.utf8)) as? [String: Any])
    }
}
#endif
