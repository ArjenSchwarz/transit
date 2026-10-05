#if os(macOS)
import Foundation
import HTTPTypes
import Testing
@testable import Transit

/// Owns retained persistent stores for the entire fixture lifetime. No listener,
/// client activation, global defaults writes or production storage is involved.
@MainActor final class MCPBatchTaskModernFixture {
    let domain: MCPBatchTaskCoordinatorFixture
    let handler: MCPToolHandler

    init(fallback: Bool = false, missingCoordinator: Bool = false,
         encoder: MCPResultProviderSelection.EncodeOutcome? = nil) throws {
        let domain = try MCPBatchTaskCoordinatorFixture()
        self.domain = domain
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(), isCloudSyncActive: false)
        let maintenance = DisplayIDMaintenanceService(modelContext: domain.owner.context,
            taskAllocator: allocator, milestoneAllocator: allocator, commentService: domain.services.comments)
        handler = MCPToolHandler(taskService: domain.services.tasks, projectService: domain.services.projects,
            commentService: domain.services.comments, milestoneService: domain.services.milestones,
            maintenanceService: maintenance, settings: MCPSettings(),
            persistence: PersistenceAvailability(isFallbackStorageActive: fallback),
            writeCoordinator: missingCoordinator ? nil : domain.coordinator,
            batchContainer: domain.owner.container, batchResultEncoder: encoder)
    }

    func call(mode: String, items: [[String: Any]], id: Any = "batch.real.rpc") async throws -> MCPHTTPTestResponse {
        let params: [String: Any] = ["name": "mutate_tasks", "arguments": ["mode": mode, "items": items]]
        return try await raw(MCPModernResultFixture.body(method: "tools/call", id: id, parameters: params))
    }

    func raw(_ body: String) async throws -> MCPHTTPTestResponse {
        try await MCPModernResultFixture.transport(handler: handler, contentType: "application/json",
            accept: "application/json, text/event-stream", protocolVersion: "2026-07-28",
            orderedHeaders: [HTTPField(name: HTTPField.Name("Mcp-Method")!, value: "tools/call"),
                HTTPField(name: HTTPField.Name("Mcp-Name")!, value: "mutate_tasks")],
            body: body, loggerLabel: "t2384-real-batch")
    }

    static func payload(_ response: MCPHTTPTestResponse) throws -> MCPJSONValue {
        #expect(response.status == .ok)
        let document = try MCPJSONDocument.parse(response.body)
        let result = try #require(MCPBatchTaskResultFixtures.field("result", in: document.value))
        let structured = try #require(MCPBatchTaskResultFixtures.field("structuredContent", in: result))
        let source = try #require(MCPBatchTaskResultFixtures.field("source", in: structured))
        return try #require(MCPBatchTaskResultFixtures.field("payload", in: source))
    }
}
#endif
