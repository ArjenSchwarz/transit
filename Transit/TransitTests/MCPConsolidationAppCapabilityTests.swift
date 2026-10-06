#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized) struct MCPConsolidationAppCapabilityTests {
    @Test func composedAppOwnersExecuteAllFourToolsAndNativeHistory() async throws {
        let workflow = try ConsolidationAppWorkflowFixture()
        let fixture = workflow.fixture, handler = workflow.handler
        let context = fixture.base.base.owner.context
        #expect(handler.consolidationCapabilityInstalled)
        let first = try await workflow.read("preview_task_consolidation", fixture.arguments)
        let apply = try await workflow.write("consolidate_tasks", ["idempotencyKey": "app-apply",
            "reviewId": try #require(first["reviewId"]), "reviewRevision": try #require(first["reviewRevision"]),
            "preservationAcknowledged": true])
        #expect(apply["outcome"] as? String == "committed")
        let operation = try #require(apply["operationId"] as? String)
        let inverse = try await workflow.read("preview_task_consolidation_undo", ["operationId": operation,
            "readPolicy": "cached"])
        let undo = try await workflow.write("undo_task_consolidation", ["operationId": operation,
            "idempotencyKey": "app-undo", "reviewId": try #require(inverse["reviewId"]),
            "reviewRevision": try #require(inverse["reviewRevision"])])
        #expect(undo["outcome"] as? String == "committed")
        #expect(fixture.base.observation.commitSaves == 2)
        let native = TaskConsolidationNativeReader(container: context.container, coordinator: fixture.coordinator,
            fence: .actorOnlyTestFixture)
        #expect(native.coordinator === handler.readCoordinator)
        let observation = await native.read(fixture.base.base.source.id)
        #expect(observation.problem == nil && observation.history.count == 1)
        #expect(observation.history.first?.undoUnavailableReason == "already_reversed")
        #expect(try fixture.capture().events.count == 2)
    }

    @Test func overLimitNativeHistoryIsExplicitAndHasNoEffects() async throws {
        let workflow = try ConsolidationAppWorkflowFixture()
        let reader = TaskConsolidationNativeReader(container: workflow.fixture.base.base.owner.container,
            coordinator: workflow.fixture.coordinator, fence: .actorOnlyTestFixture, maximumBytes: 1)
        let value = await reader.read(workflow.fixture.base.base.source.id)
        #expect(value.history.isEmpty && value.problem?.contains("16 MiB") == true)
        #expect(workflow.fixture.base.observation.commitSaves == 0)
        #expect(try workflow.fixture.capture().events.isEmpty)
    }
}

@MainActor final class ConsolidationAppWorkflowFixture {
    let fixture: ConsolidationPreviewFixture
    let handler: MCPToolHandler

    init(resultEncoder: MCPResultProviderSelection.EncodeOutcome? = nil) throws {
        fixture = try ConsolidationPreviewFixture()
        let context = fixture.base.base.owner.context, allocator = fixture.base.base.allocator
        let tasks = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projects = ProjectService(modelContext: context)
        let comments = CommentService(modelContext: context)
        let milestones = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let maintenance = DisplayIDMaintenanceService(modelContext: context, taskAllocator: allocator,
            milestoneAllocator: allocator, commentService: comments)
        let capability = try #require(MCPConsolidationAppCapability(container: context.container,
            reads: fixture.service, coordinator: fixture.base.coordinator,
            taskAllocator: allocator, milestoneAllocator: allocator))
        handler = MCPToolHandler(taskService: tasks, projectService: projects, commentService: comments,
            milestoneService: milestones, maintenanceService: maintenance, settings: MCPSettings(),
            writeCoordinator: fixture.base.coordinator, readService: fixture.service,
            consolidationPreviewAdapter: capability.previews, consolidationWriteAdapter: capability.writes,
            consolidationResultEncoder: resultEncoder,
            readCoordinator: fixture.coordinator)
    }

    func read(_ tool: String, _ arguments: [String: Any]) async throws -> [String: Any] {
        let rpc = request(tool, arguments)
        let classified = try #require(MCPBoundedReadDispatcher.classify(rpc))
        let bytes = try await MCPBoundedReadDispatcher.response(for: classified, rpc: rpc, handler: handler,
            coordinator: fixture.coordinator, admittedAt: .now)
        let response = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let result = try #require(response["result"] as? [String: Any])
        let content = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        return try #require(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
    }

    func write(_ tool: String, _ arguments: [String: Any]) async throws -> [String: Any] {
        let result = await handler.protectedWriteResult(tool: tool, arguments: arguments)
        let text = try #require(result.content.first?.text)
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func request(_ tool: String, _ arguments: [String: Any]) -> JSONRPCRequest {
        JSONRPCRequest(jsonrpc: "2.0", id: .string("composed"), method: "tools/call",
            params: AnyCodable(["name": tool, "arguments": arguments] as [String: Any]))
    }
}
#endif
