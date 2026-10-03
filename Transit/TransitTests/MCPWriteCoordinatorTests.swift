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
