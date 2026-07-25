#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1818: while `ContainerFactory` is serving the in-memory fallback
/// container, mutating MCP tools must return a tool error instead of a success payload for a
/// write that disappears on the next launch. An MCP client never sees the app's
/// degraded-storage alert, so a successful response is indistinguishable from durable
/// persistence.
///
/// The signal under test is derived from a real `ContainerFactory` failure via
/// `FallbackOutcomeFixture`, exactly as `TransitApp.init()` does at launch. Data assertions run
/// against isolated `TestModelContainer` contexts — see the fixture for why the fallback
/// container itself must not be used as a test store.
@MainActor
@Suite(.serialized)
struct MCPFallbackStorageRejectionTests {

    private struct Env {
        let handler: MCPToolHandler
        let context: ModelContext
        let persistence: PersistenceAvailability
    }

    private func makeEnv(failPrimaryStore: Bool = true) throws -> Env {
        let persistence = failPrimaryStore
            ? FallbackOutcomeFixture.degraded
            : FallbackOutcomeFixture.makeHealthy()

        let context = try TestModelContainer.newContext()
        let taskAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let commentService = CommentService(modelContext: context)
        let settings = MCPSettings()
        settings.maintenanceToolsEnabled = true

        let handler = MCPToolHandler(
            taskService: TaskService(modelContext: context, displayIDAllocator: taskAllocator),
            projectService: ProjectService(modelContext: context),
            commentService: commentService,
            milestoneService: MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator),
            maintenanceService: DisplayIDMaintenanceService(
                modelContext: context,
                taskAllocator: taskAllocator,
                milestoneAllocator: milestoneAllocator,
                commentService: commentService
            ),
            settings: settings,
            persistence: persistence
        )
        return Env(handler: handler, context: context, persistence: persistence)
    }

    @discardableResult
    private func seedProjectAndTask(in context: ModelContext) -> (Project, TransitTask) {
        let project = Project(name: "Fallback Project", description: "", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        let task = TransitTask(name: "Seeded Task", type: .bug, project: project, displayID: .permanent(1))
        context.insert(task)
        let milestone = Milestone(name: "Seeded Milestone", project: project, displayID: .permanent(1))
        context.insert(milestone)
        return (project, task)
    }

    // MARK: - Mutating Tools Are Rejected

    /// Every mutating tool, exercised with arguments that would otherwise succeed.
    /// Read-only tools are deliberately absent — see `readToolsStillWork`.
    private static func mutatingCalls() -> [(tool: String, args: [String: Any])] {
        [
            ("create_task", ["name": "Doomed", "type": "bug", "project": "Fallback Project"]),
            ("update_task_status", ["displayId": 1, "status": "in-progress"]),
            ("update_task", ["displayId": 1, "priority": "high"]),
            ("add_comment", ["displayId": 1, "content": "Doomed comment", "authorName": "Agent"]),
            ("create_milestone", ["name": "Doomed Milestone", "project": "Fallback Project"]),
            ("update_milestone", ["displayId": 1, "status": "done"]),
            ("delete_milestone", ["displayId": 1]),
            ("reassign_duplicate_display_ids", [:])
        ]
    }

    @Test("Mutating MCP tools are rejected while fallback storage is active")
    func mutatingToolsRejected() async throws {
        // Looped rather than parameterized: `[String: Any]` arguments are not Sendable,
        // which `@Test(arguments:)` requires.
        for call in Self.mutatingCalls() {
            let env = try makeEnv()
            seedProjectAndTask(in: env.context)

            let response = await env.handler.handle(
                MCPTestHelpers.toolCallRequest(tool: call.tool, arguments: call.args)
            )

            #expect(try MCPTestHelpers.isError(response), "\(call.tool) should be rejected")
            #expect(
                try MCPTestHelpers.errorText(response) == PersistenceAvailability.unavailableHint,
                "\(call.tool) should return the shared degraded-storage hint"
            )
        }
    }

    @Test("Rejected create_task writes nothing")
    func rejectedCreateLeavesStoreUntouched() async throws {
        let env = try makeEnv()
        let project = Project(name: "Fallback Project", description: "", gitRepo: nil, colorHex: "#FF0000")
        env.context.insert(project)

        _ = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["name": "Doomed", "type": "bug", "project": "Fallback Project"]
        ))

        #expect(try env.context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }

    @Test("Rejected update_task_status leaves the task untouched")
    func rejectedUpdateLeavesTaskUntouched() async throws {
        let env = try makeEnv()
        let (_, task) = seedProjectAndTask(in: env.context)

        _ = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status", arguments: ["displayId": 1, "status": "done"]
        ))

        #expect(task.statusRawValue == TaskStatus.idea.rawValue)
        #expect(task.completionDate == nil)
    }

    // MARK: - Reads Stay Available

    @Test("Read-only MCP tools keep working while fallback storage is active")
    func readToolsStillWork() async throws {
        let env = try makeEnv()
        seedProjectAndTask(in: env.context)

        let tasks = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(tool: "query_tasks", arguments: [:])
        )
        #expect(try MCPTestHelpers.isError(tasks) == false)
        #expect(try MCPTestHelpers.decodeArrayResult(tasks).count == 1)

        let projects = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(tool: "get_projects", arguments: [:])
        )
        #expect(try MCPTestHelpers.isError(projects) == false)

        let milestones = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(tool: "query_milestones", arguments: [:])
        )
        #expect(try MCPTestHelpers.isError(milestones) == false)

        let scan = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(tool: "scan_duplicate_display_ids", arguments: [:])
        )
        #expect(try MCPTestHelpers.isError(scan) == false)
    }

    // MARK: - Healthy Storage Baseline

    @Test("Mutating MCP tools still work when storage is durable")
    func mutationsAllowedWhenDurable() async throws {
        let env = try makeEnv(failPrimaryStore: false)
        let project = Project(name: "Fallback Project", description: "", gitRepo: nil, colorHex: "#FF0000")
        env.context.insert(project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["name": "Fine", "type": "bug", "project": "Fallback Project"]
        ))

        #expect(try MCPTestHelpers.isError(response) == false)
        #expect(try env.context.fetch(FetchDescriptor<TransitTask>()).count == 1)
    }
}
#endif
