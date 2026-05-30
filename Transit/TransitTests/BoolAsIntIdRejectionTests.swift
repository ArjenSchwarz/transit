import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1211: JSON boolean values must not be accepted as integer IDs.
///
/// `JSONSerialization` deserializes JSON `true`/`false` as `NSNumber` wrapping a `CFBoolean`.
/// Because `NSNumber` bridges to both `Bool`, `Int`, and `Double`, a plain `as? Int` cast
/// succeeds with values `1` (for true) and `0` (for false). Before this fix, supplying
/// `{"displayId": true}` would silently target T-1/M-1 instead of being rejected.
/// These tests verify that boolean values for `displayId` and `milestoneDisplayId` are
/// rejected with INVALID_INPUT across all Intent and MCP code paths.
@MainActor @Suite(.serialized)
struct BoolAsIntIdRejectionTests {

    // MARK: - Helpers

    private struct IntentServices {
        let task: TaskService
        let project: ProjectService
        let milestone: MilestoneService
        let context: ModelContext
    }

    private func makeIntentServices() throws -> IntentServices {
        let context = try TestModelContainer.newContext()
        let taskAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        return IntentServices(
            task: TaskService(modelContext: context, displayIDAllocator: taskAllocator),
            project: ProjectService(modelContext: context),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator),
            context: context
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - IntentHelpers.parseIntValue

    /// Boolean values delivered as `NSNumber(CFBoolean)` (the form `JSONSerialization`
    /// produces for `true`/`false`) must be rejected. Native Swift `Bool` literals must
    /// also be rejected for defence in depth.
    @Test func parseIntValueRejectsJSONBooleanTrue() throws {
        let json = try parseJSON("""
        {"displayId": true}
        """)
        // Before the fix this returned 1; expected behavior is nil so callers can reject.
        #expect(IntentHelpers.parseIntValue(json["displayId"]) == nil)
    }

    @Test func parseIntValueRejectsJSONBooleanFalse() throws {
        let json = try parseJSON("""
        {"displayId": false}
        """)
        // Before the fix this returned 0; expected behavior is nil so callers can reject.
        #expect(IntentHelpers.parseIntValue(json["displayId"]) == nil)
    }

    @Test func parseIntValueRejectsNativeBoolTrue() {
        // Native Bool — should also be rejected.
        #expect(IntentHelpers.parseIntValue(true) == nil)
    }

    @Test func parseIntValueRejectsNativeBoolFalse() {
        #expect(IntentHelpers.parseIntValue(false) == nil)
    }

    @Test func parseIntValueStillAcceptsInt() {
        #expect(IntentHelpers.parseIntValue(42) == 42)
    }

    @Test func parseIntValueStillAcceptsDouble() {
        #expect(IntentHelpers.parseIntValue(42.0) == 42)
    }

    @Test func parseIntValueStillAcceptsJSONInteger() throws {
        let json = try parseJSON("""
        {"displayId": 42}
        """)
        #expect(IntentHelpers.parseIntValue(json["displayId"]) == 42)
    }

    /// JSON integers `1` and `0` must continue to be accepted — they are distinct from
    /// JSON booleans `true`/`false` despite having the same underlying numeric value.
    @Test func parseIntValueStillAcceptsJSONIntegerOne() throws {
        let json = try parseJSON("""
        {"displayId": 1}
        """)
        #expect(IntentHelpers.parseIntValue(json["displayId"]) == 1)
    }

    @Test func parseIntValueStillAcceptsJSONIntegerZero() throws {
        let json = try parseJSON("""
        {"displayId": 0}
        """)
        #expect(IntentHelpers.parseIntValue(json["displayId"]) == 0)
    }

    // MARK: - Intent: resolveTask

    @Test func intentResolveTaskRejectsBooleanDisplayId() throws {
        let svc = try makeIntentServices()
        let project = makeProject(in: svc.context)
        let task = TransitTask(
            name: "Task 1", type: .feature, project: project,
            displayID: .permanent(1)
        )
        StatusEngine.initializeNewTask(task)
        svc.context.insert(task)

        let json = try parseJSON("""
        {"displayId": true}
        """)

        let result = IntentHelpers.resolveTask(from: json, taskService: svc.task)
        switch result {
        case .success:
            Issue.record("Expected failure but resolved to a task (likely T-1)")
        case .failure(let error):
            // Field-specific INVALID_INPUT, not a silent fallback to TASK_NOT_FOUND.
            #expect(error.json.contains("displayId must be an integer"))
        }
    }

    // MARK: - Intent: resolveMilestone

    @Test func intentResolveMilestoneRejectsBooleanDisplayId() throws {
        let svc = try makeIntentServices()
        let project = makeProject(in: svc.context)
        let milestone = Milestone(name: "Sprint 1", project: project, displayID: .permanent(1))
        svc.context.insert(milestone)

        let json = try parseJSON("""
        {"displayId": false}
        """)

        let result = IntentHelpers.resolveMilestone(
            from: json, milestoneService: svc.milestone, projectService: svc.project
        )
        switch result {
        case .success:
            Issue.record("Expected failure but resolved to a milestone (likely M-1 via 0/false)")
        case .failure(let error):
            #expect(error.json.contains("displayId must be an integer"))
        }
    }

    // MARK: - Intent: assignMilestone via milestoneDisplayId

    @Test func intentAssignMilestoneRejectsBooleanMilestoneDisplayId() throws {
        let svc = try makeIntentServices()
        let project = makeProject(in: svc.context)
        let task = TransitTask(
            name: "Task", type: .feature, project: project, displayID: .permanent(1)
        )
        StatusEngine.initializeNewTask(task)
        svc.context.insert(task)

        let milestone = Milestone(name: "Sprint 1", project: project, displayID: .permanent(1))
        svc.context.insert(milestone)

        let json = try parseJSON("""
        {"milestoneDisplayId": true}
        """)

        let error = IntentHelpers.assignMilestone(
            from: json, to: task, milestoneService: svc.milestone
        )
        #expect(error != nil)
        #expect(error?.contains("milestoneDisplayId must be an integer") == true)
        // Task must NOT have been assigned to M-1.
        #expect(task.milestone == nil)
    }

    // MARK: - CreateTaskIntent.execute via milestoneDisplayId
    /// T-1283: `CreateTaskIntent.execute` must reject a boolean `milestoneDisplayId` with
    /// INVALID_INPUT instead of silently assigning M-1 (`true` bridges to `Int(1)`).
    @Test func createTaskIntentRejectsBooleanMilestoneDisplayId() async throws {
        let svc = try makeIntentServices()
        let project = makeProject(in: svc.context)
        let milestone = Milestone(name: "Sprint 1", project: project, displayID: .permanent(1))
        svc.context.insert(milestone)
        let input = """
        {"name": "Task", "type": "bug", "project": "Test", "milestoneDisplayId": true}
        """
        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project, milestoneService: svc.milestone
        )
        #expect(result.contains("milestoneDisplayId must be an integer"))
        #expect(result.contains("INVALID_INPUT"))
        #expect(milestone.tasks?.isEmpty ?? true)
    }
}

// MARK: - MCP-Level Regression Tests

#if os(macOS)
@MainActor @Suite(.serialized)
struct BoolAsIntIdRejectionMCPTests {

    // Arguments are passed via `[String: Any]`. To reliably reproduce the
    // production behaviour (where `JSONSerialization` returns NSNumber wrapping
    // a `CFBoolean`), wrap booleans as `NSNumber(value:)` so the dispatch
    // receives the CFBoolean form rather than a native Swift `Bool`.
    private static let trueNum: NSNumber = NSNumber(value: true)
    private static let falseNum: NSNumber = NSNumber(value: false)

    // MARK: - query_tasks

    @Test func mcpQueryTasksRejectsBooleanDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": Self.trueNum]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    @Test func mcpQueryTasksRejectsBooleanMilestoneDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "Sprint", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["milestoneDisplayId": Self.falseNum]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneDisplayId must be an integer"))
    }

    // MARK: - query_milestones

    @Test func mcpQueryMilestonesRejectsBooleanDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "Sprint", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["displayId": Self.trueNum]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    // MARK: - update_task_status

    @Test func mcpUpdateStatusRejectsBooleanDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": Self.trueNum, "status": "planning"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    // MARK: - update_task

    @Test func mcpUpdateTaskRejectsBooleanDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": Self.falseNum]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    @Test func mcpUpdateTaskRejectsBooleanMilestoneDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: [
                "displayId": task.permanentDisplayId!,
                "milestoneDisplayId": Self.trueNum
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneDisplayId must be an integer"))
    }

    // MARK: - create_task

    @Test func mcpCreateTaskRejectsBooleanMilestoneDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "New Task",
                "type": "feature",
                "projectId": project.id.uuidString,
                "milestoneDisplayId": Self.trueNum
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneDisplayId must be an integer"))
    }

    // MARK: - add_comment

    @Test func mcpAddCommentRejectsBooleanDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "displayId": Self.trueNum,
                "content": "A comment",
                "authorName": "Agent"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    // MARK: - update_milestone

    @Test func mcpUpdateMilestoneRejectsBooleanDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["displayId": Self.falseNum, "name": "Updated"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    // MARK: - delete_milestone

    @Test func mcpDeleteMilestoneRejectsBooleanDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "delete_milestone",
            arguments: ["displayId": Self.trueNum]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }
}
#endif
