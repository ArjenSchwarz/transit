#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// The real shared protected handler/coordinator route with the production
/// feature adapter. No test code inserts graph changes on behalf of the SUT.
@MainActor struct TaskLinkWriteFixture {
    let base: TaskLinkCommitDiskFixture
    let coordinator: MCPWriteCoordinator
    let handler: MCPToolHandler

    init(base: TaskLinkCommitDiskFixture,
         save: @escaping @MainActor (ModelContext, MCPWriteCoordinator.SaveStage) throws -> Void =
            { context, _ in try context.save() },
         encode: @escaping @MainActor ([String: Any]) throws -> String = MCPWriteOutcome.encode,
         preparation: @escaping @MainActor (MCPWriteCommand) async throws -> Void = { _ in }) {
        self.base = base
        coordinator = base.coordinator(save: save, encode: encode, preparation: preparation)
        let context = base.owner.context
        let tasks = TaskService(modelContext: context, displayIDAllocator: base.allocator)
        let projects = ProjectService(modelContext: context)
        let comments = CommentService(modelContext: context)
        let milestones = MilestoneService(modelContext: context, displayIDAllocator: base.allocator)
        let maintenance = DisplayIDMaintenanceService(modelContext: context, taskAllocator: base.allocator,
            milestoneAllocator: base.allocator, commentService: comments)
        handler = MCPToolHandler(taskService: tasks, projectService: projects, commentService: comments,
            milestoneService: milestones, maintenanceService: maintenance, settings: MCPSettings(),
            persistence: PersistenceAvailability(isFallbackStorageActive: false), writeCoordinator: coordinator,
            batchContainer: base.owner.container,
            taskLinkWriteAdapter: TaskLinkWriteAdapter(taskAllocator: base.allocator,
                                                     milestoneAllocator: base.allocator))
    }

    func revision(_ id: UUID) throws -> String {
        let observer = try base.observer()
        return try MCPRecordSnapshot.task(base.task(id, in: observer.context), in: observer.context).revision
    }

    func addition(type: String = "relates-to", key: String = "linked") throws -> [String: Any] {
        ["taskId": base.source.id.uuidString, "expectedRevision": try revision(base.source.id),
         "idempotencyKey": key, "linkChanges": [["action": "add", "type": type,
                                                "targetTaskId": base.target.id.uuidString]],
         "endpointPreconditions": [["taskId": base.target.id.uuidString,
                                    "expectedRevision": try revision(base.target.id)]]]
    }

    func removal(key: String = "remove") throws -> [String: Any] {
        let edge = base.edge
        let value = TaskLinkOccurrenceValue(physicalKey: Data(), id: edge.id, kind: edge.kindRawValue,
            source: edge.sourceTaskID, target: edge.targetTaskID, createdAt: edge.createdAt)
        return ["taskId": base.source.id.uuidString, "expectedRevision": try revision(base.source.id),
                "idempotencyKey": key, "linkChanges": [["action": "remove", "edgeId": edge.id.uuidString,
                    "occurrenceRevision": try TaskLinkGraph.occurrenceRevision(value)]],
                "endpointPreconditions": [["taskId": base.target.id.uuidString,
                                           "expectedRevision": try revision(base.target.id)]]]
    }

    func execute(_ arguments: [String: Any], tool: String = "update_task") async -> MCPToolResult {
        await handler.protectedWriteResult(tool: tool, arguments: arguments)
    }

    func receipts(for arguments: [String: Any], in context: ModelContext) throws -> [MCPWriteReceipt] {
        let key = try #require(arguments["idempotencyKey"] as? String)
        return try context.fetch(FetchDescriptor<MCPWriteReceipt>(predicate: #Predicate { $0.key == key }))
    }

    func assertOutcome(_ result: MCPToolResult, _ outcome: String, accepted: Bool = true) throws {
        let value = try base.decode(result)
        #expect(value["outcome"] as? String == outcome)
        #expect(value["accepted"] as? Bool == accepted)
    }
}
#endif
